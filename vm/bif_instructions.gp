package vm

import (
	"fmt"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

type bifInstructionShape struct {
	failIndex   int
	importIndex int
	argumentAt  int
	arguments   int
	destination int
	operands    int
}

func bifShape(name string) option.Option[bifInstructionShape] {
	switch name {
	case "bif0":
		return option.Some(bifInstructionShape{failIndex: 0, importIndex: 1, argumentAt: 2, arguments: 0, destination: 2, operands: 3})
	case "bif1":
		return option.Some(bifInstructionShape{failIndex: 0, importIndex: 1, argumentAt: 2, arguments: 1, destination: 3, operands: 4})
	case "bif2":
		return option.Some(bifInstructionShape{failIndex: 0, importIndex: 1, argumentAt: 2, arguments: 2, destination: 4, operands: 5})
	case "gc_bif1":
		return option.Some(bifInstructionShape{failIndex: 0, importIndex: 2, argumentAt: 3, arguments: 1, destination: 4, operands: 5})
	case "gc_bif2":
		return option.Some(bifInstructionShape{failIndex: 0, importIndex: 2, argumentAt: 3, arguments: 2, destination: 5, operands: 6})
	case "gc_bif3":
		return option.Some(bifInstructionShape{failIndex: 0, importIndex: 2, argumentAt: 3, arguments: 3, destination: 6, operands: 7})
	default:
		return option.None[bifInstructionShape]()
	}
}

// assayxport:unit gotp.vm.bif-instructions
func executeBIFInstruction(
	machine *Machine,
	instruction beam.Instruction,
	host HostCapabilities,
) result.Result[instructionOutcome, Failure] {
	var shape bifInstructionShape
	match bifShape(instruction.Opcode.Name) {
	case option.None:
		return result.Err[instructionOutcome, Failure](UnsupportedOpcode(
			instruction.Opcode.Name,
			instruction.Opcode.Arity,
			instruction.Offset,
		))
	case option.Some(found):
		shape = found
	}
	if instruction.Opcode.Name == "bif0" && len(instruction.Operands) == 2 {
		shape = bifInstructionShape{failIndex: -1, importIndex: 0, argumentAt: 1, arguments: 0, destination: 1, operands: 2}
	}
	if len(instruction.Operands) != shape.operands {
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
			"%s has %d operands",
			instruction.Opcode.Name,
			len(instruction.Operands),
		)))
	}
	if instruction.Opcode.Name == "gc_bif1" || instruction.Opcode.Name == "gc_bif2" || instruction.Opcode.Name == "gc_bif3" {
		match beam.Uint64(instruction.Operands[1]) {
		case option.None:
			return result.Err[instructionOutcome, Failure](InvalidProgram("GC BIF live count is not uint64"))
		case option.Some(live):
			if live > uint64(machine.x.Len()) {
				return result.Err[instructionOutcome, Failure](InvalidProgram("GC BIF live count exceeds X registers"))
			}
		}
	}
	var imported uint64
	match beam.Uint64(instruction.Operands[shape.importIndex]) {
	case option.None:
		return result.Err[instructionOutcome, Failure](InvalidProgram("BIF destination is not an import index"))
	case option.Some(index):
		imported = index
	}
	var target ExternalFunction
	match machine.externalFunction(imported) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(found):
		target = found
	}
	if int(target.Arity) != shape.arguments {
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
			"BIF arity %d differs from import %s:%s/%d",
			shape.arguments,
			target.Module,
			target.Function,
			target.Arity,
		)))
	}
	arguments := make([]term.Term, shape.arguments)
	for index := range arguments {
		match machine.resolve(instruction.Operands[shape.argumentAt + index]) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(value):
			arguments[index] = term.Clone(value)
		}
	}
	var capability ExternalCallCapability = host.ExternalCalls
	match capability {
	case ExternalCallsUnavailable:
		return result.Err[instructionOutcome, Failure](InvalidProgram("BIF requires an explicit host capability"))
	case ExternalCallsAllowed:
		if host.externalCall == nil {
			return result.Err[instructionOutcome, Failure](InvalidConfiguration("BIF capability effect is nil"))
		}
	}
	var called ExternalCallOutcome = host.externalCall(target, arguments)
	match called {
	case ExternalCallUnbound:
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
			"unbound BIF %s:%s/%d",
			target.Module,
			target.Function,
			target.Arity,
		)))
	case ExternalCallRaised(class, reason):
		return result.Err[instructionOutcome, Failure](RaisedException(term.Clone(class), term.Clone(reason)))
	case ExternalCallRejected(detail):
		if shape.failIndex < 0 { return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf("BIF %s:%s/%d rejected: %s", target.Module, target.Function, target.Arity, detail))) }
		return machine.branchBIFailure(instruction, shape.failIndex, target, detail)
	case ExternalCallReturned(value):
		match machine.assign(instruction.Operands[shape.destination], value) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(MachineMutated):
			machine.pc++
			return result.Ok[instructionOutcome, Failure](InstructionContinues())
		}
	}
}

func (machine *Machine) branchBIFailure(
	instruction beam.Instruction,
	failIndex int,
	target ExternalFunction,
	detail string,
) result.Result[instructionOutcome, Failure] {
	match beam.Uint64(instruction.Operands[failIndex]) {
	case option.None:
		return result.Err[instructionOutcome, Failure](InvalidProgram("BIF failure target is not a label"))
	case option.Some(label):
		if label == 0 {
			return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
				"BIF %s:%s/%d failed: %s",
				target.Module,
				target.Function,
				target.Arity,
				detail,
			)))
		}
	}
	match machine.instructionLabel(instruction, failIndex) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(targetPC):
		machine.pc = targetPC
		return result.Ok[instructionOutcome, Failure](InstructionContinues())
	}
}
