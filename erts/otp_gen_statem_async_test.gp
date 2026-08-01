package erts

import (
    "os"
    "strings"
    "testing"

    "goforge.dev/goplus/std/clock"
    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/beam"
    "goforge.dev/gotp/term"
)

func pinnedGenStatemAsyncModules(t *testing.T) *ModuleSet {
    var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
    loaded := []*LoadedModule{pinnedGenStatemModule(t), pinnedListsModule(t), pinnedMapsModule(t)}
    for _, name := range []string{"gen_statem_async_fixture", "gen_statem_async_state_functions_callbacks", "gen_statem_async_handle_event_callbacks"} {
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

// assayxport:law gotp.erts.otp29-gen-statem-async-requests
func TestPinnedOTPGenStatemAsyncRequests(t *testing.T) {
    modules := pinnedGenStatemAsyncModules(t)
    for _, mode := range []string{"state_functions", "handle_event"} {
        module := "gen_statem_async_" + mode + "_callbacks"
        payload, cause := os.ReadFile("testdata/otp-29.0.4-gen_statem-async-" + mode + ".corpus")
        if cause != nil { t.Fatal(cause) }
        for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
            if strings.HasPrefix(line, "#") { continue }
            fields := strings.Split(line, "|")
            if len(fields) != 3 || fields[0] != "case" { t.Fatalf("line %d is malformed", lineNumber+1) }
            expected := decodeGenServerCorpusTerm(t, fields[2])
            process := invokeGenStatemFixture(t, modules, module, fields[1], []term.Term{})
            assertGenServerCorpusOutcome(t, fields[1], 0, process.State(), expected)
        }
    }
}
