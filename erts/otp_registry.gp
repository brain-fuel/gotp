package erts

import (
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

func reverseOnto(arguments []term.Term) vm.ExternalCallOutcome {
	match otpProperElements(arguments[0]) {
	case option.None:
		return vm.ExternalCallRejected("badarg")
	case option.Some(elements):
		if len(elements) == 0 {
			return vm.ExternalCallReturned(term.Clone(arguments[1]))
		}
		reversed := make([]term.Term, len(elements))
		for index, value := range elements {
			reversed[len(elements) - index - 1] = value
		}
		match otpProperElements(arguments[1]) {
		case option.None:
			return vm.ExternalCallReturned(term.ImproperList(reversed, arguments[1]))
		case option.Some(tail):
			joined := make([]term.Term, 0, len(reversed) + len(tail))
			joined = append(joined, reversed...)
			joined = append(joined, tail...)
			return vm.ExternalCallReturned(term.List(joined...))
		}
	}
}

// assayxport:unit gotp.erts.otp-call-registry
func NewOTPCallRegistry() result.Result[*CallRegistry, CallRegistryFailure] {
	bindings := otpPureBindings()
	bindings = append(bindings, CallBinding{
		Target: vm.ExternalFunction{Module: "lists", Function: "reverse", Arity: 2},
		Implementation: reverseOnto,
	})
	return NewCallRegistry(bindings)
}
