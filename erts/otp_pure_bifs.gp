package erts

import (
	"math"
	"math/big"
	"strconv"
	"strings"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

type otpNumber enum {
	otpInteger(Value *big.Int)
	otpFloat(Value float64)
}

type otpArithmeticOperation enum {
	otpAdd()
	otpSubtract()
	otpMultiply()
}

func otpBadarg() vm.ExternalCallOutcome {
	return vm.ExternalCallRejected("badarg")
}

func otpBadarith() vm.ExternalCallOutcome {
	return vm.ExternalCallRejected("badarith")
}

// assayxport:unit gotp.erts.otp-exception-bifs
func otpError(arguments []term.Term) vm.ExternalCallOutcome {
	return vm.ExternalCallRaised(term.MustAtom("error"), term.Clone(arguments[0]))
}

func otpThrow(arguments []term.Term) vm.ExternalCallOutcome {
	return vm.ExternalCallRaised(term.MustAtom("throw"), term.Clone(arguments[0]))
}

func otpExit(arguments []term.Term) vm.ExternalCallOutcome {
	return vm.ExternalCallRaised(term.MustAtom("exit"), term.Clone(arguments[0]))
}

func otpRaise(arguments []term.Term) vm.ExternalCallOutcome {
	match term.AtomName(arguments[0]) {
	case option.Some(class):
		switch class {
		case "error", "exit", "throw":
			return vm.ExternalCallRaised(term.Clone(arguments[0]), term.Clone(arguments[1]))
		default:
			return vm.ExternalCallRaised(term.MustAtom("error"), term.MustAtom("badarg"))
		}
	case option.None:
		return vm.ExternalCallRaised(term.MustAtom("error"), term.MustAtom("badarg"))
	}
}

func otpNumberOf(value term.Term) option.Option[otpNumber] {
	match term.IntegerValue(value) {
	case option.Some(integer):
		return option.Some[otpNumber](otpInteger(integer))
	case option.None:
	}
	match term.FloatValue(value) {
	case option.Some(float):
		return option.Some[otpNumber](otpFloat(float))
	case option.None:
		return option.None[otpNumber]()
	}
}

func otpFloatOf(value otpNumber) option.Option[float64] {
	match value {
	case otpFloat(float):
		return option.Some(float)
	case otpInteger(integer):
		float, _ := integer.Float64()
		if math.IsInf(float, 0) {
			return option.None[float64]()
		}
		return option.Some(float)
	}
}

func otpArithmetic(arguments []term.Term, operation otpArithmeticOperation) vm.ExternalCallOutcome {
	var left otpNumber
	match otpNumberOf(arguments[0]) {
	case option.None:
		return otpBadarith()
	case option.Some(number):
		left = number
	}
	var right otpNumber
	match otpNumberOf(arguments[1]) {
	case option.None:
		return otpBadarith()
	case option.Some(number):
		right = number
	}
	match left {
	case otpInteger(leftInteger):
		match right {
		case otpInteger(rightInteger):
			value := new(big.Int)
			match operation {
			case otpAdd:
				value.Add(leftInteger, rightInteger)
			case otpSubtract:
				value.Sub(leftInteger, rightInteger)
			case otpMultiply:
				value.Mul(leftInteger, rightInteger)
			}
			return vm.ExternalCallReturned(term.MustBigInteger(value))
		case otpFloat(_):
		}
	case otpFloat(_):
	}
	var leftFloat float64
	match otpFloatOf(left) {
	case option.None:
		return otpBadarith()
	case option.Some(value):
		leftFloat = value
	}
	var rightFloat float64
	match otpFloatOf(right) {
	case option.None:
		return otpBadarith()
	case option.Some(value):
		rightFloat = value
	}
	match operation {
	case otpAdd:
		return vm.ExternalCallReturned(term.Float(leftFloat + rightFloat))
	case otpSubtract:
		return vm.ExternalCallReturned(term.Float(leftFloat - rightFloat))
	case otpMultiply:
		return vm.ExternalCallReturned(term.Float(leftFloat * rightFloat))
	}
}

func otpIntegerDivide(arguments []term.Term) vm.ExternalCallOutcome {
	var left *big.Int
	match term.IntegerValue(arguments[0]) {
	case option.None:
		return otpBadarith()
	case option.Some(value):
		left = value
	}
	match term.IntegerValue(arguments[1]) {
	case option.None:
		return otpBadarith()
	case option.Some(right):
		if right.Sign() == 0 {
			return otpBadarith()
		}
		return vm.ExternalCallReturned(term.MustBigInteger(new(big.Int).Quo(left, right)))
	}
}

func otpProperElements(value term.Term) option.Option[[]term.Term] {
	var kind term.Kind = term.TermKind(value)
	match kind {
	case term.ListKind:
		match term.ImproperTail(value) {
		case option.Some(_):
			return option.None[[]term.Term]()
		case option.None:
			return term.Elements(value)
		}
	case term.InvalidKind, term.IntegerKind, term.FloatKind, term.AtomKind, term.BinaryKind, term.TupleKind, term.MapKind, term.PIDKind, term.ReferenceKind, term.FunKind, term.PortKind:
		return option.None[[]term.Term]()
	}
}

func otpTupleElements(value term.Term) option.Option[[]term.Term] {
	var kind term.Kind = term.TermKind(value)
	match kind {
	case term.TupleKind:
		return term.Elements(value)
	case term.InvalidKind, term.IntegerKind, term.FloatKind, term.AtomKind, term.BinaryKind, term.ListKind, term.MapKind, term.PIDKind, term.ReferenceKind, term.FunKind, term.PortKind:
		return option.None[[]term.Term]()
	}
}

func otpListAppend(arguments []term.Term) vm.ExternalCallOutcome {
	match otpProperElements(arguments[0]) {
	case option.None:
		return otpBadarg()
	case option.Some(left):
		if len(left) == 0 {
			return vm.ExternalCallReturned(term.Clone(arguments[1]))
		}
		match otpProperElements(arguments[1]) {
		case option.None:
			return vm.ExternalCallReturned(term.ImproperList(left, arguments[1]))
		case option.Some(right):
			joined := make([]term.Term, 0, len(left) + len(right))
			joined = append(joined, left...)
			joined = append(joined, right...)
			return vm.ExternalCallReturned(term.List(joined...))
		}
	}
}

func otpListSubtract(arguments []term.Term) vm.ExternalCallOutcome {
	var left []term.Term
	match otpProperElements(arguments[0]) {
	case option.None:
		return otpBadarg()
	case option.Some(elements):
		left = append([]term.Term(nil), elements...)
	}
	match otpProperElements(arguments[1]) {
	case option.None:
		return otpBadarg()
	case option.Some(right):
		for _, remove := range right {
			for index, candidate := range left {
				if term.Equal(candidate, remove) {
					left = append(left[:index], left[index + 1:]...)
					break
				}
			}
		}
		return vm.ExternalCallReturned(term.List(left...))
	}
}

func otpLength(arguments []term.Term) vm.ExternalCallOutcome {
	match otpProperElements(arguments[0]) {
	case option.None:
		return otpBadarg()
	case option.Some(elements):
		return vm.ExternalCallReturned(term.MustBigInteger(new(big.Int).SetUint64(uint64(len(elements)))))
	}
}

func otpMember(arguments []term.Term) vm.ExternalCallOutcome {
	match otpProperElements(arguments[1]) {
	case option.None:
		return otpBadarg()
	case option.Some(elements):
		for _, candidate := range elements {
			if term.Equal(arguments[0], candidate) {
				return vm.ExternalCallReturned(term.MustAtom("true"))
			}
		}
		return vm.ExternalCallReturned(term.MustAtom("false"))
	}
}

func otpKeyPosition(value term.Term) option.Option[int] {
	match term.IntegerValue(value) {
	case option.None:
		return option.None[int]()
	case option.Some(integer):
		if !integer.IsInt64() || integer.Sign() <= 0 {
			return option.None[int]()
		}
		position := integer.Int64() - 1
		if uint64(position) > uint64(^uint(0) >> 1) {
			return option.None[int]()
		}
		return option.Some(int(position))
	}
}

func otpComparesEqual(left term.Term, right term.Term) (bool, bool) {
	match term.Compare(left, right) {
	case result.Err(_):
		return false, false
	case result.Ok(order):
		var checked term.Ordering = order
		match checked {
		case term.TermEqual:
			return true, true
		case term.TermLess, term.TermGreater:
			return false, true
		}
	}
}

func otpFindKey(arguments []term.Term) (term.Term, bool, bool) {
	var position int
	match otpKeyPosition(arguments[1]) {
	case option.None:
		return term.InvalidValue(), false, false
	case option.Some(value):
		position = value
	}
	match otpProperElements(arguments[2]) {
	case option.None:
		return term.InvalidValue(), false, false
	case option.Some(elements):
		for _, candidate := range elements {
			match otpTupleElements(candidate) {
			case option.None:
			case option.Some(tuple):
				if position < len(tuple) {
					equal, valid := otpComparesEqual(arguments[0], tuple[position])
					if !valid {
						return term.InvalidValue(), false, false
					}
					if equal {
						return term.Clone(candidate), true, true
					}
				}
			}
		}
		return term.InvalidValue(), false, true
	}
}

func otpKeyFind(arguments []term.Term) vm.ExternalCallOutcome {
	value, found, valid := otpFindKey(arguments)
	if !valid {
		return otpBadarg()
	}
	if !found {
		return vm.ExternalCallReturned(term.MustAtom("false"))
	}
	return vm.ExternalCallReturned(value)
}

func otpKeyMember(arguments []term.Term) vm.ExternalCallOutcome {
	_, found, valid := otpFindKey(arguments)
	if !valid {
		return otpBadarg()
	}
	if found {
		return vm.ExternalCallReturned(term.MustAtom("true"))
	}
	return vm.ExternalCallReturned(term.MustAtom("false"))
}

func otpKeySearch(arguments []term.Term) vm.ExternalCallOutcome {
	value, found, valid := otpFindKey(arguments)
	if !valid {
		return otpBadarg()
	}
	if !found {
		return vm.ExternalCallReturned(term.MustAtom("false"))
	}
	return vm.ExternalCallReturned(term.Tuple(term.MustAtom("value"), value))
}

func otpCharacters(value string) term.Term {
	characters := make([]term.Term, 0, len(value))
	for _, character := range value {
		characters = append(characters, term.Integer(int64(character)))
	}
	return term.List(characters...)
}

func otpIntegerToList(arguments []term.Term) vm.ExternalCallOutcome {
	match term.IntegerValue(arguments[0]) {
	case option.None:
		return otpBadarg()
	case option.Some(value):
		return vm.ExternalCallReturned(otpCharacters(value.String()))
	}
}

func otpFloatToList(arguments []term.Term) vm.ExternalCallOutcome {
	match term.FloatValue(arguments[0]) {
	case option.None:
		return otpBadarg()
	case option.Some(value):
		text := strconv.FormatFloat(value, 'g', -1, 64)
		if !strings.ContainsAny(text, ".eE") {
			text += ".0"
		}
		return vm.ExternalCallReturned(otpCharacters(text))
	}
}

func otpAtomToList(arguments []term.Term) vm.ExternalCallOutcome {
	match term.AtomName(arguments[0]) {
	case option.None:
		return otpBadarg()
	case option.Some(value):
		return vm.ExternalCallReturned(otpCharacters(value))
	}
}

func otpElement(arguments []term.Term) vm.ExternalCallOutcome {
	var index *big.Int
	match term.IntegerValue(arguments[0]) {
	case option.None:
		return otpBadarg()
	case option.Some(value):
		index = value
	}
	if !index.IsInt64() || index.Sign() <= 0 {
		return otpBadarg()
	}
	match otpTupleElements(arguments[1]) {
	case option.None:
		return otpBadarg()
	case option.Some(elements):
		position := index.Int64() - 1
		if position >= int64(len(elements)) {
			return otpBadarg()
		}
		return vm.ExternalCallReturned(term.Clone(elements[position]))
	}
}

func otpSetElement(arguments []term.Term) vm.ExternalCallOutcome {
	var index *big.Int
	match term.IntegerValue(arguments[0]) {
	case option.None:
		return otpBadarg()
	case option.Some(value):
		index = value
	}
	if !index.IsInt64() || index.Sign() <= 0 {
		return otpBadarg()
	}
	match otpTupleElements(arguments[1]) {
	case option.None:
		return otpBadarg()
	case option.Some(elements):
		position := index.Int64() - 1
		if position >= int64(len(elements)) {
			return otpBadarg()
		}
		updated := append([]term.Term(nil), elements...)
		updated[position] = term.Clone(arguments[2])
		return vm.ExternalCallReturned(term.Tuple(updated...))
	}
}

// assayxport:unit gotp.erts.otp-pure-bifs
func otpPureBindings() []CallBinding {
	return []CallBinding{
		{Target: vm.ExternalFunction{Module: "erlang", Function: "++", Arity: 2}, Implementation: otpListAppend},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "--", Arity: 2}, Implementation: otpListSubtract},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "-", Arity: 2}, Implementation: func(arguments []term.Term) vm.ExternalCallOutcome { return otpArithmetic(arguments, otpSubtract()) }},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "length", Arity: 1}, Implementation: otpLength},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "=:=", Arity: 2}, Implementation: func(arguments []term.Term) vm.ExternalCallOutcome {
			if term.Equal(arguments[0], arguments[1]) {
				return vm.ExternalCallReturned(term.MustAtom("true"))
			}
			return vm.ExternalCallReturned(term.MustAtom("false"))
		}},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "+", Arity: 2}, Implementation: func(arguments []term.Term) vm.ExternalCallOutcome { return otpArithmetic(arguments, otpAdd()) }},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "div", Arity: 2}, Implementation: otpIntegerDivide},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "*", Arity: 2}, Implementation: func(arguments []term.Term) vm.ExternalCallOutcome { return otpArithmetic(arguments, otpMultiply()) }},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "integer_to_list", Arity: 1}, Implementation: otpIntegerToList},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "float_to_list", Arity: 1}, Implementation: otpFloatToList},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "atom_to_list", Arity: 1}, Implementation: otpAtomToList},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "element", Arity: 2}, Implementation: otpElement},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "setelement", Arity: 3}, Implementation: otpSetElement},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "error", Arity: 1}, Implementation: otpError},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "error", Arity: 2}, Implementation: otpError},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "error", Arity: 3}, Implementation: otpError},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "throw", Arity: 1}, Implementation: otpThrow},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "exit", Arity: 1}, Implementation: otpExit},
		{Target: vm.ExternalFunction{Module: "erlang", Function: "raise", Arity: 3}, Implementation: otpRaise},
		{Target: vm.ExternalFunction{Module: "lists", Function: "member", Arity: 2}, Implementation: otpMember},
		{Target: vm.ExternalFunction{Module: "lists", Function: "keyfind", Arity: 3}, Implementation: otpKeyFind},
		{Target: vm.ExternalFunction{Module: "lists", Function: "keymember", Arity: 3}, Implementation: otpKeyMember},
		{Target: vm.ExternalFunction{Module: "lists", Function: "keysearch", Arity: 3}, Implementation: otpKeySearch},
	}
}
