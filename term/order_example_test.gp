package term

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
)

func orderingSign(value Ordering) int {
	var checked Ordering = value
	match checked {
	case TermLess:
		return -1
	case TermEqual:
		return 0
	case TermGreater:
		return 1
	}
}

func compareSign(left Term, right Term) (int, bool) {
	match Compare(left, right) {
	case result.Err(_):
		return 0, false
	case result.Ok(order):
		return orderingSign(order), true
	}
}

// assayxport:law gotp.term.total-order-laws
func TestIntegerOrderAntisymmetryProperty(t *testing.T) {
	property := func(left int64, right int64) bool {
		forward, forwardValid := compareSign(Integer(left), Integer(right))
		reverse, reverseValid := compareSign(Integer(right), Integer(left))
		return forwardValid && reverseValid && forward == -reverse
	}
	match result.Of(struct{}{}, quick.Check(property, nil)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
}

func TestIntegerOrderTransitivityProperty(t *testing.T) {
	property := func(first int64, second int64, third int64) bool {
		firstSecond, validFirstSecond := compareSign(Integer(first), Integer(second))
		secondThird, validSecondThird := compareSign(Integer(second), Integer(third))
		firstThird, validFirstThird := compareSign(Integer(first), Integer(third))
		if !validFirstSecond || !validSecondThird || !validFirstThird {
			return false
		}
		if firstSecond <= 0 && secondThird <= 0 {
			return firstThird <= 0
		}
		return true
	}
	match result.Of(struct{}{}, quick.Check(property, nil)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
}

func TestListOrderLexicographicProperty(t *testing.T) {
	property := func(prefix []byte, left byte, right byte) bool {
		if left >= right {
			return true
		}
		leftTerms := make([]Term, 0, len(prefix) + 1)
		rightTerms := make([]Term, 0, len(prefix) + 1)
		for _, value := range prefix {
			leftTerms = append(leftTerms, Integer(int64(value)))
			rightTerms = append(rightTerms, Integer(int64(value)))
		}
		leftTerms = append(leftTerms, Integer(int64(left)))
		rightTerms = append(rightTerms, Integer(int64(right)))
		order, valid := compareSign(List(leftTerms...), List(rightTerms...))
		return valid && order < 0
	}
	match result.Of(struct{}{}, quick.Check(property, nil)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
}

func TestErlangKindOrder(t *testing.T) {
	var emptyMap Term
	match Map(nil) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(value):
		emptyMap = value
	}
	values := []Term{
		Integer(0),
		MustAtom("atom"),
		ReferenceValue(Reference{Node: 1, Creation: 1, Words: [5]uint32{1}, Length: 1}),
		Function(Fun{Form: LocalClosure(), Module: "demo", Function: "f", Arity: 0, Label: 1}),
		PortValue(Port{Node: 1, ID: 1, Creation: 1}),
		PIDValue(PID{Node: 1, Number: 1, Creation: 1}),
		Tuple(),
		emptyMap,
		List(),
		List(Integer(0)),
		Binary(nil),
	}
	for index := 1; index < len(values); index++ {
		order, valid := compareSign(values[index - 1], values[index])
		if !valid || order >= 0 {
			t.Fatalf("kind order %d: %T !< %T", index, values[index - 1], values[index])
		}
	}
}
