package erts

import (
	"fmt"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

type HotCodeExitCapability enum {
	HotCodeExitWith(Exit func(term.PID, term.Term) kernel.Delivery)
}

type HotCodeRuntimeFailure enum {
	NilHotCodeKernel()
	NilHotCodeExit()
	HotCodeStateFailure(Cause beam.HotCodeFailure)
	CodeReferenceNotOwned(Owner term.PID, Generation uint64)
}

func (failure HotCodeRuntimeFailure) Error() string {
	match failure {
	case NilHotCodeKernel: return "gotp/erts: hot-code kernel is nil"
	case NilHotCodeExit: return "gotp/erts: hot-code exit capability is nil"
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
}

type HotCodeRuntime struct {
	store beam.CodeStore
	owners map[uint64]map[term.PID]int
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
	return result.Ok[*HotCodeRuntime, HotCodeRuntimeFailure](&HotCodeRuntime{store: beam.NewCodeStore(), owners: map[uint64]map[term.PID]int{}, exits: exits})
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
	transition := runtime.store.SoftPurge(module)
	runtime.store = transition.Store
	return HotCodePurgeReport{State: transition.State}
}

func (runtime *HotCodeRuntime) Purge(module string) HotCodePurgeReport {
	old := runtime.store.Old(module)
	transition := runtime.store.Purge(module)
	runtime.store = transition.Store
	exited := 0
	match old {
	case option.None:
	case option.Some(handle):
		owners := runtime.owners[handle.Generation]
		match runtime.exits {
		case HotCodeExitWith(exit):
			for owner := range owners { exit(owner, term.MustAtom("killed")); exited++ }
		}
		delete(runtime.owners, handle.Generation)
	}
	return HotCodePurgeReport{State: transition.State, Exited: exited}
}
