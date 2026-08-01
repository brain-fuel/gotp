package erts

import (
    "os"
    "strings"
    "testing"
    "time"

    "goforge.dev/goplus/std/clock"
    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/beam"
    "goforge.dev/gotp/kernel"
    "goforge.dev/gotp/term"
)

func pinnedGenStatemModule(t *testing.T) *LoadedModule {
    var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
    match LoadModuleFile(read, "../beam/testdata/otp-29.0.4/gen_statem.beam", ModuleLoaderConfig{}) {
    case result.Err(failure): t.Fatal(failure)
    case result.Ok(module): return module
    }
    panic("unreachable")
}

func pinnedGenStatemModules(t *testing.T) *ModuleSet {
    var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
    loaded := []*LoadedModule{pinnedGenStatemModule(t), pinnedListsModule(t), pinnedMapsModule(t)}
    for _, name := range []string{"gen_statem_fixture", "gen_statem_state_functions_callbacks", "gen_statem_handle_event_callbacks"} {
        match LoadModuleFile(read, "testdata/otp-29.0.4/" + name + ".beam", ModuleLoaderConfig{}) {
        case result.Err(failure): t.Fatal(failure)
        case result.Ok(module): loaded = append(loaded, module)
        }
    }
    for _, name := range []string{"sets", "gen", "proc_lib", "sys", "global", "code", "io", "io_lib", "logger", "logger_config", "error_logger"} {
        loaded = append(loaded, pinnedStdlibDependency(t, name))
    }
    match NewModuleSet(loaded) {
    case result.Err(failure): t.Fatal(failure)
    case result.Ok(modules): return modules
    }
    panic("unreachable")
}

// assayxport:law gotp.erts.otp29-gen-statem-core-callback-modes
func TestPinnedOTPGenStatemCoreCorpora(t *testing.T) {
    modules := pinnedGenStatemModules(t)
    for _, mode := range []string{"state_functions", "handle_event"} {
        module := "gen_statem_" + mode + "_callbacks"
        payload, cause := os.ReadFile("testdata/otp-29.0.4-gen_statem-" + mode + ".corpus")
        if cause != nil { t.Fatal(cause) }
        for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
            if strings.HasPrefix(line, "#") { continue }
            fields := strings.Split(line, "|")
            if len(fields) != 3 || fields[0] != "case" { t.Fatalf("line %d is malformed", lineNumber+1) }
            process := invokeGenStatemFixture(t, modules, module, fields[1], nil)
            assertGenServerCorpusOutcome(t, fields[1], 0, process.State(), decodeGenServerCorpusTerm(t, fields[2]))
        }
    }
}

func invokeGenStatemFixture(t *testing.T, modules *ModuleSet, module string, function string, arguments []term.Term) *VMProcess {
    t.Helper()
    var process *VMProcess
    match modules.Invoke(module, function, arguments, clock.Real{}, otpRegistryForInvocation(t)) {
    case result.Err(failure): t.Fatal(failure)
    case result.Ok(created): process = created
    }
    runtime := kernel.New(kernel.KernelConfig{})
    runtime.PersistentPut(term.Tuple(term.MustAtom("logger_config"), term.MustAtom("$primary_config$")), term.Integer(0))
    var tracer *kernel.Tracer
    match runtime.EnableTracing(512) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): tracer = found }
    match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
    case result.Err(failure): t.Fatal(failure)
    case result.Ok(_):
    }
    deadline := time.Now().Add(time.Second)
    for time.Now().Before(deadline) {
        runtime.Run(4_000_000)
        settled := false
        match process.State() {
        case VMProcessWaiting(_, _), VMProcessSuspended(_, _): time.Sleep(time.Millisecond)
        case _: settled = true
        }
        if settled { break }
    }
    match process.State() { case VMProcessCompleted(_, _, _): case _: t.Logf("%s:%s trace: %#v", module, function, tracer.Snapshot()) }
    return process
}
