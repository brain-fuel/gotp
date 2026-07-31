package erts

import (
	"fmt"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

type ExternalImplementation func(Arguments []term.Term) vm.ExternalCallOutcome

type CallBinding struct {
	Target         vm.ExternalFunction
	Implementation ExternalImplementation
}

type CallRegistryFailure enum {
	InvalidExternalFunction(Target vm.ExternalFunction, Detail string)
	DuplicateExternalFunction(Target vm.ExternalFunction)
	NilExternalImplementation(Target vm.ExternalFunction)
}

func (failure CallRegistryFailure) Error() string {
	match failure {
	case InvalidExternalFunction(target, detail):
		return fmt.Sprintf("gotp/erts: invalid external function %s:%s/%d: %s", target.Module, target.Function, target.Arity, detail)
	case DuplicateExternalFunction(target):
		return fmt.Sprintf("gotp/erts: duplicate external function %s:%s/%d", target.Module, target.Function, target.Arity)
	case NilExternalImplementation(target):
		return fmt.Sprintf("gotp/erts: nil external function %s:%s/%d", target.Module, target.Function, target.Arity)
	}
}

type CallRegistry struct {
	implementations map[vm.ExternalFunction]ExternalImplementation
}

// assayxport:unit gotp.erts.call-registry
func NewCallRegistry(bindings []CallBinding) result.Result[*CallRegistry, CallRegistryFailure] {
	implementations := make(map[vm.ExternalFunction]ExternalImplementation, len(bindings))
	for _, binding := range bindings {
		target := binding.Target
		if target.Module == "" || target.Function == "" {
			return result.Err[*CallRegistry, CallRegistryFailure](InvalidExternalFunction(target, "module and function are required"))
		}
		match term.Atom(target.Module) {
		case result.Err(failure):
			return result.Err[*CallRegistry, CallRegistryFailure](InvalidExternalFunction(target, failure.Error()))
		case result.Ok(_):
		}
		match term.Atom(target.Function) {
		case result.Err(failure):
			return result.Err[*CallRegistry, CallRegistryFailure](InvalidExternalFunction(target, failure.Error()))
		case result.Ok(_):
		}
		if binding.Implementation == nil {
			return result.Err[*CallRegistry, CallRegistryFailure](NilExternalImplementation(target))
		}
		if _, duplicate := implementations[target]; duplicate {
			return result.Err[*CallRegistry, CallRegistryFailure](DuplicateExternalFunction(target))
		}
		implementations[target] = binding.Implementation
	}
	return result.Ok[*CallRegistry, CallRegistryFailure](&CallRegistry{implementations: implementations})
}

func (registry *CallRegistry) Call(
	target vm.ExternalFunction,
	arguments []term.Term,
) vm.ExternalCallOutcome {
	if registry == nil {
		return vm.ExternalCallRejected("call registry is nil")
	}
	implementation, present := registry.implementations[target]
	match option.Of(implementation, present) {
	case option.None:
		return vm.ExternalCallRejected(fmt.Sprintf(
			"unbound external function %s:%s/%d",
			target.Module,
			target.Function,
			target.Arity,
		))
	case option.Some(call):
		if len(arguments) != int(target.Arity) {
			return vm.ExternalCallRejected(fmt.Sprintf(
				"argument count %d differs from arity %d",
				len(arguments),
				target.Arity,
			))
		}
		cloned := make([]term.Term, len(arguments))
		for index, argument := range arguments {
			cloned[index] = term.Clone(argument)
		}
		return call(cloned)
	}
}
