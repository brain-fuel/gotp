package erts

import (
    "os"
    "strings"
    "testing"

    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/beam"
    "goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.otp29-gen-statem-format
func TestPinnedOTPGenStatemFormatting(t *testing.T) {
    modules := pinnedGenStatemFormatModules(t)
    for _, mode := range []string{"state_functions", "handle_event"} {
        payload, cause := os.ReadFile("testdata/otp-29.0.4-gen_statem-format-" + mode + ".corpus")
        if cause != nil { t.Fatal(cause) }
        module := "gen_statem_format_" + mode + "_callbacks"
        for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
            fields := strings.Split(line, "|")
            if len(fields) != 3 || fields[0] != "case" { t.Fatalf("line %d is malformed", lineNumber+1) }
            process := invokeGenStatemFixture(t, modules, module, fields[1], nil)
            assertGenServerCorpusOutcome(t, mode+":"+fields[1], 0, process.State(), decodeGenServerCorpusTerm(t, fields[2]))
        }
    }
}

func pinnedGenStatemFormatModules(t *testing.T) *ModuleSet {
    var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
    loaded := []*LoadedModule{pinnedGenStatemModule(t), pinnedListsModule(t), pinnedMapsModule(t)}
    names := []string{
        "gen_statem_format_fixture",
        "gen_statem_format_state_functions_callbacks",
        "gen_statem_format_handle_event_callbacks",
        "gen_statem_format_state_functions_legacy_callbacks",
        "gen_statem_format_handle_event_legacy_callbacks",
    }
    for _, name := range names {
        match LoadModuleFile(read, "testdata/otp-29.0.4/" + name + ".beam", ModuleLoaderConfig{}) {
        case result.Err(failure): t.Fatal(failure)
        case result.Ok(found): loaded = append(loaded, found)
        }
    }
    dependencies := []string{"sets", "gen", "proc_lib", "sys", "global", "code", "epp", "erl_features", "erl_scan", "io", "io_lib", "io_lib_format", "io_lib_pretty", "logger", "logger_config", "error_logger"}
    for _, dependency := range dependencies { loaded = append(loaded, pinnedStdlibDependency(t, dependency)) }
    match NewModuleSet(loaded) {
    case result.Err(failure): t.Fatal(failure)
    case result.Ok(modules): return modules
    }
    panic("unreachable")
}
