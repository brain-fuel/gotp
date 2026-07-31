package erts

import (
	"sort"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/otp/release"
	"goforge.dev/gotp/term"
)

type StageReleaseEffect func(Library string, Version string, Modules []string) result.Result[[]*LoadedModule, ReleaseRuntimeFailure]
type UnstageReleaseEffect func(Library string, Modules []string) result.Result[bool, ReleaseRuntimeFailure]
type CommitPathsEffect func() result.Result[bool, ReleaseRuntimeFailure]
type RemoveReleaseEffect func(Module string, Pre release.PurgeMethod, Post release.PurgeMethod) result.Result[bool, ReleaseRuntimeFailure]
type SuspendReleaseEffect func(Target release.SuspendTarget) result.Result[bool, ReleaseRuntimeFailure]
type ModuleReleaseEffect func(Module string) result.Result[bool, ReleaseRuntimeFailure]
type ChangeReleaseEffect func(Mode release.ChangeMode, Target release.ChangeTarget) result.Result[bool, ReleaseRuntimeFailure]
type SyncListReleaseEffect func(ID term.Term, Nodes []string) result.Result[bool, ReleaseRuntimeFailure]
type SyncApplyReleaseEffect func(ID term.Term, Call release.MFA) result.Result[bool, ReleaseRuntimeFailure]
type ApplyReleaseEffect func(Call release.MFA) result.Result[bool, ReleaseRuntimeFailure]

type ReleaseRuntimeOperations struct {
	Stage StageReleaseEffect
	Unstage UnstageReleaseEffect
	CommitPaths CommitPathsEffect
	Remove RemoveReleaseEffect
	Suspend SuspendReleaseEffect
	Resume ModuleReleaseEffect
	Change ChangeReleaseEffect
	Stop ModuleReleaseEffect
	Start ModuleReleaseEffect
	SyncList SyncListReleaseEffect
	SyncApply SyncApplyReleaseEffect
	Apply ApplyReleaseEffect
}

type ReleaseRuntimeFailure enum {
	NilReleaseHotCode()
	InvalidReleaseOperation(Name string)
	ReleaseOperationRejected(Name string, Detail string)
	ReleaseHotCodeFailure(Cause HotCodeRuntimeFailure)
	MissingStagedReleaseModule(Module string)
	UnexpectedStagedReleaseModule(Module string)
}

func (failure ReleaseRuntimeFailure) Error() string {
	match failure {
	case NilReleaseHotCode: return "gotp/erts: release hot-code runtime is nil"
	case InvalidReleaseOperation(name): return "gotp/erts: release operation is nil: " + name
	case ReleaseOperationRejected(name, detail): return "gotp/erts: release operation " + name + " rejected: " + detail
	case ReleaseHotCodeFailure(cause): return cause.Error()
	case MissingStagedReleaseModule(module): return "gotp/erts: release module is not staged: " + module
	case UnexpectedStagedReleaseModule(module): return "gotp/erts: stage returned unexpected module: " + module
	}
}

type stagedReleaseModule struct { library string; module *LoadedModule }

type ReleaseRuntime struct {
	hotCode *HotCodeRuntime
	operations ReleaseRuntimeOperations
	staged map[string]stagedReleaseModule
	unpurged map[string]release.PurgeMethod
}

// assayxport:unit gotp.erts.release-runtime
func NewReleaseRuntime(hotCode *HotCodeRuntime, operations ReleaseRuntimeOperations) result.Result[*ReleaseRuntime, ReleaseRuntimeFailure] {
	if hotCode == nil { return result.Err[*ReleaseRuntime, ReleaseRuntimeFailure](NilReleaseHotCode()) }
	checks := []struct { name string; present bool }{
		{"stage", operations.Stage != nil}, {"unstage", operations.Unstage != nil}, {"commit_paths", operations.CommitPaths != nil}, {"remove", operations.Remove != nil},
		{"suspend", operations.Suspend != nil}, {"resume", operations.Resume != nil}, {"change", operations.Change != nil}, {"stop", operations.Stop != nil}, {"start", operations.Start != nil},
		{"sync_list", operations.SyncList != nil}, {"sync_apply", operations.SyncApply != nil}, {"apply", operations.Apply != nil},
	}
	for _, check := range checks { if !check.present { return result.Err[*ReleaseRuntime, ReleaseRuntimeFailure](InvalidReleaseOperation(check.name)) } }
	return result.Ok[*ReleaseRuntime, ReleaseRuntimeFailure](&ReleaseRuntime{hotCode: hotCode, operations: operations, staged: map[string]stagedReleaseModule{}, unpurged: map[string]release.PurgeMethod{}})
}

func (runtime *ReleaseRuntime) Capability() result.Result[release.EffectCapability, release.ExecutionFailure] {
	return release.NewEffectCapability(runtime.execute, runtime.rollback)
}

func (runtime *ReleaseRuntime) UnpurgedModules() []string {
	modules := []string{}; for module := range runtime.unpurged { modules = append(modules, module) }; sort.Strings(modules); return modules
}

func (runtime *ReleaseRuntime) execute(instruction release.Instruction) release.EffectOutcome {
	match instruction {
	case release.LoadObjectCode(library, version, modules): return runtime.stage(library, version, modules)
	case release.PointOfNoReturn: return releaseEffect(runtime.operations.CommitPaths())
	case release.LoadCode(module, pre, post): return runtime.load(module, pre, post)
	case release.RemoveCode(module, pre, post): return releaseEffect(runtime.operations.Remove(module, pre, post))
	case release.PurgeCode(modules): for _, module := range modules { runtime.hotCode.Purge(module); delete(runtime.unpurged, module) }; return release.EffectApplied()
	case release.SuspendCode(targets): for _, target := range targets { match runtime.operations.Suspend(target) { case result.Err(failure): return release.EffectRejected(failure.Error()); case result.Ok(_): } }; return release.EffectApplied()
	case release.ResumeCode(modules): return runtime.modules("resume", modules, runtime.operations.Resume)
	case release.ChangeCode(mode, targets): for _, target := range targets { match runtime.operations.Change(mode, target) { case result.Err(failure): return release.EffectRejected(failure.Error()); case result.Ok(_): } }; return release.EffectApplied()
	case release.StopCode(modules): return runtime.modules("stop", modules, runtime.operations.Stop)
	case release.StartCode(modules): return runtime.modules("start", modules, runtime.operations.Start)
	case release.SyncNodesList(id, nodes): return releaseEffect(runtime.operations.SyncList(id.Clone(), append([]string{}, nodes...)))
	case release.SyncNodesApply(id, call): return releaseEffect(runtime.operations.SyncApply(id.Clone(), call))
	case release.Apply(call): return releaseEffect(runtime.operations.Apply(call))
	case release.RestartEmulator: return release.EffectRestartRequested(release.CurrentEmulatorRestart())
	case release.RestartNewEmulator: return release.EffectRestartRequested(release.NewEmulatorRestart())
	}
}

func (runtime *ReleaseRuntime) rollback(instruction release.Instruction) release.RollbackOutcome {
	match instruction {
	case release.LoadObjectCode(library, _, modules):
		match runtime.operations.Unstage(library, append([]string{}, modules...)) {
		case result.Err(failure): return release.RollbackRejected(failure.Error())
		case result.Ok(_): for _, module := range modules { delete(runtime.staged, module) }; return release.RollbackApplied()
		}
	case _: return release.RollbackRejected("instruction has no preflight rollback")
	}
}

func (runtime *ReleaseRuntime) stage(library string, version string, modules []string) release.EffectOutcome {
	match runtime.operations.Stage(library, version, append([]string{}, modules...)) {
	case result.Err(failure): return release.EffectRejected(failure.Error())
	case result.Ok(loaded):
		wanted := map[string]bool{}; for _, module := range modules { wanted[module] = true }
		if len(loaded) != len(wanted) { return release.EffectRejected("stage returned a different module count") }
		returned := map[string]bool{}
		for _, module := range loaded {
			if module == nil || !wanted[module.name] { name := "<nil>"; if module != nil { name = module.name }; return release.EffectRejected(UnexpectedStagedReleaseModule(name).Error()) }
			if returned[module.name] { return release.EffectRejected("stage returned duplicate module: " + module.name) }
			returned[module.name] = true
			if _, exists := runtime.staged[module.name]; exists { return release.EffectRejected("module is already staged: " + module.name) }
		}
		for module := range wanted { if !returned[module] { return release.EffectRejected("stage omitted module: " + module) } }
		for _, module := range loaded { runtime.staged[module.name] = stagedReleaseModule{library: library, module: module} }
		return release.EffectApplied()
	}
}

func (runtime *ReleaseRuntime) load(module string, pre release.PurgeMethod, post release.PurgeMethod) release.EffectOutcome {
	staged, present := runtime.staged[module]
	if !present { return release.EffectRejected(MissingStagedReleaseModule(module).Error()) }
	match runtime.prePurge(module, pre) { case result.Err(failure): return release.EffectRejected(failure.Error()); case result.Ok(_): }
	match runtime.hotCode.InstallLoaded(staged.module) { case result.Err(failure): return release.EffectRejected(failure.Error()); case result.Ok(_): }
	delete(runtime.staged, module)
	transition := runtime.hotCode.SoftPurge(module)
	match transition.State { case beam.OldCodeVersionBusy(_): runtime.unpurged[module] = post; case beam.NoOldCodeVersion, beam.OldCodeVersionPurged(_): delete(runtime.unpurged, module) }
	return release.EffectApplied()
}

func (runtime *ReleaseRuntime) prePurge(module string, method release.PurgeMethod) result.Result[bool, ReleaseRuntimeFailure] {
	match method {
	case release.SoftPurge:
		transition := runtime.hotCode.SoftPurge(module)
		match transition.State { case beam.OldCodeVersionBusy(_): return result.Err[bool, ReleaseRuntimeFailure](ReleaseOperationRejected("soft_purge", "old code is active for " + module)); case _: return result.Ok[bool, ReleaseRuntimeFailure](true) }
	case release.BrutalPurge: runtime.hotCode.Purge(module); return result.Ok[bool, ReleaseRuntimeFailure](true)
	}
}

func (runtime *ReleaseRuntime) modules(name string, modules []string, effect ModuleReleaseEffect) release.EffectOutcome { for _, module := range modules { match effect(module) { case result.Err(failure): return release.EffectRejected(name + ": " + failure.Error()); case result.Ok(_): } }; return release.EffectApplied() }
func releaseEffect(outcome result.Result[bool, ReleaseRuntimeFailure]) release.EffectOutcome { match outcome { case result.Err(failure): return release.EffectRejected(failure.Error()); case result.Ok(_): return release.EffectApplied() } }
