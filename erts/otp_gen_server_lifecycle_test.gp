package erts

import (
    "os"
    "strings"
    "testing"

    "goforge.dev/goplus/std/clock"
    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/beam"
    "goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

var _ term.PID

// assayxport:law gotp.erts.otp29-gen-server-lifecycle
func TestPinnedOTPGenServerLifecycle(t *testing.T) {
    payload, cause := os.ReadFile("testdata/otp-29.0.4-gen_server-lifecycle.corpus")
    if cause != nil { t.Fatal(cause) }
    fields := strings.Split(strings.TrimSpace(string(payload)), "|")
    if len(fields) != 3 || fields[0] != "case" { t.Fatal("malformed lifecycle corpus") }
    var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
    var callback *LoadedModule
    match LoadModuleFile(read, "testdata/otp-29.0.4/gen_server_callbacks.beam", ModuleLoaderConfig{}) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): callback = found }
    modules := pinnedGenServerModuleSet(t, callback)
    var process *VMProcess
    match modules.Invoke("gen_server_callbacks", fields[1], nil, clock.Real{}, otpRegistryForInvocation(t)) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): process = found }
    runtime := kernel.New(kernel.KernelConfig{})
	var tracer *kernel.Tracer
	match runtime.EnableTracing(256) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): tracer = found }
    match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
    runtime.Run(100_000)
	match process.State() { case VMProcessCompleted(_, _, _): case _: t.Logf("runtime trace: %#v", tracer.Snapshot()) }
    assertGenServerCorpusOutcome(t, fields[1], 0, process.State(), decodeGenServerCorpusTerm(t, fields[2]))
}

func pinnedGenServerModuleSet(t *testing.T, callback *LoadedModule) *ModuleSet {
    dependencies := []string{"sets","gen","proc_lib","sys","global","code","io","io_lib","logger","error_logger"}
    loaded := []*LoadedModule{pinnedGenServerModule(t), pinnedListsModule(t), pinnedMapsModule(t), callback}
    for _, dependency := range dependencies { loaded = append(loaded, pinnedStdlibDependency(t, dependency)) }
    match NewModuleSet(loaded) { case result.Err(failure): t.Fatal(failure); case result.Ok(modules): return modules }
    panic("unreachable")
}
