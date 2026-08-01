package erts

import (
    "sort"
    "testing"
    "testing/quick"

    "goforge.dev/goplus/std/clock"
    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/beam"
    "goforge.dev/gotp/kernel"
    "goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.gen-server-request-collection-order
func TestGenServerRequestCollectionStatefulOrderLaw(t *testing.T) {
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
    law := func(raw []uint8) bool {
        count := len(raw)%8 + 1
        type rankedLabel struct { rank uint8; label int }
        ranked := make([]rankedLabel, count)
        for index := range ranked {
            rank := uint8(index)
            if len(raw) > 0 { rank = raw[index%len(raw)] }
            ranked[index] = rankedLabel{rank: rank, label: index + 1}
        }
        sort.Slice(ranked, func(left, right int) bool {
            if ranked[left].rank == ranked[right].rank { return ranked[left].label < ranked[right].label }
            return ranked[left].rank < ranked[right].rank
        })
        order := make([]term.Term, count)
        sizes := make([]term.Term, count)
        for index, item := range ranked {
            order[index] = term.Integer(int64(item.label))
            sizes[index] = term.Integer(int64(count - index - 1))
        }
        var process *VMProcess
        match modules.Invoke("gen_server_async_callbacks", "property_collection", []term.Term{term.List(order...)}, clock.Real{}, registry) {
        case result.Err(_): return false
        case result.Ok(created): process = created
        }
        runtime := kernel.New(kernel.KernelConfig{})
        runtime.PersistentPut(term.Tuple(term.MustAtom("logger_config"), term.MustAtom("$primary_config$")), term.Integer(0))
        match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) { case result.Err(_): return false; case result.Ok(_): }
        runtime.Run(1_000_000)
        expected := term.Tuple(term.List(order...), term.List(sizes...))
        match process.State() {
        case VMProcessCompleted(value, _, _): return term.Equal(value, expected)
        case _: return false
        }
    }
    match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 200})) {
    case result.Err(cause): t.Fatal(cause)
    case result.Ok(_):
    }
}
