package erts

import (
	"math/big"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

func otpReturned(outcome vm.ExternalCallOutcome) option.Option[term.Term] {
	var checked vm.ExternalCallOutcome = outcome
	match checked {
	case vm.ExternalCallReturned(value):
		return option.Some(value)
	case vm.ExternalCallUnbound, vm.ExternalCallRaised(_, _), vm.ExternalCallRejected(_):
		return option.None[term.Term]()
	}
}

// assayxport:law gotp.erts.otp-pure-bif-laws
func TestOTPIntegerArithmeticRoundTripProperty(t *testing.T) {
	property := func(left int64, right int64) bool {
		added := otpArithmetic([]term.Term{term.Integer(left), term.Integer(right)}, otpAdd())
		match otpReturned(added) {
		case option.None:
			return false
		case option.Some(sum):
			subtracted := otpArithmetic([]term.Term{sum, term.Integer(right)}, otpSubtract())
			match otpReturned(subtracted) {
			case option.None:
				return false
			case option.Some(value):
				match term.IntegerValue(value) {
				case option.None:
					return false
				case option.Some(integer):
					return integer.Cmp(big.NewInt(left)) == 0
				}
			}
		}
	}
	match result.Of(struct{}{}, quick.Check(property, nil)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
}

func termsFromBytes(values []byte) []term.Term {
	terms := make([]term.Term, len(values))
	for index, value := range values {
		terms[index] = term.Integer(int64(value))
	}
	return terms
}

func TestOTPListAppendAssociativityProperty(t *testing.T) {
	property := func(first []byte, second []byte, third []byte) bool {
		firstList := term.List(termsFromBytes(first)...)
		secondList := term.List(termsFromBytes(second)...)
		thirdList := term.List(termsFromBytes(third)...)
		var firstSecond term.Term
		match otpReturned(otpListAppend([]term.Term{firstList, secondList})) {
		case option.None:
			return false
		case option.Some(value):
			firstSecond = value
		}
		var secondThird term.Term
		match otpReturned(otpListAppend([]term.Term{secondList, thirdList})) {
		case option.None:
			return false
		case option.Some(value):
			secondThird = value
		}
		var left term.Term
		match otpReturned(otpListAppend([]term.Term{firstSecond, thirdList})) {
		case option.None:
			return false
		case option.Some(value):
			left = value
		}
		match otpReturned(otpListAppend([]term.Term{firstList, secondThird})) {
		case option.None:
			return false
		case option.Some(right):
			return term.Equal(left, right)
		}
	}
	match result.Of(struct{}{}, quick.Check(property, nil)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
}
