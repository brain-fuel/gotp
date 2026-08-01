package erts

import (
    "sort"
    "testing"
    "testing/quick"

    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.gen-statem-request-collection-order
func TestGenStatemRequestCollectionStatefulOrderLaw(t *testing.T) {
    modules := pinnedGenStatemAsyncModules(t)
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
            sizes[index] = term.Integer(int64(count-index-1))
        }
        expected := term.Tuple(term.List(order...), term.List(sizes...))
        for _, module := range []string{"gen_statem_async_state_functions_callbacks", "gen_statem_async_handle_event_callbacks"} {
            process := invokeGenStatemFixture(t, modules, module, "property_collection", []term.Term{term.List(order...), term.MustAtom("true")})
            match process.State() {
            case VMProcessCompleted(value, _, _): if !term.Equal(value, expected) { return false }
            case _: return false
            }
        }
        return true
    }
    match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 200})) {
    case result.Err(cause): t.Fatal(cause)
    case result.Ok(_):
    }
}
