package erts

import (
	"testing"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

func pinnedRaisedInvocation(t *testing.T, function string, arguments []term.Term) VMProcessRaised {
	module := pinnedListsModule(t)
	var process *VMProcess
	match module.Invoke(function, arguments, clock.Real{}, otpRegistryForInvocation(t)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(value):
		process = value
	}
	runtime := kernel.New(kernel.KernelConfig{})
	match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	runtime.Run(100)
	var state VMProcessState = process.State()
	match state {
	case VMProcessRaised(class, reason, reductions, instructions):
		return VMProcessRaised{Class: class, Reason: reason, TotalReductions: reductions, TotalInstructions: instructions}
	case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessCompleted(_, _, _), VMProcessFailed(_, _, _):
		t.Fatalf("expected raised process, got %T: %v", state, state)
	}
	panic("unreachable")
}

// assayxport:law gotp.erts.pinned-otp-exception-laws
func TestPinnedOTPExceptionsPreserveClassReasonAndProgress(t *testing.T) {
	badarg := pinnedRaisedInvocation(t, "seq", []term.Term{term.Integer(1), term.Integer(3), term.Integer(0)})
	if !term.Equal(badarg.Class, term.MustAtom("error")) || !term.Equal(badarg.Reason, term.MustAtom("badarg")) {
		t.Fatalf("lists:seq/3 raised = %v:%v", badarg.Class, badarg.Reason)
	}
	if badarg.TotalReductions <= 0 || badarg.TotalInstructions <= 0 {
		t.Fatalf("lists:seq/3 progress = %#v", badarg)
	}
	clause := pinnedRaisedInvocation(t, "nth", []term.Term{term.Integer(0), term.List(term.MustAtom("a"))})
	if !term.Equal(clause.Class, term.MustAtom("error")) || !term.Equal(clause.Reason, term.MustAtom("function_clause")) {
		t.Fatalf("lists:nth/2 raised = %v:%v", clause.Class, clause.Reason)
	}
	if clause.TotalReductions <= 0 || clause.TotalInstructions <= 0 {
		t.Fatalf("lists:nth/2 progress = %#v", clause)
	}
}
