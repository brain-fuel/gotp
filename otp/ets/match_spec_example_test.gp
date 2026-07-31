package ets

import (
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func thresholdSpec(result term.Term) term.Term {
	return term.List(term.Tuple(
		term.Tuple(term.MustAtom("$1"), term.MustAtom("$2")),
		term.List(term.Tuple(term.MustAtom(">"), term.MustAtom("$2"), term.Integer(10))),
		term.List(result),
	))
}

// assayxport:law gotp.otp.ets-match-spec-laws
func TestSelectEvaluatesGuardsAndBodyVariables(t *testing.T) {
	registry := NewRegistry(); owner := etsPID(1); id := mustTable(t, registry, owner, Set())
	for _, value := range []int64{5, 12, 20} { mustInsert(t, registry, owner, id, term.Tuple(term.Integer(value), term.Integer(value))) }
	match registry.Select(owner, id, thresholdSpec(term.MustAtom("$1"))) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(values):
		if len(values) != 2 || !term.Equal(values[0], term.Integer(12)) || !term.Equal(values[1], term.Integer(20)) { t.Fatalf("select = %v", values) }
	}
}

func TestSelectWholeObjectAndAllBindings(t *testing.T) {
	registry := NewRegistry(); owner := etsPID(1); id := mustTable(t, registry, owner, Set())
	object := term.Tuple(term.MustAtom("key"), term.Integer(14)); mustInsert(t, registry, owner, id, object)
	for _, output := range []term.Term{term.MustAtom("$_"), term.MustAtom("$$")} {
		match registry.Select(owner, id, term.List(term.Tuple(
			term.Tuple(term.MustAtom("$2"), term.MustAtom("$1")), term.List(), term.List(output),
		))) {
		case result.Err(failure): t.Fatal(failure)
		case result.Ok(values): if len(values) != 1 { t.Fatalf("select special output = %v", values) }
		}
	}
}

func TestSelectCountAndDeleteRequireTrueBody(t *testing.T) {
	registry := NewRegistry(); owner := etsPID(1); id := mustTable(t, registry, owner, Set())
	for _, value := range []int64{5, 12, 20} { mustInsert(t, registry, owner, id, term.Tuple(term.Integer(value), term.Integer(value))) }
	spec := thresholdSpec(term.MustAtom("true"))
	match registry.SelectCount(owner, id, spec) { case result.Err(failure): t.Fatal(failure); case result.Ok(count): if count != 2 { t.Fatalf("select_count = %d", count) } }
	match registry.SelectDelete(owner, id, spec) { case result.Err(failure): t.Fatal(failure); case result.Ok(count): if count != 2 { t.Fatalf("select_delete = %d", count) } }
	match registry.Objects(owner, id) { case result.Err(failure): t.Fatal(failure); case result.Ok(objects): if len(objects) != 1 { t.Fatalf("select_delete remainder = %v", objects) } }
}

func TestMatchSpecRejectsUnknownOperatorAndUnboundVariable(t *testing.T) {
	for _, spec := range []term.Term{
		term.List(term.Tuple(term.MustAtom("_"), term.List(term.Tuple(term.MustAtom("unknown"), term.Integer(1))), term.List(term.MustAtom("true")))),
		term.List(term.Tuple(term.MustAtom("_"), term.List(), term.List(term.MustAtom("$1")))),
	} {
		match CompileMatchSpec(spec) { case result.Ok(_): t.Fatal("invalid match spec compiled"); case result.Err(_): }
	}
}

func allObjectsSpec() term.Term {
	return term.List(term.Tuple(term.MustAtom("_"), term.List(), term.List(term.MustAtom("$_"))))
}

func TestLimitedSelectConcatenatesToUnlimitedSelect(t *testing.T) {
	registry := NewRegistry(); owner := etsPID(1); id := mustTable(t, registry, owner, OrderedSet())
	for value := int64(1); value <= 7; value++ {
		mustInsert(t, registry, owner, id, term.Tuple(term.Integer(value), term.MustAtom("value")))
	}
	var unlimited []term.Term
	match registry.Select(owner, id, allObjectsSpec()) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(values): unlimited = values
	}
	var page SelectPage
	match registry.SelectLimit(owner, id, allObjectsSpec(), 3) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(value): page = value
	}
	collected := []term.Term{}
	for {
		var current SelectPage = page
		match current {
		case SelectComplete(values):
			collected = append(collected, values...)
			if len(collected) != len(unlimited) { t.Fatalf("limited count = %d", len(collected)) }
			for index := range collected { if !term.Equal(collected[index], unlimited[index]) { t.Fatalf("limited values = %v", collected) } }
			return
		case SelectMore(values, continuation):
			collected = append(collected, values...)
			match ContinueSelect(continuation) {
			case result.Err(failure): t.Fatal(failure)
			case result.Ok(next): page = next
			}
		}
	}
}

func TestSelectContinuationReplayIsImmutable(t *testing.T) {
	registry := NewRegistry(); owner := etsPID(1); id := mustTable(t, registry, owner, Set())
	for value := int64(1); value <= 3; value++ { mustInsert(t, registry, owner, id, term.Tuple(term.Integer(value), term.Integer(value))) }
	match registry.SelectLimit(owner, id, allObjectsSpec(), 1) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(first):
		var checked SelectPage = first
		match checked {
		case SelectComplete(_): t.Fatal("first page unexpectedly complete")
		case SelectMore(_, continuation):
			var left SelectPage; var right SelectPage
			match ContinueSelect(continuation) { case result.Err(failure): t.Fatal(failure); case result.Ok(value): left = value }
			match ContinueSelect(continuation) { case result.Err(failure): t.Fatal(failure); case result.Ok(value): right = value }
			match left {
			case SelectComplete(leftValues):
				match right { case SelectComplete(rightValues): if len(leftValues) != len(rightValues) || !term.Equal(leftValues[0], rightValues[0]) { t.Fatal("continuation replay differed") }; case SelectMore(_, _): t.Fatal("continuation replay shape differed") }
			case SelectMore(leftValues, _):
				match right { case SelectMore(rightValues, _): if len(leftValues) != len(rightValues) || !term.Equal(leftValues[0], rightValues[0]) { t.Fatal("continuation replay differed") }; case SelectComplete(_): t.Fatal("continuation replay shape differed") }
			}
		}
	}
}

func TestLimitedSelectRejectsNonpositiveLimit(t *testing.T) {
	registry := NewRegistry(); owner := etsPID(1); id := mustTable(t, registry, owner, Set())
	match registry.SelectLimit(owner, id, allObjectsSpec(), 0) {
	case result.Ok(_): t.Fatal("zero select limit succeeded")
	case result.Err(_):
	}
}
