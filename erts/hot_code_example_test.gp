package erts

import (
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

func hotCodeModule(digest string) *beam.Module { return &beam.Module{Name: "sample", Digest: digest} }

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
