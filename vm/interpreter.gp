package vm

import (
	"fmt"
	"math/big"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
)

type MachineConfig struct {
	XRegisters int
	StepLimit  int
}

type RunResult struct {
	Value beam.Operand
	Steps int
}

type MachineMutation enum {
	MachineMutated()
}

type Machine struct {
	program   []beam.Instruction
	labels    map[uint64]int
	x         []option.Option[beam.Operand]
	y         []option.Option[beam.Operand]
	returnPCs []int
	pc        int
	steps     int
	stepLimit int
}

func NewMachine(
	program []beam.Instruction,
	config MachineConfig,
) result.Result[*Machine, Failure] {
	if config.XRegisters <= 0 {
		config.XRegisters = 256
	}
	if config.StepLimit <= 0 {
		config.StepLimit = 1_000_000
	}
	labels := make(map[uint64]int)
	for index, instruction := range program {
		if instruction.Opcode.Name != "label" {
			continue
		}
		if len(instruction.Operands) != 1 {
			return result.Err[*Machine, Failure](InvalidProgram(fmt.Sprintf(
				"label at instruction %d has %d operands",
				index,
				len(instruction.Operands),
			)))
		}
		match labelIndex(instruction.Operands[0]) {
		case option.None:
			return result.Err[*Machine, Failure](InvalidProgram(fmt.Sprintf(
				"label at instruction %d is not a nonnegative uint64",
				index,
			)))
		case option.Some(label):
			_, duplicate := labels[label]
			if duplicate {
				return result.Err[*Machine, Failure](InvalidProgram(fmt.Sprintf(
					"duplicate label %d",
					label,
				)))
			}
			labels[label] = index
		}
	}
	registers := make([]option.Option[beam.Operand], config.XRegisters)
	for index := range registers {
		registers[index] = option.None[beam.Operand]
	}
	return result.Ok[*Machine, Failure](&Machine{
		program: program, labels: labels, x: registers, stepLimit: config.StepLimit,
	})
}

func (machine *Machine) SetX(
	index int,
	value beam.Operand,
) result.Result[MachineMutation, Failure] {
	if index < 0 || index >= len(machine.x) {
		return result.Err[MachineMutation, Failure](RegisterOutOfRange("x", index))
	}
	machine.x[index] = option.Some[beam.Operand](value)
	return result.Ok[MachineMutation, Failure](MachineMutated())
}

func (machine *Machine) X(index int) result.Result[beam.Operand, Failure] {
	return machine.register(machine.x, "x", index)
}

func (machine *Machine) Run(entryLabel uint64) result.Result[RunResult, Failure] {
	entry, present := machine.labels[entryLabel]
	match option.Of(entry, present) {
	case option.None:
		return result.Err[RunResult, Failure](MissingLabel(entryLabel))
	case option.Some(position):
		machine.pc = position + 1
	}
	machine.steps = 0
	machine.returnPCs = machine.returnPCs[:0]

	for {
		if machine.steps >= machine.stepLimit {
			return result.Err[RunResult, Failure](StepLimitExceeded(machine.stepLimit))
		}
		if machine.pc < 0 || machine.pc >= len(machine.program) {
			return result.Err[RunResult, Failure](InvalidProgram(fmt.Sprintf(
				"program counter %d is out of range",
				machine.pc,
			)))
		}
		instruction := machine.program[machine.pc]
		machine.steps++
		next := machine.pc + 1

		switch instruction.Opcode.Name {
		case "label", "func_info":
			machine.pc = next
		case "move":
			match machine.move(instruction) {
			case result.Err(failure):
				return result.Err[RunResult, Failure](failure)
			case result.Ok(MachineMutated):
				machine.pc = next
			}
		case "jump":
			match machine.instructionLabel(instruction, 0) {
			case result.Ok(target):
				machine.pc = target
			case result.Err(failure):
				return result.Err[RunResult, Failure](failure)
			}
		case "call":
			match machine.instructionLabel(instruction, 1) {
			case result.Ok(target):
				machine.returnPCs = append(machine.returnPCs, next)
				machine.pc = target
			case result.Err(failure):
				return result.Err[RunResult, Failure](failure)
			}
		case "call_only":
			match machine.instructionLabel(instruction, 1) {
			case result.Ok(target):
				machine.pc = target
			case result.Err(failure):
				return result.Err[RunResult, Failure](failure)
			}
		case "call_last":
			match machine.deallocate(instruction, 2) {
			case result.Err(failure):
				return result.Err[RunResult, Failure](failure)
			case result.Ok(MachineMutated):
			}
			match machine.instructionLabel(instruction, 1) {
			case result.Ok(target):
				machine.pc = target
			case result.Err(failure):
				return result.Err[RunResult, Failure](failure)
			}
		case "allocate", "allocate_zero":
			match machine.allocate(instruction, 0) {
			case result.Ok(MachineMutated):
				machine.pc = next
			case result.Err(failure):
				return result.Err[RunResult, Failure](failure)
			}
		case "deallocate":
			match machine.deallocate(instruction, 0) {
			case result.Ok(MachineMutated):
				machine.pc = next
			case result.Err(failure):
				return result.Err[RunResult, Failure](failure)
			}
		case "return":
			if len(machine.returnPCs) == 0 {
				return machine.finish()
			}
			last := len(machine.returnPCs) - 1
			machine.pc = machine.returnPCs[last]
			machine.returnPCs = machine.returnPCs[:last]
		case "int_code_end":
			return machine.finish()
		default:
			return result.Err[RunResult, Failure](UnsupportedOpcode(
				instruction.Opcode.Name,
				instruction.Opcode.Arity,
				instruction.Offset,
			))
		}
	}
}

func (machine *Machine) finish() result.Result[RunResult, Failure] {
	match machine.X(0) {
	case result.Ok(value):
		return result.Ok[RunResult, Failure](RunResult{Value: value, Steps: machine.steps})
	case result.Err(failure):
		return result.Err[RunResult, Failure](failure)
	}
}

func (machine *Machine) move(
	instruction beam.Instruction,
) result.Result[MachineMutation, Failure] {
	if len(instruction.Operands) != 2 {
		return result.Err[MachineMutation, Failure](InvalidProgram(fmt.Sprintf(
			"move has %d operands",
			len(instruction.Operands),
		)))
	}
	match machine.resolve(instruction.Operands[0]) {
	case result.Err(failure):
		return result.Err[MachineMutation, Failure](failure)
	case result.Ok(value):
		return machine.assign(instruction.Operands[1], value)
	}
}

func (machine *Machine) resolve(
	operand beam.Operand,
) result.Result[beam.Operand, Failure] {
	match operand {
	case beam.TypedRegisterOperand(register, _):
		return machine.resolve(register)
	case beam.XRegisterOperand(index):
		return machine.readIndexed(machine.x, "x", index)
	case beam.YRegisterOperand(index):
		match machine.yPosition(index) {
		case result.Ok(position):
			return machine.register(machine.y, "y", position)
		case result.Err(failure):
			return result.Err[beam.Operand, Failure](failure)
		}
	case beam.UnsignedOperand(_):
		return result.Ok[beam.Operand, Failure](operand)
	case beam.IntegerOperand(_):
		return result.Ok[beam.Operand, Failure](operand)
	case beam.AtomOperand(_):
		return result.Ok[beam.Operand, Failure](operand)
	case beam.CharacterOperand(_):
		return result.Ok[beam.Operand, Failure](operand)
	case beam.LiteralOperand(_):
		return result.Ok[beam.Operand, Failure](operand)
	case _:
		return result.Err[beam.Operand, Failure](InvalidProgram("operand is not a value"))
	}
}

func (machine *Machine) assign(
	destination beam.Operand,
	value beam.Operand,
) result.Result[MachineMutation, Failure] {
	match destination {
	case beam.TypedRegisterOperand(register, _):
		return machine.assign(register, value)
	case beam.XRegisterOperand(index):
		return machine.writeIndexed(machine.x, "x", index, value)
	case beam.YRegisterOperand(index):
		match machine.yPosition(index) {
		case result.Err(failure):
			return result.Err[MachineMutation, Failure](failure)
		case result.Ok(position):
			machine.y[position] = option.Some[beam.Operand](value)
			return result.Ok[MachineMutation, Failure](MachineMutated())
		}
	case _:
		return result.Err[MachineMutation, Failure](InvalidProgram("move destination is not a register"))
	}
}

func (machine *Machine) readIndexed(
	registers []option.Option[beam.Operand],
	name string,
	index *big.Int,
) result.Result[beam.Operand, Failure] {
	match registerIndex(index) {
	case option.None:
		return result.Err[beam.Operand, Failure](InvalidProgram(name + " register index is not uint64"))
	case option.Some(value):
		if value > uint64(maxInt()) {
			return result.Err[beam.Operand, Failure](RegisterOutOfRange(name, maxInt()))
		}
		return machine.register(registers, name, int(value))
	}
}

func (machine *Machine) writeIndexed(
	registers []option.Option[beam.Operand],
	name string,
	index *big.Int,
	value beam.Operand,
) result.Result[MachineMutation, Failure] {
	match registerIndex(index) {
	case option.None:
		return result.Err[MachineMutation, Failure](InvalidProgram(name + " register index is not uint64"))
	case option.Some(position):
		if position >= uint64(len(registers)) {
			return result.Err[MachineMutation, Failure](RegisterOutOfRange(name, int(position)))
		}
		registers[int(position)] = option.Some[beam.Operand](value)
		return result.Ok[MachineMutation, Failure](MachineMutated())
	}
}

func (machine *Machine) register(
	registers []option.Option[beam.Operand],
	name string,
	index int,
) result.Result[beam.Operand, Failure] {
	if index < 0 || index >= len(registers) {
		return result.Err[beam.Operand, Failure](RegisterOutOfRange(name, index))
	}
	match registers[index] {
	case option.Some(value):
		return result.Ok[beam.Operand, Failure](value)
	case option.None:
		return result.Err[beam.Operand, Failure](UninitializedRegister(name, index))
	}
}

func (machine *Machine) yPosition(index *big.Int) result.Result[int, Failure] {
	match registerIndex(index) {
	case option.None:
		return result.Err[int, Failure](InvalidProgram("y register index is not uint64"))
	case option.Some(value):
		if value >= uint64(len(machine.y)) {
			return result.Err[int, Failure](RegisterOutOfRange("y", int(value)))
		}
		return result.Ok[int, Failure](len(machine.y) - 1 - int(value))
	}
}

func (machine *Machine) instructionLabel(
	instruction beam.Instruction,
	operandIndex int,
) result.Result[int, Failure] {
	if operandIndex < 0 || operandIndex >= len(instruction.Operands) {
		return result.Err[int, Failure](InvalidProgram(fmt.Sprintf(
			"%s is missing label operand %d",
			instruction.Opcode.Name,
			operandIndex,
		)))
	}
	match labelIndex(instruction.Operands[operandIndex]) {
	case option.None:
		return result.Err[int, Failure](InvalidProgram(fmt.Sprintf(
			"%s operand %d is not a label",
			instruction.Opcode.Name,
			operandIndex,
		)))
	case option.Some(label):
		target, present := machine.labels[label]
		match option.Of(target, present) {
		case option.Some(position):
			return result.Ok[int, Failure](position + 1)
		case option.None:
			return result.Err[int, Failure](MissingLabel(label))
		}
	}
}

func (machine *Machine) allocate(
	instruction beam.Instruction,
	operandIndex int,
) result.Result[MachineMutation, Failure] {
	match allocationCount(instruction, operandIndex) {
	case result.Err(failure):
		return result.Err[MachineMutation, Failure](failure)
	case result.Ok(count):
		for index := 0; index < count; index++ {
			machine.y = append(machine.y, option.None[beam.Operand])
		}
		return result.Ok[MachineMutation, Failure](MachineMutated())
	}
}

func (machine *Machine) deallocate(
	instruction beam.Instruction,
	operandIndex int,
) result.Result[MachineMutation, Failure] {
	match allocationCount(instruction, operandIndex) {
	case result.Err(failure):
		return result.Err[MachineMutation, Failure](failure)
	case result.Ok(count):
		if count > len(machine.y) {
			return result.Err[MachineMutation, Failure](InvalidProgram("invalid deallocation count"))
		}
		machine.y = machine.y[:len(machine.y)-count]
		return result.Ok[MachineMutation, Failure](MachineMutated())
	}
}

func allocationCount(
	instruction beam.Instruction,
	operandIndex int,
) result.Result[int, Failure] {
	if operandIndex < 0 || operandIndex >= len(instruction.Operands) {
		return result.Err[int, Failure](InvalidProgram(fmt.Sprintf(
			"%s is missing allocation operand",
			instruction.Opcode.Name,
		)))
	}
	match instruction.Operands[operandIndex] {
	case beam.UnsignedOperand(value):
		match registerIndex(value) {
		case option.Some(count):
			if count <= 1_000_000 {
				return result.Ok[int, Failure](int(count))
			}
		case option.None:
		}
	case _:
	}
	return result.Err[int, Failure](InvalidProgram("invalid allocation count"))
}

func labelIndex(operand beam.Operand) option.Option[uint64] {
	match operand {
	case beam.LabelOperand(index):
		return registerIndex(index)
	case _:
		return option.None[uint64]
	}
}

func registerIndex(index *big.Int) option.Option[uint64] {
	if index.Sign() < 0 || !index.IsUint64() {
		return option.None[uint64]
	}
	return option.Some[uint64](index.Uint64())
}

func maxInt() int {
	return int(^uint(0) >> 1)
}
