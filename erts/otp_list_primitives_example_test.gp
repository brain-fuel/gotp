package erts

import (
	"testing"

	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

// assayxport:law gotp.erts.otp-list-head-tail-laws
func TestOTPListHeadAndTailPreserveProperAndImproperShape(t *testing.T) {
	proper := term.List(term.MustAtom("head"), term.MustAtom("tail"))
	assertOTPReturned(t, otpListHead([]term.Term{proper}), term.MustAtom("head"))
	assertOTPReturned(t, otpListTail([]term.Term{proper}), term.List(term.MustAtom("tail")))
	improper := term.ImproperList([]term.Term{term.MustAtom("head"), term.MustAtom("middle")}, term.MustAtom("tail"))
	assertOTPReturned(t, otpListTail([]term.Term{improper}), term.ImproperList([]term.Term{term.MustAtom("middle")}, term.MustAtom("tail")))
	assertOTPReturned(t, otpListTail([]term.Term{term.ImproperList([]term.Term{term.MustAtom("head")}, term.MustAtom("tail"))}), term.MustAtom("tail"))
}

func assertOTPReturned(t *testing.T, outcome vm.ExternalCallOutcome, expected term.Term) {
	t.Helper()
	match outcome {
	case vm.ExternalCallReturned(actual): if !term.Equal(actual, expected) { t.Fatalf("value = %v, want %v", actual, expected) }
	case _: t.Fatalf("outcome = %T", outcome)
	}
}
