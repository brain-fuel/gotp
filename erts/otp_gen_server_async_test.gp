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

// assayxport:law gotp.erts.otp29-gen-server-async-requests
func TestPinnedOTPGenServerAsyncRequests(t *testing.T) {
    payload, cause := os.ReadFile("testdata/otp-29.0.4-gen_server-async.corpus")
    if cause != nil { t.Fatal(cause) }
    var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
    var callback *LoadedModule
    match LoadModuleFile(read, "testdata/otp-29.0.4/gen_server_async_callbacks.beam", ModuleLoaderConfig{}) {
    case result.Err(failure): t.Fatal(failure)
    case result.Ok(found): callback = found
    }
    dependencies := []string{"sets", "gen", "proc_lib", "sys", "global", "code", "io", "io_lib", "logger", "logger_config", "error_logger"}
    loaded := []*LoadedModule{callback, pinnedGenServerModule(t), pinnedListsModule(t), pinnedMapsModule(t)}
    for _, dependency := range dependencies { loaded = append(loaded, pinnedStdlibDependency(t, dependency)) }
    var modules *ModuleSet
    match NewModuleSet(loaded) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): modules = found }
    registry := otpRegistryForInvocation(t)
    for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
        fields := strings.Split(line, "|")
        if len(fields) != 3 || fields[0] != "case" { t.Fatalf("line %d is malformed", lineNumber+1) }
        expected := decodeGenServerCorpusTerm(t, fields[2])
        var process *VMProcess
        match modules.Invoke("gen_server_async_callbacks", fields[1], []term.Term{}, clock.Real{}, registry) {
        case result.Err(failure): t.Fatal(failure)
        case result.Ok(created): process = created
        }
        runtime := kernel.New(kernel.KernelConfig{})
        runtime.PersistentPut(term.Tuple(term.MustAtom("logger_config"), term.MustAtom("$primary_config$")), term.Integer(0))
        match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
        runtime.Run(1_000_000)
        assertGenServerCorpusOutcome(t, fields[1], 0, process.State(), expected)
    }
}
