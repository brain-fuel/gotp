package term

import (
	"math/big"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/nonempty"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

func TestTermExactEqualityLaws(t *testing.T) {
	reflexive := func(raw int64) bool {
		value := Integer(raw)
		return value.Equal(value)
	}
	symmetric := func(left int64, right int64) bool {
		a := Integer(left)
		b := Integer(right)
		return a.Equal(b) == b.Equal(a)
	}
	transitive := func(raw int64) bool {
		a := Integer(raw)
		b := a.Clone()
		c := b.Clone()
		return a.Equal(b) && b.Equal(c) && a.Equal(c)
	}
	match result.Of(true, quick.Check(reflexive, nil)) {
	case result.Err(cause):
		t.Fatalf("reflexive: %v", cause)
	case result.Ok(_):
	}
	match result.Of(true, quick.Check(symmetric, nil)) {
	case result.Err(cause):
		t.Fatalf("symmetric: %v", cause)
	case result.Ok(_):
	}
	match result.Of(true, quick.Check(transitive, nil)) {
	case result.Err(cause):
		t.Fatalf("transitive: %v", cause)
	case result.Ok(_):
	}
}

func TestConstructorsOwnMutableInput(t *testing.T) {
	input := []byte{1, 2, 3}
	value := Binary(input)
	input[0] = 9
	match value.BinaryValue() {
	case option.None:
		t.Fatal("binary projection failed")
	case option.Some(got):
		if got[0] != 1 {
			t.Fatalf("binary = %v", got)
		}
		got[1] = 9
	}
	match value.BinaryValue() {
	case option.None:
		t.Fatal("binary projection failed")
	case option.Some(got):
		if got[1] != 2 {
			t.Fatalf("binary accessor exposed storage: %v", got)
		}
	}

	large := new(big.Int).Lsh(big.NewInt(1), 200)
	var integer Term
	match BigInteger(large) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(value):
		integer = value
	}
	large.SetInt64(0)
	match integer.IntegerValue() {
	case option.None:
		t.Fatal("integer projection failed")
	case option.Some(got):
		if got.BitLen() != 201 {
			t.Fatalf("big integer = %v", got)
		}
	}
}

func TestMapEqualityIgnoresInsertionOrder(t *testing.T) {
	var left Term
	match Map([]MapEntry{
		{Key: MustAtom("a"), Value: Integer(1)},
		{Key: MustAtom("b"), Value: Integer(2)},
	}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(value):
		left = value
	}
	var right Term
	match Map([]MapEntry{
		{Key: MustAtom("b"), Value: Integer(2)},
		{Key: MustAtom("a"), Value: Integer(1)},
	}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(value):
		right = value
	}
	if !left.Equal(right) {
		t.Fatal("map equality depends on insertion order")
	}
}

func TestMapRejectsDuplicateExactKeys(t *testing.T) {
	match Map([]MapEntry{
		{Key: Integer(1), Value: MustAtom("first")},
		{Key: Integer(1), Value: MustAtom("second")},
	}) {
	case result.Ok(_):
		t.Fatal("duplicate map keys were accepted")
	case result.Err(failure):
		match failure {
		case DuplicateMapKey(first, second):
			if first != 0 || second != 1 {
				t.Fatalf("duplicate indexes = %d, %d", first, second)
			}
		case _:
			t.Fatalf("unexpected failure: %v", failure)
		}
	}
}

func TestAtomLimits(t *testing.T) {
	match Atom(string([]byte{0xff})) {
	case result.Ok(_):
		t.Fatal("invalid UTF-8 atom was accepted")
	case result.Err(_):
	}
	runes := make([]rune, 256)
	for index := range runes {
		runes[index] = 'a'
	}
	match Atom(string(runes)) {
	case result.Ok(_):
		t.Fatal("oversized atom was accepted")
	case result.Err(_):
	}
}

func TestReferenceRequiresNonEmptyBoundedWords(t *testing.T) {
	words := nonempty.Of[uint32](1, 2, 3, 4, 5)
	match ReferenceOf(1, 7, words) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(reference):
		if !reference.Valid() || reference.Length != 5 {
			t.Fatalf("reference = %#v", reference)
		}
	}
	tooMany := nonempty.Of[uint32](1, 2, 3, 4, 5, 6)
	match ReferenceOf(1, 7, tooMany) {
	case result.Ok(_):
		t.Fatal("oversized reference was accepted")
	case result.Err(_):
	}
}
