package vm

import (
	"fmt"
	"math/big"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

// assayxport:unit gotp.vm.function-instructions
func executeMakeFun3(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 3 {
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf("make_fun3 has %d operands", len(instruction.Operands))))
	}
	var index uint64
	match beam.Uint64(instruction.Operands[0]) {
	case option.None:
		return result.Err[instructionOutcome, Failure](InvalidProgram("make_fun3 index is not uint64"))
	case option.Some(value):
		index = value
	}
	var template beam.FunctionTemplate
	function, present := machine.functions[index]
	match option.Of(function, present) {
	case option.None:
		return result.Err[instructionOutcome, Failure](MissingConstant("function", index))
	case option.Some(found):
		template = found
	}
	var captures []beam.Operand
	match beam.ListItems(instruction.Operands[2]) {
	case option.None:
		return result.Err[instructionOutcome, Failure](InvalidProgram("make_fun3 environment is not an operand list"))
	case option.Some(items):
		captures = items
	}
	if uint64(len(captures)) != uint64(template.Free) {
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
			"make_fun3 captures %d values; FunT declares %d",
			len(captures),
			template.Free,
		)))
	}
	environment := make([]term.Term, len(captures))
	for captureIndex, operand := range captures {
		match machine.resolve(operand) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(value):
			environment[captureIndex] = term.Clone(value)
		}
	}
	value := term.Function(term.Fun{
		Form: term.LocalClosure(),
		Module: machine.current.name,
		Function: template.Function,
		Arity: template.Arity,
		Label: uint64(template.Label),
		Index: template.Index,
		Unique: template.Unique,
		Environment: environment,
	})
	match machine.assign(instruction.Operands[1], value) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(MachineMutated):
		machine.pc++
		return result.Ok[instructionOutcome, Failure](InstructionContinues())
	}
}

func executeCallFun(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	var arity uint64
	var functionOperand beam.Operand
	switch instruction.Opcode.Name {
	case "call_fun":
		if len(instruction.Operands) != 1 {
			return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf("call_fun has %d operands", len(instruction.Operands))))
		}
		match beam.Uint64(instruction.Operands[0]) {
		case option.None:
			return result.Err[instructionOutcome, Failure](InvalidProgram("call_fun arity is not uint64"))
		case option.Some(value):
			arity = value
		}
		functionOperand = beam.XRegisterOperand{Index: new(big.Int).SetUint64(arity)}
	case "call_fun2":
		if len(instruction.Operands) != 3 {
			return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf("call_fun2 has %d operands", len(instruction.Operands))))
		}
		match beam.Uint64(instruction.Operands[1]) {
		case option.None:
			return result.Err[instructionOutcome, Failure](InvalidProgram("call_fun2 arity is not uint64"))
		case option.Some(value):
			arity = value
		}
		functionOperand = instruction.Operands[2]
	default:
		return result.Err[instructionOutcome, Failure](UnsupportedOpcode(instruction.Opcode.Name, instruction.Opcode.Arity, instruction.Offset))
	}
	var function term.Fun
	match machine.resolve(functionOperand) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		match value.FunValue() {
		case option.None:
			return result.Err[instructionOutcome, Failure](InvalidProgram("call_fun target is not a function"))
		case option.Some(found):
			function = found
		}
	}
	if arity != uint64(function.Arity) {
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
			"call_fun arity %d differs from function arity %d",
			arity,
			function.Arity,
		)))
	}
	image, present := machine.modules[function.Module]
	if !present {
		return result.Err[instructionOutcome, Failure](InvalidProgram("function module is not linked: " + function.Module))
	}
	position, present := image.labels[function.Label]
	if !present {
		return result.Err[instructionOutcome, Failure](MissingLabel(function.Label))
	}
	if arity + uint64(len(function.Environment)) > uint64(len(machine.x)) {
		return result.Err[instructionOutcome, Failure](RegisterOutOfRange("x", int(arity) + len(function.Environment) - 1))
	}
	for index, captured := range function.Environment {
		machine.x[int(arity) + index] = option.Some[term.Term](term.Clone(captured))
	}
	machine.pushReturn(machine.pc + 1)
	machine.activate(image)
	machine.pc = position + 1
	return result.Ok[instructionOutcome, Failure](InstructionContinues())
}

func executeFunctionTest(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	wantOperands := 2
	if instruction.Opcode.Name == "is_function2" { wantOperands = 3 }
	if len(instruction.Operands) != wantOperands {
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf("%s has %d operands", instruction.Opcode.Name, len(instruction.Operands))))
	}
	valid := false
	match machine.resolve(instruction.Operands[1]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		match value.FunValue() {
		case option.None:
		case option.Some(function):
			if instruction.Opcode.Name == "is_function" {
				valid = true
			} else {
				match machine.resolve(instruction.Operands[2]) {
				case result.Err(failure):
					return result.Err[instructionOutcome, Failure](failure)
				case result.Ok(arityTerm):
					match term.IntegerValue(arityTerm) {
					case option.None:
					case option.Some(arity):
						valid = arity.Sign() >= 0 && arity.IsUint64() && arity.Uint64() == uint64(function.Arity)
					}
				}
			}
		}
	}
	if valid {
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
