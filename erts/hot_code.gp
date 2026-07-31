package erts

import (
	"fmt"

	"goforge.dev/goplus/std/memory"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

type HotCodeExitCapability enum {
	HotCodeExitWith(Exit func(term.PID, term.Term) kernel.Delivery)
}

type HotCodeRuntimeFailure enum {
	NilHotCodeKernel()
	NilHotCodeExit()
	NilLoadedHotCodeModule()
	HotCodeStateFailure(Cause beam.HotCodeFailure)
	CodeReferenceNotOwned(Owner term.PID, Generation uint64)
}

func (failure HotCodeRuntimeFailure) Error() string {
	match failure {
	case NilHotCodeKernel: return "gotp/erts: hot-code kernel is nil"
	case NilHotCodeExit: return "gotp/erts: hot-code exit capability is nil"
	case NilLoadedHotCodeModule: return "gotp/erts: loaded hot-code module is nil"
	case HotCodeStateFailure(cause): return cause.Error()
	case CodeReferenceNotOwned(_, generation): return "gotp/erts: code reference is not owned for generation " + fmt.Sprint(generation)
	}
}

type HotCodeEntry struct {
	Handle beam.CodeHandle
	Reference beam.CodeReference
}

type HotCodePurgeReport struct {
	State beam.CodePurgeState
	Exited int
	ReclaimedLiterals int
	ReleaseFailure option.Option[LiteralArenaFailure]
}

type HotCodeRemoveReport struct { State beam.CodeRemovalState; Exited int; ReclaimedLiterals int; ReleaseFailure option.Option[LiteralArenaFailure] }

type HotCodeRuntime struct {
	store beam.CodeStore
	owners map[uint64]map[term.PID]int
	images map[uint64]vm.ModuleImage
	literals map[uint64]*LiteralArena
	exits HotCodeExitCapability
}

func HotCodeExits(kernelRuntime *kernel.Kernel) result.Result[HotCodeExitCapability, HotCodeRuntimeFailure] {
	if kernelRuntime == nil { return result.Err[HotCodeExitCapability, HotCodeRuntimeFailure](NilHotCodeKernel()) }
	return result.Ok[HotCodeExitCapability, HotCodeRuntimeFailure](HotCodeExitWith(kernelRuntime.Exit))
}

func NewHotCodeRuntime(exits HotCodeExitCapability) result.Result[*HotCodeRuntime, HotCodeRuntimeFailure] {
	match exits {
	case HotCodeExitWith(exit): if exit == nil { return result.Err[*HotCodeRuntime, HotCodeRuntimeFailure](NilHotCodeExit()) }
	}
	return result.Ok[*HotCodeRuntime, HotCodeRuntimeFailure](&HotCodeRuntime{store: beam.NewCodeStore(), owners: map[uint64]map[term.PID]int{}, images: map[uint64]vm.ModuleImage{}, literals: map[uint64]*LiteralArena{}, exits: exits})
}

func (runtime *HotCodeRuntime) InstallLoaded(module *LoadedModule) result.Result[beam.CodeHandle, HotCodeRuntimeFailure] {
	if module == nil { return result.Err[beam.CodeHandle, HotCodeRuntimeFailure](NilLoadedHotCodeModule()) }
	match runtime.Install(&beam.Module{Name: module.name, Digest: module.digest}) {
	case result.Err(failure): return result.Err[beam.CodeHandle, HotCodeRuntimeFailure](failure)
	case result.Ok(handle): runtime.images[handle.Generation] = module.image(); if module.literalArena != nil { runtime.literals[handle.Generation] = module.literalArena; module.literalArena = nil }; return result.Ok[beam.CodeHandle, HotCodeRuntimeFailure](handle)
	}
}

func (runtime *HotCodeRuntime) LinkedCode(owner term.PID) vm.LinkedCodeEffect {
	return func(target vm.ExternalFunction) vm.LinkedCodeOutcome {
		match runtime.Enter(owner, target.Module) {
		case result.Err(failure): return vm.LinkedCodeRejected(failure.Error())
		case result.Ok(entry):
			image, present := runtime.images[entry.Reference.Generation]
			match option.Of(image, present) {
			case option.None:
				runtime.Leave(owner, entry.Reference)
				return vm.LinkedCodeRejected("loaded generation has no VM image")
			case option.Some(image):
				released := false
				return vm.LinkedCodeResolved(image, func() {
					if released { return }
					released = true
					runtime.Leave(owner, entry.Reference)
				})
			}
		}
	}
}

// assayxport:unit gotp.erts.hot-code
func (runtime *HotCodeRuntime) Install(image *beam.Module) result.Result[beam.CodeHandle, HotCodeRuntimeFailure] {
	match runtime.store.Install(image) {
	case result.Err(cause): return result.Err[beam.CodeHandle, HotCodeRuntimeFailure](HotCodeStateFailure(cause))
	case result.Ok(transition): runtime.store = transition.Store; return result.Ok[beam.CodeHandle, HotCodeRuntimeFailure](transition.Current)
	}
}

func (runtime *HotCodeRuntime) Enter(owner term.PID, module string) result.Result[HotCodeEntry, HotCodeRuntimeFailure] {
	match runtime.store.EnterCurrent(module) {
	case result.Err(cause): return result.Err[HotCodeEntry, HotCodeRuntimeFailure](HotCodeStateFailure(cause))
	case result.Ok(transition):
		runtime.store = transition.Store
		owners, present := runtime.owners[transition.Reference.Generation]
		if !present { owners = map[term.PID]int{}; runtime.owners[transition.Reference.Generation] = owners }
		owners[owner]++
		return result.Ok[HotCodeEntry, HotCodeRuntimeFailure](HotCodeEntry{Handle: transition.Handle, Reference: transition.Reference})
	}
}

func (runtime *HotCodeRuntime) Leave(owner term.PID, reference beam.CodeReference) result.Result[bool, HotCodeRuntimeFailure] {
	owners, present := runtime.owners[reference.Generation]
	count := owners[owner]
	if !present || count < 1 { return result.Err[bool, HotCodeRuntimeFailure](CodeReferenceNotOwned(owner, reference.Generation)) }
	match runtime.store.Leave(reference) {
	case result.Err(cause): return result.Err[bool, HotCodeRuntimeFailure](HotCodeStateFailure(cause))
	case result.Ok(store): runtime.store = store
	}
	if count == 1 { delete(owners, owner) } else { owners[owner] = count - 1 }
	if len(owners) == 0 { delete(runtime.owners, reference.Generation) }
	return result.Ok[bool, HotCodeRuntimeFailure](true)
}

func (runtime *HotCodeRuntime) SoftPurge(module string) HotCodePurgeReport {
	old := runtime.store.Old(module)
	transition := runtime.store.SoftPurge(module)
	runtime.store = transition.Store
	reclaimed := 0; var releaseFailure option.Option[LiteralArenaFailure] = option.None[LiteralArenaFailure]()
	match transition.State {
	case beam.OldCodeVersionPurged(_): match old { case option.Some(handle): delete(runtime.images, handle.Generation); reclaimed, releaseFailure = runtime.releaseLiterals(handle.Generation); case option.None: }
	case beam.NoOldCodeVersion, beam.OldCodeVersionBusy(_):
	}
	return HotCodePurgeReport{State: transition.State, ReclaimedLiterals: reclaimed, ReleaseFailure: releaseFailure}
}

func (runtime *HotCodeRuntime) Purge(module string) HotCodePurgeReport {
	old := runtime.store.Old(module)
	transition := runtime.store.Purge(module)
	runtime.store = transition.Store
	exited := 0
	reclaimed := 0; var releaseFailure option.Option[LiteralArenaFailure] = option.None[LiteralArenaFailure]()
	match old {
	case option.None:
	case option.Some(handle):
		owners := runtime.owners[handle.Generation]
		match runtime.exits {
		case HotCodeExitWith(exit):
			for owner := range owners { exit(owner, term.MustAtom("killed")); exited++ }
		}
		delete(runtime.owners, handle.Generation)
		delete(runtime.images, handle.Generation)
		reclaimed, releaseFailure = runtime.releaseLiterals(handle.Generation)
	}
	return HotCodePurgeReport{State: transition.State, Exited: exited, ReclaimedLiterals: reclaimed, ReleaseFailure: releaseFailure}
}

func (runtime *HotCodeRuntime) Remove(module string, force bool) result.Result[HotCodeRemoveReport, HotCodeRuntimeFailure] {
	match runtime.store.Remove(module, force) {
	case result.Err(cause): return result.Err[HotCodeRemoveReport, HotCodeRuntimeFailure](HotCodeStateFailure(cause))
	case result.Ok(transition):
		runtime.store = transition.Store; exited := 0; reclaimed := 0; var releaseFailure option.Option[LiteralArenaFailure] = option.None[LiteralArenaFailure]()
		match transition.Removed {
		case option.None:
		case option.Some(handle):
			if force { owners := runtime.owners[handle.Generation]; match runtime.exits { case HotCodeExitWith(exit): for owner := range owners { exit(owner, term.MustAtom("killed")); exited++ } } }
			delete(runtime.owners, handle.Generation); delete(runtime.images, handle.Generation); reclaimed, releaseFailure = runtime.releaseLiterals(handle.Generation)
		}
		return result.Ok[HotCodeRemoveReport, HotCodeRuntimeFailure](HotCodeRemoveReport{State: transition.State, Exited: exited, ReclaimedLiterals: reclaimed, ReleaseFailure: releaseFailure})
	}
}

func (runtime *HotCodeRuntime) releaseLiterals(generation uint64) (int, option.Option[LiteralArenaFailure]) { literals, present := runtime.literals[generation]; if !present { return 0, option.None[LiteralArenaFailure]() }; count := literals.Len(); match literals.Close() { case result.Err(failure): return 0, option.Some(failure); case result.Ok(_): delete(runtime.literals, generation); return count, option.None[LiteralArenaFailure]() } }
