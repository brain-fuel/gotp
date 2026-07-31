package erts

import (
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

// assayxport:unit gotp.erts.otp-context-bifs
func (process *VMProcess) contextualCall(
	context *kernel.Context,
	target vm.ExternalFunction,
	arguments []term.Term,
) vm.ExternalCallOutcome {
	if target.Module == "erlang" && target.Function == "alias" && target.Arity == 0 {
		match context.Alias() {
		case result.Err(failure):
			return vm.ExternalCallRejected(failure.Error())
		case result.Ok(reference):
			return vm.ExternalCallReturned(term.ReferenceValue(reference))
		}
	}
	if target.Module == "erlang" && target.Function == "unalias" && target.Arity == 1 {
		match term.TermReferenceValue(arguments[0]) {
		case option.None:
			return vm.ExternalCallRaised(term.MustAtom("error"), term.MustAtom("badarg"))
		case option.Some(reference):
			context.Unalias(reference)
			return vm.ExternalCallReturned(term.MustAtom("true"))
		}
	}
	return process.callRegistry.Call(target, arguments)
}
