package erts

import (
    "testing"
    "testing/quick"
	"time"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/option"
    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/kernel"
    "goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.gen-server-hibernate-wake-equivalence
func TestGenServerHibernateWakeStatefulEquivalenceLaw(t *testing.T) {
    modules := pinnedGenServerRemainingModules(t)
    registry := otpRegistryForInvocation(t)
    names := []string{"call", "cast", "info", "system", "code_change"}
    law := func(raw []uint8) bool {
        count := len(raw)%12 + 1
        operations := make([]term.Term, count)
        for index := range operations {
            choice := uint8(index)
            if len(raw) > 0 { choice = raw[index%len(raw)] }
            operations[index] = term.MustAtom(names[int(choice)%len(names)])
        }
        var process *VMProcess
        match modules.Invoke("gen_server_remaining_callbacks", "hibernate_equivalence", []term.Term{term.List(operations...)}, clock.Real{}, registry) { case result.Err(_): return false; case result.Ok(created): process = created }
        runtime := kernel.New(kernel.KernelConfig{})
        runtime.PersistentPut(term.Tuple(term.MustAtom("logger_config"), term.MustAtom("$primary_config$")), term.Integer(0))
        match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) { case result.Err(_): return false; case result.Ok(_): }
        deadline := time.Now().Add(time.Second)
        for time.Now().Before(deadline) {
            runtime.Run(8_000_000)
            settled := false
            match process.State() { case VMProcessWaiting(_, _), VMProcessSuspended(_, _): time.Sleep(time.Millisecond); case _: settled = true }
            if settled { break }
        }
        match process.State() {
        case VMProcessCompleted(value, _, _):
            match term.Elements(value) { case option.Some(parts): return len(parts) == 2 && term.Equal(parts[0], parts[1]); case option.None: return false }
        case _: return false
        }
    }
    match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 200})) { case result.Err(cause): t.Fatal(cause); case result.Ok(_): }
}
