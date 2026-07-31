package vm

import (
	"fmt"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

func (machine *Machine) externalFunction(index uint64) result.Result[ExternalFunction, Failure] {
	target, present := machine.imports[index]
	match option.Of(target, present) {
	case option.None:
		return result.Err[ExternalFunction, Failure](MissingConstant("import", index))
	case option.Some(found):
		return result.Ok[ExternalFunction, Failure](found)
	}
}

type linkedCallTarget struct {
	image *machineImage
	pc    int
}

func (machine *Machine) linkedFunction(target ExternalFunction) option.Option[linkedCallTarget] {
	image, modulePresent := machine.modules[target.Module]
	if !modulePresent {
		return option.None[linkedCallTarget]()
	}
	label, exportPresent := image.exports[target]
	if !exportPresent {
		return option.None[linkedCallTarget]()
	}
	position, labelPresent := image.labels[label]
	if !labelPresent {
		return option.None[linkedCallTarget]()
	}
	return option.Some(linkedCallTarget{image: image, pc: position + 1})
}

func executeExternalCall(
	machine *Machine,
	instruction beam.Instruction,
	host HostCapabilities,
	tail bool,
	deallocate bool,
) result.Result[instructionOutcome, Failure] {
	wantOperands := 2
	if deallocate {
		wantOperands = 3
	}
	if len(instruction.Operands) != wantOperands {
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
			"%s has %d operands",
			instruction.Opcode.Name,
			len(instruction.Operands),
		)))
	}
	var arity uint64
	match beam.Uint64(instruction.Operands[0]) {
	case option.None:
		return result.Err[instructionOutcome, Failure](InvalidProgram("external call arity is not uint64"))
	case option.Some(value):
		arity = value
	}
	if arity > uint64(len(machine.x)) || arity > uint64(^uint32(0)) {
		return result.Err[instructionOutcome, Failure](InvalidProgram("external call arity is out of range"))
	}
	var importIndex uint64
	match beam.Uint64(instruction.Operands[1]) {
	case option.None:
		return result.Err[instructionOutcome, Failure](InvalidProgram("external call destination is not an import index"))
	case option.Some(value):
		importIndex = value
	}
	var target ExternalFunction
	match machine.externalFunction(importIndex) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(found):
		target = found
	}
	if uint64(target.Arity) != arity {
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
			"external call arity %d differs from import %s:%s/%d",
			arity,
			target.Module,
			target.Function,
			target.Arity,
		)))
	}
	if deallocate {
		match machine.deallocate(instruction, 2) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(MachineMutated):
		}
	}
	arguments := make([]term.Term, int(arity))
	for index := range arguments {
		match machine.X(index) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(value):
			arguments[index] = term.Clone(value)
		}
	}
	match machine.linkedFunction(target) {
	case option.Some(destination):
		if !tail {
			machine.pushReturn(machine.pc + 1)
		}
		machine.activate(destination.image)
		machine.pc = destination.pc
		return result.Ok[instructionOutcome, Failure](InstructionContinues())
	case option.None:
	}
	var capability ExternalCallCapability = host.ExternalCalls
	match capability {
	case ExternalCallsUnavailable:
		return result.Err[instructionOutcome, Failure](InvalidProgram("external call requires an explicit host capability"))
	case ExternalCallsAllowed:
		if host.externalCall == nil {
			return result.Err[instructionOutcome, Failure](InvalidConfiguration("external call capability effect is nil"))
		}
	}
	var called ExternalCallOutcome = host.externalCall(target, arguments)
	match called {
	case ExternalCallRejected(detail):
		return result.Err[instructionOutcome, Failure](InvalidProgram(
			fmt.Sprintf("external call %s:%s/%d rejected: %s", target.Module, target.Function, target.Arity, detail),
		))
	case ExternalCallReturned(value):
		match machine.SetX(0, value) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(MachineMutated):
		}
	}
	if !tail {
		machine.pc++
		return result.Ok[instructionOutcome, Failure](InstructionContinues())
	}
	if !machine.returnToCaller() {
		return result.Ok[instructionOutcome, Failure](InstructionHalts())
	}
	return result.Ok[instructionOutcome, Failure](InstructionContinues())
}
