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

// assayxport:law gotp.erts.otp29-gen-server-format
func TestPinnedOTPGenServerFormatting(t *testing.T) {
    payload, cause := os.ReadFile("testdata/otp-29.0.4-gen_server-format.corpus")
    if cause != nil { t.Fatal(cause) }
    modules := pinnedGenServerFormatModules(t)
    registry := otpRegistryForInvocation(t)
    for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
        fields := strings.Split(line, "|")
        if len(fields) != 3 || fields[0] != "case" { t.Fatalf("line %d is malformed", lineNumber+1) }
        module := "gen_server_format_callbacks"
        function := fields[1]
        if function == "status_callback_legacy" { module = "gen_server_format_legacy_callbacks"; function = "status_callback" }
        var process *VMProcess
        match modules.Invoke(module, function, []term.Term{}, clock.Real{}, registry) { case result.Err(failure): t.Fatal(failure); case result.Ok(created): process = created }
        runtime := kernel.New(kernel.KernelConfig{})
        runtime.PersistentPut(term.Tuple(term.MustAtom("logger_config"), term.MustAtom("$primary_config$")), term.Integer(0))
        match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
        deadline := time.Now().Add(500 * time.Millisecond)
        for time.Now().Before(deadline) {
            runtime.Run(2_000_000)
            settled := false
            match process.State() { case VMProcessWaiting(_, _), VMProcessSuspended(_, _): time.Sleep(time.Millisecond); case _: settled = true }
            if settled { break }
        }
        assertGenServerCorpusOutcome(t, fields[1], 0, process.State(), decodeGenServerCorpusTerm(t, fields[2]))
    }
}

func pinnedGenServerFormatModules(t *testing.T) *ModuleSet {
    var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
    loaded := []*LoadedModule{pinnedGenServerModule(t), pinnedListsModule(t), pinnedMapsModule(t)}
    for _, path := range []string{"testdata/otp-29.0.4/gen_server_format_callbacks.beam", "testdata/otp-29.0.4/gen_server_format_legacy_callbacks.beam"} {
        match LoadModuleFile(read, path, ModuleLoaderConfig{}) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): loaded = append(loaded, found) }
    }
    dependencies := []string{"sets", "gen", "proc_lib", "sys", "global", "code", "epp", "erl_features", "erl_scan", "io", "io_lib", "io_lib_format", "io_lib_pretty", "logger", "logger_config", "error_logger"}
    for _, dependency := range dependencies { loaded = append(loaded, pinnedStdlibDependency(t, dependency)) }
    var modules *ModuleSet
    match NewModuleSet(loaded) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): modules = found }
    return modules
}
