package erts

import (
	"testing"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

// assayxport:law gotp.erts.otp-key-bif-laws
func TestPinnedOTPKeyBIFsUseLooseNumericComparison(t *testing.T) {
	module := pinnedListsModule(t)
	registry := otpRegistryForInvocation(t)
	first := term.Tuple(term.Float(1), term.MustAtom("float"))
	second := term.Tuple(term.Integer(2), term.MustAtom("integer"))
	tuples := term.List(first, second)
	match module.Invoke(
		"keyfind",
		[]term.Term{term.Integer(1), term.Integer(1), tuples},
		clock.Real{},
		registry,
	) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(process):
		value := completedInvocation(t, process)
		if !term.Equal(value, first) {
			t.Fatalf("lists:keyfind/3 = %v", value)
		}
	}
	match module.Invoke(
		"keymember",
		[]term.Term{term.Integer(3), term.Integer(1), tuples},
		clock.Real{},
		registry,
	) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(process):
		value := completedInvocation(t, process)
		if !term.Equal(value, term.MustAtom("false")) {
			t.Fatalf("lists:keymember/3 = %v", value)
		}
	}
	match module.Invoke(
		"keysearch",
		[]term.Term{term.Integer(2), term.Integer(1), tuples},
		clock.Real{},
		registry,
	) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(process):
		value := completedInvocation(t, process)
		want := term.Tuple(term.MustAtom("value"), second)
		if !term.Equal(value, want) {
			t.Fatalf("lists:keysearch/3 = %v", value)
		}
	}
}

func TestOTPKeyBIFRejectsInvalidPosition(t *testing.T) {
	outcome := otpKeyFind([]term.Term{
		term.MustAtom("key"),
		term.Integer(0),
		term.List(term.Tuple(term.MustAtom("key"))),
	})
	var checked vm.ExternalCallOutcome = outcome
	match checked {
	case vm.ExternalCallRejected(detail):
		if detail != "badarg" {
			t.Fatalf("invalid position rejection = %q", detail)
		}
	case vm.ExternalCallUnbound, vm.ExternalCallReturned(_), vm.ExternalCallRaised(_, _):
		t.Fatalf("invalid position outcome = %T", checked)
	}
}
