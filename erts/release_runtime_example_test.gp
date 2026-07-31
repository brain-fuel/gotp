package erts

import (
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/otp/release"
	"goforge.dev/gotp/term"
)

var _ beam.CodeHandle

func releaseHotCode(t *testing.T) *HotCodeRuntime {
	t.Helper(); match NewHotCodeRuntime(HotCodeExitWith(func(term.PID, term.Term) kernel.Delivery { return kernel.Delivered() })) { case result.Err(failure): t.Fatal(failure.Error()); return nil; case result.Ok(runtime): return runtime }
}

func releaseOperations(trace *[]string) ReleaseRuntimeOperations {
	ok := func(name string) result.Result[bool, ReleaseRuntimeFailure] { *trace = append(*trace, name); return result.Ok[bool, ReleaseRuntimeFailure](true) }
	return ReleaseRuntimeOperations{
		Stage: func(library string, version string, modules []string) result.Result[[]*LoadedModule, ReleaseRuntimeFailure] { *trace = append(*trace, "stage:"+library+":"+version); loaded := make([]*LoadedModule, len(modules)); for index, module := range modules { loaded[index] = &LoadedModule{name: module, digest: version} }; return result.Ok[[]*LoadedModule, ReleaseRuntimeFailure](loaded) },
		Unstage: func(library string, _ []string) result.Result[bool, ReleaseRuntimeFailure] { return ok("unstage:"+library) },
		CommitPaths: func() result.Result[bool, ReleaseRuntimeFailure] { return ok("commit_paths") },
		Suspend: func(target release.SuspendTarget) result.Result[bool, ReleaseRuntimeFailure] { return ok("suspend:"+target.Module) },
		Resume: func(module string) result.Result[bool, ReleaseRuntimeFailure] { return ok("resume:"+module) },
		Change: func(_ release.ChangeMode, target release.ChangeTarget) result.Result[bool, ReleaseRuntimeFailure] { return ok("change:"+target.Module) },
		Stop: func(module string) result.Result[bool, ReleaseRuntimeFailure] { return ok("stop:"+module) },
		Start: func(module string) result.Result[bool, ReleaseRuntimeFailure] { return ok("start:"+module) },
		SyncList: func(_ term.Term, _ []string) result.Result[bool, ReleaseRuntimeFailure] { return ok("sync_list") },
		SyncApply: func(_ term.Term, _ release.MFA) result.Result[bool, ReleaseRuntimeFailure] { return ok("sync_apply") },
		Apply: func(_ release.MFA) result.Result[bool, ReleaseRuntimeFailure] { return ok("apply") },
	}
}

func newReleaseRuntime(t *testing.T, hot *HotCodeRuntime, operations ReleaseRuntimeOperations) *ReleaseRuntime {
	t.Helper(); match NewReleaseRuntime(hot, operations) { case result.Err(failure): t.Fatal(failure.Error()); return nil; case result.Ok(runtime): return runtime }
}

func executeReleaseRuntime(t *testing.T, runtime *ReleaseRuntime, script release.Script) result.Result[release.ExecutionReport, release.ExecutionFailure] {
	t.Helper(); match runtime.Capability() { case result.Err(failure): t.Fatal(failure.Error()); return result.Err[release.ExecutionReport, release.ExecutionFailure](failure); case result.Ok(capability): return release.Execute(script, capability) }
}

// assayxport:law gotp.erts.release-runtime-laws
func TestReleaseRuntimeCommitsHotCodeInInstructionOrder(t *testing.T) {
	trace := []string{}
	runtime := newReleaseRuntime(t, releaseHotCode(t), releaseOperations(&trace))
	script := release.Script{CommitIndex: 1, Instructions: []release.Instruction{
		release.LoadObjectCode("sample", "2", []string{"alpha"}), release.PointOfNoReturn(), release.SuspendCode([]release.SuspendTarget{{Module: "alpha", Timeout: release.DefaultTimeout()}}),
		release.LoadCode("alpha", release.SoftPurge(), release.SoftPurge()), release.ChangeCode(release.Upgrade(), []release.ChangeTarget{{Module: "alpha", Extra: term.MustAtom("extra")}}), release.ResumeCode([]string{"alpha"}),
	}}
	match executeReleaseRuntime(t, runtime, script) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(report): match report { case release.ReleaseCompleted(applied): if applied != 6 { t.Fatalf("applied = %d", applied) }; case _: t.Fatalf("report = %v", report) } }
	want := []string{"stage:sample:2", "commit_paths", "suspend:alpha", "change:alpha", "resume:alpha"}
	if len(trace) != len(want) { t.Fatalf("trace = %v", trace) }; for index := range want { if trace[index] != want[index] { t.Fatalf("trace = %v", trace) } }
}

func TestReleaseRuntimeDefersBusyPostPurge(t *testing.T) {
	hot := releaseHotCode(t)
	match hot.InstallLoaded(&LoadedModule{name: "alpha", digest: "1"}) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	owner := term.PID{Node: 1, Number: 1, Creation: 1}
	match hot.Enter(owner, "alpha") { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	trace := []string{}; runtime := newReleaseRuntime(t, hot, releaseOperations(&trace))
	script := release.Script{CommitIndex: 1, Instructions: []release.Instruction{release.LoadObjectCode("sample", "2", []string{"alpha"}), release.PointOfNoReturn(), release.LoadCode("alpha", release.SoftPurge(), release.BrutalPurge())}}
	match executeReleaseRuntime(t, runtime, script) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	unpurged := runtime.UnpurgedModules(); if len(unpurged) != 1 || unpurged[0] != "alpha" { t.Fatalf("unpurged = %v", unpurged) }
}

func TestReleaseRuntimeRejectsBusySoftPrePurge(t *testing.T) {
	hot := releaseHotCode(t)
	match hot.InstallLoaded(&LoadedModule{name: "alpha", digest: "0"}) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	owner := term.PID{Node: 1, Number: 2, Creation: 1}
	match hot.Enter(owner, "alpha") { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	match hot.InstallLoaded(&LoadedModule{name: "alpha", digest: "1"}) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	trace := []string{}; runtime := newReleaseRuntime(t, hot, releaseOperations(&trace))
	script := release.Script{CommitIndex: 1, Instructions: []release.Instruction{release.LoadObjectCode("sample", "2", []string{"alpha"}), release.PointOfNoReturn(), release.LoadCode("alpha", release.SoftPurge(), release.SoftPurge())}}
	match executeReleaseRuntime(t, runtime, script) { case result.Err(_): case result.Ok(_): t.Fatal("busy soft pre-purge succeeded") }
}

func TestReleaseRuntimeRemovesCurrentCodeThroughHotCodeState(t *testing.T) {
	hot := releaseHotCode(t); match hot.InstallLoaded(&LoadedModule{name: "retired", digest: "1"}) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	trace := []string{}; runtime := newReleaseRuntime(t, hot, releaseOperations(&trace)); script := release.Script{CommitIndex: -1, Instructions: []release.Instruction{release.RemoveCode("retired", release.SoftPurge(), release.BrutalPurge())}}
	match executeReleaseRuntime(t, runtime, script) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	match hot.Enter(term.PID{Node: 1, Number: 19, Creation: 1}, "retired") { case result.Err(failure): match failure { case HotCodeStateFailure(cause): match cause { case beam.CodeModuleNotLoaded(_): case _: t.Fatal(cause) }; case _: t.Fatal(failure.Error()) }; case result.Ok(_): t.Fatal("removed current code remained enterable") }
}
