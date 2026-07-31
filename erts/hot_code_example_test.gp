package erts

import (
	"math/big"
	"testing"

	"goforge.dev/goplus/std/memory"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

func hotCodeModule(digest string) *beam.Module { return &beam.Module{Name: "sample", Digest: digest} }
var _ memory.Handle

// assayxport:unit gotp.erts.hot-code-laws
func TestForcedHotCodePurgeExitsEachOldCodeProcessOnce(t *testing.T) {
	exits := map[term.PID]int{}
	capability := HotCodeExitWith(func(pid term.PID, reason term.Term) kernel.Delivery {
		if !term.Equal(reason, term.MustAtom("killed")) { t.Fatalf("reason = %v", reason) }
		exits[pid]++
		return kernel.Delivered()
	})
	var runtime *HotCodeRuntime
	match NewHotCodeRuntime(capability) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(created): runtime = created }
	match runtime.Install(hotCodeModule("v1")) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	first := term.PID{Node: 1, Number: 1, Creation: 1}
	second := term.PID{Node: 1, Number: 2, Creation: 1}
	match runtime.Enter(first, "sample") { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	match runtime.Enter(first, "sample") { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	match runtime.Enter(second, "sample") { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	match runtime.Install(hotCodeModule("v2")) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	soft := runtime.SoftPurge("sample")
	match soft.State { case beam.OldCodeVersionBusy(references): if references != 3 { t.Fatalf("references = %d", references) }; case _: t.Fatalf("soft purge state = %v", soft.State) }
	if len(exits) != 0 { t.Fatalf("soft purge exited processes: %v", exits) }
	forced := runtime.Purge("sample")
	if forced.Exited != 2 || exits[first] != 1 || exits[second] != 1 { t.Fatalf("forced purge exits = %v, report = %d", exits, forced.Exited) }
}

func TestHotCodeLeaveRequiresReferenceOwnership(t *testing.T) {
	var runtime *HotCodeRuntime
	match NewHotCodeRuntime(HotCodeExitWith(func(term.PID, term.Term) kernel.Delivery { return kernel.Delivered() })) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(created): runtime = created }
	match runtime.Install(hotCodeModule("v1")) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	owner := term.PID{Node: 1, Number: 1, Creation: 1}
	other := term.PID{Node: 1, Number: 2, Creation: 1}
	match runtime.Enter(owner, "sample") {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(entry):
		match runtime.Leave(other, entry.Reference) {
		case result.Err(failure): match failure { case CodeReferenceNotOwned(pid, _): if pid != other { t.Fatalf("owner = %v", pid) }; case _: t.Fatalf("failure = %s", failure.Error()) }
		case result.Ok(_): t.Fatal("foreign owner released reference")
		}
	}
}

func TestHotCodeRejectsNilExitCapability(t *testing.T) {
	match NewHotCodeRuntime(HotCodeExitWith(nil)) {
	case result.Err(failure): match failure { case NilHotCodeExit: case _: t.Fatalf("failure = %s", failure.Error()) }
	case result.Ok(_): t.Fatal("nil exit capability was accepted")
	}
}

func TestHotCodeResolverLeasesCurrentVMGeneration(t *testing.T) {
	var runtime *HotCodeRuntime
	match NewHotCodeRuntime(HotCodeExitWith(func(term.PID, term.Term) kernel.Delivery { return kernel.Delivered() })) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(created): runtime = created }
	target := vm.ExternalFunction{Module: "sample", Function: "run", Arity: 0}
	loaded := &LoadedModule{name: "sample", digest: "v1", config: vm.MachineConfig{Exports: map[vm.ExternalFunction]uint64{target: 1}}, instructions: []beam.Instruction{{Opcode: beam.Opcode{Name: "label", Arity: 1}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(1)}}}}}
	match runtime.InstallLoaded(loaded) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	owner := term.PID{Node: 1, Number: 9, Creation: 1}
	match runtime.LinkedCode(owner)(target) {
	case vm.LinkedCodeRejected(detail): t.Fatal(detail)
	case vm.LinkedCodeUnchanged: t.Fatal("resolver left code unchanged")
	case vm.LinkedCodeResolved(image, leave):
		if image.Name != "sample" { t.Fatalf("image = %s", image.Name) }
		match runtime.InstallLoaded(&LoadedModule{name: "sample", digest: "v2"}) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
		match runtime.SoftPurge("sample").State { case beam.OldCodeVersionBusy(count): if count != 1 { t.Fatalf("references = %d", count) }; case _: t.Fatal("soft purge did not report busy old code") }
		leave(); leave()
		match runtime.SoftPurge("sample").State { case beam.OldCodeVersionPurged(count): if count != 0 { t.Fatalf("invalidated = %d", count) }; case _: t.Fatal("soft purge did not remove old code") }
	}
}

func TestHotCodePurgeReclaimsLiteralGenerationAfterLease(t *testing.T) {
	var runtime *HotCodeRuntime; match NewHotCodeRuntime(HotCodeExitWith(func(term.PID, term.Term) kernel.Delivery { return kernel.Delivered() })) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(created): runtime = created }
	literals := requireLiteralArena(t); match literals.Store(0, []byte("old literal")) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
	match runtime.InstallLoaded(&LoadedModule{name: "sample", digest: "literal-v1", literalArena: literals}) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	owner := term.PID{Node: 1, Number: 17, Creation: 1}; var reference beam.CodeReference; match runtime.Enter(owner, "sample") { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(entry): reference = entry.Reference }
	match runtime.InstallLoaded(&LoadedModule{name: "sample", digest: "literal-v2"}) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	busy := runtime.SoftPurge("sample"); if busy.ReclaimedLiterals != 0 || literals.Stats().Closed { t.Fatal("busy purge reclaimed leased literals") }
	match runtime.Leave(owner, reference) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	purged := runtime.SoftPurge("sample"); if purged.ReclaimedLiterals != 1 || !literals.Stats().Closed { t.Fatalf("purge = %d/%v", purged.ReclaimedLiterals, literals.Stats().Closed) }; match purged.ReleaseFailure { case option.None: case option.Some(failure): t.Fatal(failure) }
}

func TestHotCodeCurrentRemovalHonorsLeaseAndForce(t *testing.T) {
	var runtime *HotCodeRuntime; match NewHotCodeRuntime(HotCodeExitWith(func(term.PID, term.Term) kernel.Delivery { return kernel.Delivered() })) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(created): runtime = created }
	literals := requireLiteralArena(t); match literals.Store(0, []byte("current")) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
	match runtime.InstallLoaded(&LoadedModule{name: "remove_me", digest: "v1", literalArena: literals}) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	owner := term.PID{Node: 1, Number: 18, Creation: 1}; match runtime.Enter(owner, "remove_me") { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	match runtime.Remove("remove_me", false) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(report): match report.State { case beam.CurrentCodeBusy(references): if references != 1 { t.Fatalf("references = %d", references) }; case _: t.Fatal("soft removal ignored lease") }; if literals.Stats().Closed { t.Fatal("soft removal reclaimed busy generation") } }
	match runtime.Remove("remove_me", true) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(report): match report.State { case beam.CurrentCodeRemoved(references): if references != 1 { t.Fatalf("invalidated = %d", references) }; case _: t.Fatal("forced removal did not remove current") }; if report.ReclaimedLiterals != 1 || !literals.Stats().Closed { t.Fatal("forced removal retained literal arena") } }
}
