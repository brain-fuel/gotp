package erts

import (
    "testing"
    "testing/quick"

    "goforge.dev/goplus/std/clock"
    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/beam"
    "goforge.dev/gotp/kernel"
    "goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.gen-server-enter-loop-equivalence
func TestGenServerEnterLoopStatefulEquivalenceLaw(t *testing.T) {
    var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
    var callback *LoadedModule
    match LoadModuleFile(read, "testdata/otp-29.0.4/gen_server_enter_loop_callbacks.beam", ModuleLoaderConfig{}) {
    case result.Err(failure): t.Fatal(failure)
    case result.Ok(found): callback = found
    }
    dependencies := []string{"sets", "gen", "proc_lib", "sys", "global", "code", "io", "io_lib", "logger", "logger_config", "error_logger"}
    loaded := []*LoadedModule{callback, pinnedGenServerModule(t), pinnedListsModule(t), pinnedMapsModule(t)}
    for _, dependency := range dependencies { loaded = append(loaded, pinnedStdlibDependency(t, dependency)) }
    var modules *ModuleSet
    match NewModuleSet(loaded) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): modules = found }
    registry := otpRegistryForInvocation(t)
    operationNames := []string{"increment", "info", "suspend", "code_change", "get"}
    law := func(raw []uint8) bool {
        count := len(raw)%12 + 1
        operations := make([]term.Term, count)
        for index := range operations {
            choice := uint8(index)
            if len(raw) > 0 { choice = raw[index%len(raw)] }
            operations[index] = term.MustAtom(operationNames[int(choice)%len(operationNames)])
        }
        var process *VMProcess
        match modules.Invoke("gen_server_enter_loop_callbacks", "property_equivalence", []term.Term{term.List(operations...)}, clock.Real{}, registry) {
        case result.Err(_): return false
        case result.Ok(created): process = created
        }
        runtime := kernel.New(kernel.KernelConfig{})
        runtime.PersistentPut(term.Tuple(term.MustAtom("logger_config"), term.MustAtom("$primary_config$")), term.Integer(0))
        match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) { case result.Err(_): return false; case result.Ok(_): }
        runtime.Run(4_000_000)
        match process.State() {
        case VMProcessCompleted(value, _, _): return term.Equal(value, term.MustAtom("equivalent"))
        case _: return false
        }
    }
    match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 200})) {
    case result.Err(cause): t.Fatal(cause)
    case result.Ok(_):
    }
}
