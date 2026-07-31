package vm

import (
	"fmt"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

// assayxport:unit gotp.vm.term-order-tests
func executeTermOrderInstruction(
	machine *Machine,
	instruction beam.Instruction,
) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 3 {
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
			"%s has %d operands",
			instruction.Opcode.Name,
			len(instruction.Operands),
		)))
	}
	var left term.Term
	match machine.resolve(instruction.Operands[1]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		left = value
	}
	var right term.Term
	match machine.resolve(instruction.Operands[2]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		right = value
	}
	var order term.Ordering
	match term.Compare(left, right) {
	case result.Err(_):
		return result.Err[instructionOutcome, Failure](InvalidProgram("term comparison contains an invalid or unordered term"))
	case result.Ok(checked):
		order = checked
	}
	passes := false
	var checked term.Ordering = order
	switch instruction.Opcode.Name {
	case "is_lt":
		match checked { case term.TermLess: passes = true; case term.TermEqual, term.TermGreater: }
	case "is_ge":
		match checked { case term.TermLess: case term.TermEqual, term.TermGreater: passes = true }
	default:
		return result.Err[instructionOutcome, Failure](UnsupportedOpcode(instruction.Opcode.Name, instruction.Opcode.Arity, instruction.Offset))
	}
	if passes {
		machine.pc++
		return result.Ok[instructionOutcome, Failure](InstructionContinues())
	}
	match machine.instructionLabel(instruction, 0) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(target):
		machine.pc = target
		return result.Ok[instructionOutcome, Failure](InstructionContinues())
	}
}
