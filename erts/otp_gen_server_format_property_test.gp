package erts

import (
    "testing"
    "testing/quick"
	"time"

    "goforge.dev/goplus/std/clock"
    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/kernel"
    "goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.gen-server-format-determinism
func TestGenServerFormattingDeterminismLaw(t *testing.T) {
    modules := pinnedGenServerFormatModules(t)
    registry := otpRegistryForInvocation(t)
    law := func(raw []uint8) bool {
        functions := []string{"format_log_multi_unicode", "format_log_single_depth", "format_log_chars_limit", "format_log_no_handle_info"}
        function := functions[len(raw)%len(functions)]
        first, firstOK := invokeGenServerFormatLaw(modules, registry, function, []term.Term{})
        second, secondOK := invokeGenServerFormatLaw(modules, registry, function, []term.Term{})
        return firstOK && secondOK && term.Equal(first, second)
    }
    match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 200})) { case result.Err(cause): t.Fatal(cause); case result.Ok(_): }
}

// assayxport:law gotp.erts.gen-server-enter-loop-status-equivalence
func TestGenServerEnterLoopStatusEquivalenceLaw(t *testing.T) {
    modules := pinnedGenServerFormatModules(t)
    registry := otpRegistryForInvocation(t)
    operationNames := []string{"increment", "info", "suspend", "code_change"}
    law := func(raw []uint8) bool {
        count := len(raw)%10 + 1
        operations := make([]term.Term, count)
        for index := range operations {
            choice := uint8(index)
            if len(raw) > 0 { choice = raw[index%len(raw)] }
            operations[index] = term.MustAtom(operationNames[int(choice)%len(operationNames)])
        }
        value, ok := invokeGenServerFormatLaw(modules, registry, "status_equivalence", []term.Term{term.List(operations...)})
        return ok && term.Equal(value, term.MustAtom("equivalent"))
    }
    match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 200})) { case result.Err(cause): t.Fatal(cause); case result.Ok(_): }
}

func invokeGenServerFormatLaw(modules *ModuleSet, registry *CallRegistry, function string, arguments []term.Term) (term.Term, bool) {
    var empty term.Term
    var process *VMProcess
    match modules.Invoke("gen_server_format_callbacks", function, arguments, clock.Real{}, registry) { case result.Err(_): return empty, false; case result.Ok(created): process = created }
    runtime := kernel.New(kernel.KernelConfig{})
    runtime.PersistentPut(term.Tuple(term.MustAtom("logger_config"), term.MustAtom("$primary_config$")), term.Integer(0))
    match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) { case result.Err(_): return empty, false; case result.Ok(_): }
    deadline := time.Now().Add(500 * time.Millisecond)
    for time.Now().Before(deadline) {
        runtime.Run(4_000_000)
        settled := false
        match process.State() { case VMProcessWaiting(_, _), VMProcessSuspended(_, _): time.Sleep(time.Millisecond); case _: settled = true }
        if settled { break }
    }
    match process.State() { case VMProcessCompleted(value, _, _): return value, true; case _: return empty, false }
}
