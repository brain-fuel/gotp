package term

import (
	"bytes"
	"math"
	"math/big"
	"strings"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

type Ordering enum {
	TermLess()
	TermEqual()
	TermGreater()
}

type OrderFailure enum {
	InvalidOrderedTerm()
	UnorderedFloat()
}

func orderFromInteger(value int) Ordering {
	if value < 0 {
		return TermLess()
	}
	if value > 0 {
		return TermGreater()
	}
	return TermEqual()
}

func reverseOrder(value Ordering) Ordering {
	match value {
	case TermLess:
		return TermGreater()
	case TermEqual:
		return TermEqual()
	case TermGreater:
		return TermLess()
	}
}

func compareFunForms(left FunForm, right FunForm) (Ordering, bool) {
	if left == nil || right == nil {
		return TermEqual(), false
	}
	leftRank := 0
	var leftDigest [16]byte
	var leftNewIndex uint32
	var leftOldIndex uint32
	match left {
	case LocalClosure:
		leftRank = 0
	case OldClosure:
		leftRank = 1
	case NewClosure(digest, newIndex, oldIndex):
		leftRank = 2
		leftDigest, leftNewIndex, leftOldIndex = digest, newIndex, oldIndex
	case ExportedFunction:
		leftRank = 3
	}
	rightRank := 0
	var rightDigest [16]byte
	var rightNewIndex uint32
	var rightOldIndex uint32
	match right {
	case LocalClosure:
		rightRank = 0
	case OldClosure:
		rightRank = 1
	case NewClosure(digest, newIndex, oldIndex):
		rightRank = 2
		rightDigest, rightNewIndex, rightOldIndex = digest, newIndex, oldIndex
	case ExportedFunction:
		rightRank = 3
	}
	if leftRank != rightRank {
		return orderFromInteger(leftRank - rightRank), true
	}
	if leftRank == 2 {
		if order := bytes.Compare(leftDigest[:], rightDigest[:]); order != 0 {
			return orderFromInteger(order), true
		}
		if leftNewIndex != rightNewIndex {
			if leftNewIndex < rightNewIndex { return TermLess(), true }
			return TermGreater(), true
		}
		if leftOldIndex != rightOldIndex {
			if leftOldIndex < rightOldIndex { return TermLess(), true }
			return TermGreater(), true
		}
	}
	return TermEqual(), true
}

func orderingInteger(value Term) option.Option[*big.Int] {
	return IntegerValue(value)
}

func compareNumbers(left Term, right Term) (Ordering, bool) {
	match orderingInteger(left) {
	case option.Some(leftInteger):
		match orderingInteger(right) {
		case option.Some(rightInteger):
			return orderFromInteger(leftInteger.Cmp(rightInteger)), true
		case option.None:
			match FloatValue(right) {
			case option.None:
				return TermEqual(), false
			case option.Some(rightFloat):
				if math.IsNaN(rightFloat) {
					return TermEqual(), false
				}
				rightRat := new(big.Rat)
				if rightRat.SetFloat64(rightFloat) == nil {
					if math.IsInf(rightFloat, 1) {
						return TermLess(), true
					}
					return TermGreater(), true
				}
				return orderFromInteger(new(big.Rat).SetInt(leftInteger).Cmp(rightRat)), true
			}
		}
	case option.None:
		match FloatValue(left) {
		case option.None:
			return TermEqual(), false
		case option.Some(leftFloat):
			if math.IsNaN(leftFloat) {
				return TermEqual(), false
			}
			match orderingInteger(right) {
			case option.Some(_):
				order, valid := compareNumbers(right, left)
				return reverseOrder(order), valid
			case option.None:
				match FloatValue(right) {
				case option.None:
					return TermEqual(), false
				case option.Some(rightFloat):
					if math.IsNaN(rightFloat) {
						return TermEqual(), false
					}
					if leftFloat < rightFloat {
						return TermLess(), true
					}
					if leftFloat > rightFloat {
						return TermGreater(), true
					}
					return TermEqual(), true
				}
			}
		}
	}
}

func orderRank(value Term) (int, bool) {
	var kind Kind = TermKind(value)
	match kind {
	case InvalidKind:
		return 0, false
	case IntegerKind, FloatKind:
		return 0, true
	case AtomKind:
		return 1, true
	case ReferenceKind:
		return 2, true
	case FunKind:
		return 3, true
	case PortKind:
		return 4, true
	case PIDKind:
		return 5, true
	case TupleKind:
		return 6, true
	case MapKind:
		return 7, true
	case ListKind:
		match Elements(value) {
		case option.Some(elements):
			if len(elements) == 0 {
				return 8, true
			}
		case option.None:
		}
		return 9, true
	case BinaryKind:
		return 10, true
	}
}

func compareTermSlices(left []Term, right []Term) (Ordering, bool) {
	limit := len(left)
	if len(right) < limit {
		limit = len(right)
	}
	for index := 0; index < limit; index++ {
		order, valid := compareTerms(left[index], right[index])
		if !valid {
			return TermEqual(), false
		}
		var checked Ordering = order
		match checked {
		case TermLess, TermGreater:
			return checked, true
		case TermEqual:
		}
	}
	return orderFromInteger(len(left) - len(right)), true
}

func listParts(value Term) ([]Term, Term, bool) {
	var kind Kind = TermKind(value)
	match kind {
	case ListKind:
		match Elements(value) {
		case option.None:
			return nil, InvalidValue(), false
		case option.Some(elements):
			match ImproperTail(value) {
			case option.None:
				return elements, List(), true
			case option.Some(tail):
				return elements, tail, true
			}
		}
	case InvalidKind, IntegerKind, FloatKind, AtomKind, BinaryKind, TupleKind, MapKind, PIDKind, ReferenceKind, FunKind, PortKind:
		return nil, InvalidValue(), false
	}
}

func compareLists(left Term, right Term) (Ordering, bool) {
	leftElements, leftTail, leftValid := listParts(left)
	rightElements, rightTail, rightValid := listParts(right)
	if !leftValid || !rightValid {
		return TermEqual(), false
	}
	limit := len(leftElements)
	if len(rightElements) < limit {
		limit = len(rightElements)
	}
	for index := 0; index < limit; index++ {
		order, valid := compareTerms(leftElements[index], rightElements[index])
		if !valid {
			return TermEqual(), false
		}
		var checked Ordering = order
		match checked {
		case TermLess, TermGreater:
			return checked, true
		case TermEqual:
		}
	}
	if len(leftElements) == len(rightElements) {
		return compareTerms(leftTail, rightTail)
	}
	if len(leftElements) < len(rightElements) {
		remainder := rightElements[limit:]
		return compareTerms(leftTail, ImproperList(remainder, rightTail))
	}
	remainder := leftElements[limit:]
	order, valid := compareTerms(rightTail, ImproperList(remainder, leftTail))
	return reverseOrder(order), valid
}

func exactKeyOrder(left Term, right Term) (Ordering, bool) {
	order, valid := compareTerms(left, right)
	if !valid {
		return TermEqual(), false
	}
	var checked Ordering = order
	match checked {
	case TermLess, TermGreater:
		return checked, true
	case TermEqual:
		if Equal(left, right) {
			return TermEqual(), true
		}
		var leftKind Kind = TermKind(left)
		match leftKind {
		case IntegerKind:
			return TermLess(), true
		case FloatKind:
			return TermGreater(), true
		case InvalidKind, AtomKind, BinaryKind, TupleKind, ListKind, MapKind, PIDKind, ReferenceKind, FunKind, PortKind:
			return TermEqual(), false
		}
	}
}

func sortedMapEntries(entries []MapEntry) ([]MapEntry, bool) {
	sorted := append([]MapEntry(nil), entries...)
	for index := 1; index < len(sorted); index++ {
		position := index
		for position > 0 {
			order, valid := exactKeyOrder(sorted[position].Key, sorted[position - 1].Key)
			if !valid {
				return nil, false
			}
			var checked Ordering = order
			match checked {
			case TermLess:
				sorted[position], sorted[position - 1] = sorted[position - 1], sorted[position]
				position--
			case TermEqual, TermGreater:
				position = 0
			}
		}
	}
	return sorted, true
}

func compareMaps(left Term, right Term) (Ordering, bool) {
	var leftEntries []MapEntry
	match MapEntries(left) {
	case option.None:
		return TermEqual(), false
	case option.Some(entries):
		leftEntries = entries
	}
	var rightEntries []MapEntry
	match MapEntries(right) {
	case option.None:
		return TermEqual(), false
	case option.Some(entries):
		rightEntries = entries
	}
	if len(leftEntries) != len(rightEntries) {
		return orderFromInteger(len(leftEntries) - len(rightEntries)), true
	}
	leftSorted, leftValid := sortedMapEntries(leftEntries)
	rightSorted, rightValid := sortedMapEntries(rightEntries)
	if !leftValid || !rightValid {
		return TermEqual(), false
	}
	for index := range leftSorted {
		keyOrder, valid := exactKeyOrder(leftSorted[index].Key, rightSorted[index].Key)
		if !valid {
			return TermEqual(), false
		}
		var checkedKey Ordering = keyOrder
		match checkedKey {
		case TermLess, TermGreater:
			return checkedKey, true
		case TermEqual:
		}
		valueOrder, valid := compareTerms(leftSorted[index].Value, rightSorted[index].Value)
		if !valid {
			return TermEqual(), false
		}
		var checkedValue Ordering = valueOrder
		match checkedValue {
		case TermLess, TermGreater:
			return checkedValue, true
		case TermEqual:
		}
	}
	return TermEqual(), true
}

func compareTerms(left Term, right Term) (Ordering, bool) {
	leftRank, leftValid := orderRank(left)
	rightRank, rightValid := orderRank(right)
	if !leftValid || !rightValid {
		return TermEqual(), false
	}
	if leftRank != rightRank {
		return orderFromInteger(leftRank - rightRank), true
	}
	if leftRank == 0 {
		return compareNumbers(left, right)
	}
	switch leftRank {
	case 1:
		var leftName string
		match AtomName(left) { case option.None: return TermEqual(), false; case option.Some(value): leftName = value }
		var rightName string
		match AtomName(right) { case option.None: return TermEqual(), false; case option.Some(value): rightName = value }
		return orderFromInteger(strings.Compare(leftName, rightName)), true
	case 2:
		var leftValue Reference
		match TermReferenceValue(left) { case option.None: return TermEqual(), false; case option.Some(value): leftValue = value }
		var rightValue Reference
		match TermReferenceValue(right) { case option.None: return TermEqual(), false; case option.Some(value): rightValue = value }
		if leftValue == rightValue { return TermEqual(), true }
		if leftValue.Less(rightValue) { return TermLess(), true }
		return TermGreater(), true
	case 3:
		var leftValue Fun
		match left.FunValue() { case option.None: return TermEqual(), false; case option.Some(value): leftValue = value }
		var rightValue Fun
		match right.FunValue() { case option.None: return TermEqual(), false; case option.Some(value): rightValue = value }
		formOrder, valid := compareFunForms(leftValue.Form, rightValue.Form)
		if !valid { return TermEqual(), false }
		var checkedForm Ordering = formOrder
		match checkedForm { case TermLess, TermGreater: return checkedForm, true; case TermEqual: }
		if leftValue.Module != rightValue.Module { return orderFromInteger(strings.Compare(leftValue.Module, rightValue.Module)), true }
		if leftValue.Function != rightValue.Function { return orderFromInteger(strings.Compare(leftValue.Function, rightValue.Function)), true }
		if leftValue.Arity != rightValue.Arity { if leftValue.Arity < rightValue.Arity { return TermLess(), true }; return TermGreater(), true }
		if leftValue.Label != rightValue.Label { if leftValue.Label < rightValue.Label { return TermLess(), true }; return TermGreater(), true }
		if leftValue.Index != rightValue.Index { if leftValue.Index < rightValue.Index { return TermLess(), true }; return TermGreater(), true }
		if leftValue.Unique != rightValue.Unique { if leftValue.Unique < rightValue.Unique { return TermLess(), true }; return TermGreater(), true }
		if leftValue.Creator != rightValue.Creator { if leftValue.Creator.Less(rightValue.Creator) { return TermLess(), true }; return TermGreater(), true }
		return compareTermSlices(leftValue.Environment, rightValue.Environment)
	case 4:
		var leftValue Port
		match TermPortValue(left) { case option.None: return TermEqual(), false; case option.Some(value): leftValue = value }
		var rightValue Port
		match TermPortValue(right) { case option.None: return TermEqual(), false; case option.Some(value): rightValue = value }
		if leftValue.Node != rightValue.Node { return orderFromInteger(int(leftValue.Node) - int(rightValue.Node)), true }
		if leftValue.ID < rightValue.ID { return TermLess(), true }; if leftValue.ID > rightValue.ID { return TermGreater(), true }
		return orderFromInteger(int(leftValue.Creation) - int(rightValue.Creation)), true
	case 5:
		var leftValue PID
		match TermPIDValue(left) { case option.None: return TermEqual(), false; case option.Some(value): leftValue = value }
		var rightValue PID
		match TermPIDValue(right) { case option.None: return TermEqual(), false; case option.Some(value): rightValue = value }
		if leftValue == rightValue { return TermEqual(), true }
		if leftValue.Less(rightValue) { return TermLess(), true }
		return TermGreater(), true
	case 6:
		var leftElements []Term
		match Elements(left) { case option.None: return TermEqual(), false; case option.Some(value): leftElements = value }
		var rightElements []Term
		match Elements(right) { case option.None: return TermEqual(), false; case option.Some(value): rightElements = value }
		if len(leftElements) != len(rightElements) { return orderFromInteger(len(leftElements) - len(rightElements)), true }
		return compareTermSlices(leftElements, rightElements)
	case 7:
		return compareMaps(left, right)
	case 8:
		return TermEqual(), true
	case 9:
		return compareLists(left, right)
	case 10:
		var leftBytes []byte
		match BinaryValue(left) { case option.None: return TermEqual(), false; case option.Some(value): leftBytes = value }
		var rightBytes []byte
		match BinaryValue(right) { case option.None: return TermEqual(), false; case option.Some(value): rightBytes = value }
		return orderFromInteger(bytes.Compare(leftBytes, rightBytes)), true
	default:
		return TermEqual(), false
	}
}

// assayxport:unit gotp.term.total-order
func Compare(left Term, right Term) result.Result[Ordering, OrderFailure] {
	order, valid := compareTerms(left, right)
	if !valid {
		match FloatValue(left) {
		case option.Some(value):
			if math.IsNaN(value) { return result.Err[Ordering, OrderFailure](UnorderedFloat()) }
		case option.None:
		}
		match FloatValue(right) {
		case option.Some(value):
			if math.IsNaN(value) { return result.Err[Ordering, OrderFailure](UnorderedFloat()) }
		case option.None:
		}
		return result.Err[Ordering, OrderFailure](InvalidOrderedTerm())
	}
	return result.Ok[Ordering, OrderFailure](order)
}
