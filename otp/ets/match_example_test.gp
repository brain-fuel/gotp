package ets

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.otp.ets-object-pattern-laws
func TestRepeatedVariableUnifiesExactlyProperty(t *testing.T) {
	var compiled CompiledObjectPattern
	pattern := term.Tuple(term.MustAtom("$1"), term.MustAtom("$1"))
	match CompileObjectPattern(pattern) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(value):
		compiled = value
	}
	property := func(left int16, right int16) bool {
		bindings := make(map[int]term.Term)
		matched := objectPatternMatches(
			compiled.root,
			term.Tuple(term.Integer(int64(left)), term.Integer(int64(right))),
			bindings,
		)
		return matched == (left == right)
	}
	if failure := quick.Check(property, nil); failure != nil {
		t.Fatal(failure)
	}
}

func TestMatchReturnsVariablesInNumericOrder(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	id := mustTable(t, registry, owner, Bag())
	mustInsert(t, registry, owner, id, term.Tuple(
		term.MustAtom("person"), term.MustAtom("alice"),
		term.List(term.MustAtom("active"), term.Integer(7)),
	))
	mustInsert(t, registry, owner, id, term.Tuple(
		term.MustAtom("person"), term.MustAtom("bob"),
		term.List(term.MustAtom("inactive"), term.Integer(9)),
	))
	pattern := term.Tuple(
		term.MustAtom("person"), term.MustAtom("$2"),
		term.List(term.MustAtom("active"), term.MustAtom("$1")),
	)
	match registry.Match(owner, id, pattern) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(matches):
		if len(matches) != 1 || len(matches[0]) != 2 ||
			!term.Equal(matches[0][0], term.Integer(7)) ||
			!term.Equal(matches[0][1], term.MustAtom("alice")) {
			t.Fatalf("match bindings = %v", matches)
		}
	}
}

func TestMatchObjectWildcardAndAtomicDelete(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	id := mustTable(t, registry, owner, Bag())
	for _, status := range []string{"active", "inactive", "active"} {
		mustInsert(t, registry, owner, id, term.Tuple(
			term.MustAtom(status), term.Integer(int64(len(mustLookup(t, registry, owner, id, term.MustAtom(status))) + 1)),
		))
	}
	pattern := term.Tuple(term.MustAtom("active"), term.MustAtom("_"))
	match registry.MatchObject(owner, id, pattern) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(objects):
		if len(objects) != 2 {
			t.Fatalf("match_object count = %d", len(objects))
		}
	}
	match registry.MatchDelete(owner, id, pattern) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(removed):
		if removed != 2 {
			t.Fatalf("match_delete removed = %d", removed)
		}
	}
	match registry.Objects(owner, id) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(objects):
		if len(objects) != 1 {
			t.Fatalf("match_delete remainder = %v", objects)
		}
	}
}
