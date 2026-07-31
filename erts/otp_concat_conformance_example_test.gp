package erts

import (
	"testing"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.pinned-otp-closure-laws
func TestPinnedOTPConcatExecutesLocalClosure(t *testing.T) {
	module := pinnedListsModule(t)
	arguments := term.List(term.MustAtom("a"), term.Integer(12), term.Float(1.5))
	match module.Invoke("concat", []term.Term{arguments}, clock.Real{}, otpRegistryForInvocation(t)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(process):
		value := completedInvocation(t, process)
		want := term.List(
			term.Integer(97),
			term.Integer(49),
			term.Integer(50),
			term.Integer(49),
			term.Integer(46),
			term.Integer(53),
		)
		if !term.Equal(value, want) {
			t.Fatalf("lists:concat/1 = %v", value)
		}
	}
}
