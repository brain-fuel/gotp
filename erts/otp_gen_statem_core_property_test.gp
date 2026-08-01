package erts

import (
    "testing"
    "testing/quick"

    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.gen-statem-callback-mode-trace-equivalence
func TestGenStatemCallbackModesHaveEquivalentTraceLaw(t *testing.T) {
    modules := pinnedGenStatemModules(t)
    names := []string{"set", "info", "sequence", "postpone", "repeat"}
    law := func(raw []uint8) bool {
        count := len(raw)%16 + 1
        operations := make([]term.Term, count)
        for index := range operations {
            choice := uint8(index)
            if len(raw) > 0 { choice = raw[index%len(raw)] }
            operations[index] = term.MustAtom(names[int(choice)%len(names)])
        }
        left := invokeGenStatemFixture(t, modules, "gen_statem_state_functions_callbacks", "trace", []term.Term{term.List(operations...)})
        right := invokeGenStatemFixture(t, modules, "gen_statem_handle_event_callbacks", "trace", []term.Term{term.List(operations...)})
        match left.State() {
        case VMProcessCompleted(leftValue, _, _):
            match right.State() {
            case VMProcessCompleted(rightValue, _, _): return term.Equal(leftValue, rightValue)
            case _: return false
            }
        case _: return false
        }
    }
    match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 200})) {
    case result.Err(cause): t.Fatal(cause)
    case result.Ok(_):
    }
}

// assayxport:law gotp.erts.gen-statem-timer-ordering
func TestGenStatemTimerOrderingLaw(t *testing.T) {
    modules := pinnedGenStatemModules(t)
    for _, module := range []string{"gen_statem_state_functions_callbacks", "gen_statem_handle_event_callbacks"} {
        process := invokeGenStatemFixture(t, modules, module, "timeouts", nil)
        expected := term.Tuple(term.MustAtom("ok"), term.Tuple(term.Integer(0), term.List(
            term.Tuple(term.MustAtom("enter"), term.MustAtom("idle"), term.MustAtom("idle")),
            term.Tuple(term.MustAtom("internal"), term.MustAtom("next")),
            term.MustAtom("state_timeout"), term.MustAtom("named_timeout"))))
        assertGenServerCorpusOutcome(t, "timeouts", 0, process.State(), expected)
    }
}

// assayxport:law gotp.erts.gen-statem-postponed-event-retry
func TestGenStatemPostponedEventRetriesAfterStateChangeLaw(t *testing.T) {
    modules := pinnedGenStatemModules(t)
    for _, module := range []string{"gen_statem_state_functions_callbacks", "gen_statem_handle_event_callbacks"} {
        process := invokeGenStatemFixture(t, modules, module, "trace", []term.Term{term.List(term.MustAtom("postpone"))})
        match process.State() {
        case VMProcessCompleted(value, _, _):
            if !containsGenStatemAtom(value, "postponed") { t.Fatalf("%s did not retry postponed event: %v", module, value) }
        case _: t.Fatalf("%s did not complete", module)
        }
    }
}

func containsGenStatemAtom(value term.Term, wanted string) bool {
    match value {
    case term.AtomTerm(atom): return atom == wanted
    case term.TupleTerm(parts): for _, part := range parts { if containsGenStatemAtom(part, wanted) { return true } }
    case term.ProperListTerm(parts): for _, part := range parts { if containsGenStatemAtom(part, wanted) { return true } }
    case term.ImproperListTerm(parts, tail): for _, part := range parts { if containsGenStatemAtom(part, wanted) { return true } }; return containsGenStatemAtom(tail, wanted)
    case _:
    }
    return false
}
