package erts

import (
    "testing"
    "testing/quick"

    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.gen-statem-format-determinism
func TestGenStatemFormattingDeterminismLaw(t *testing.T) {
    modules := pinnedGenStatemFormatModules(t)
    law := func(raw []uint8) bool {
        state := term.Tuple(term.MustAtom("state"), statemFormatBytes(raw))
        data := term.Tuple(term.MustAtom("data"), statemFormatBytes(raw), term.Integer(int64(len(raw))))
        event := term.Tuple(term.MustAtom("event"), term.List(state, data))
        variant := term.Integer(int64(len(raw) % 4))
        arguments := []term.Term{state, data, event, variant}
        left1, leftOK1 := invokeGenStatemFormatLaw(t, modules, "gen_statem_format_state_functions_callbacks", arguments)
        left2, leftOK2 := invokeGenStatemFormatLaw(t, modules, "gen_statem_format_state_functions_callbacks", arguments)
        right, rightOK := invokeGenStatemFormatLaw(t, modules, "gen_statem_format_handle_event_callbacks", arguments)
        return leftOK1 && leftOK2 && rightOK && term.Equal(left1, left2) && term.Equal(left1, right)
    }
    match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 200})) {
    case result.Err(cause): t.Fatal(cause)
    case result.Ok(_):
    }
}

func statemFormatBytes(raw []uint8) term.Term {
    values := make([]term.Term, len(raw))
    for index, value := range raw { values[index] = term.Integer(int64(value)) }
    return term.List(values...)
}

func invokeGenStatemFormatLaw(t *testing.T, modules *ModuleSet, module string, arguments []term.Term) (term.Term, bool) {
    process := invokeGenStatemFixture(t, modules, module, "format_generated", arguments)
    match process.State() {
    case VMProcessCompleted(value, _, _): return value, true
    case _: var empty term.Term; return empty, false
    }
}
