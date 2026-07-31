package vm

import (
	"fmt"
	"math"
	"math/big"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

// assayxport:unit gotp.vm.core-term-instructions
func executeCoreTermInstruction(
	machine *Machine,
	instruction beam.Instruction,
) result.Result[instructionOutcome, Failure] {
	switch instruction.Opcode.Name {
	case "line":
		machine.pc++
	case "test_heap":
		// Runtime terms are immutable Go values; ProcessHeap-backed terms will
		// replace this proof obligation when heap residency reaches the VM.
		machine.pc++
	case "allocate_heap":
		match machine.allocate(instruction, 0) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(MachineMutated):
			machine.pc++
		}
	case "trim":
		match machine.deallocate(instruction, 0) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(MachineMutated):
			machine.pc++
		}
	case "init_yregs":
		return initializeYRegisters(machine, instruction)
	case "swap":
		return swapRegisters(machine, instruction)
	case "get_list":
		return getList(machine, instruction, false)
	case "get_hd":
		return getList(machine, instruction, true)
	case "get_tl":
		return getListTail(machine, instruction)
	case "put_list":
		return putList(machine, instruction)
	case "get_tuple_element":
		return getTupleElement(machine, instruction)
	case "put_tuple2":
		return putTuple(machine, instruction)
	case "select_val":
		return selectValue(machine, instruction)
	case "select_tuple_arity":
		return selectTupleArity(machine, instruction)
	case "test_arity":
		return testArity(machine, instruction)
	case "is_tagged_tuple":
		return testTaggedTuple(machine, instruction)
	case "is_atom", "is_binary", "is_bitstr", "is_boolean", "is_float", "is_integer",
		"is_list", "is_map", "is_nil", "is_nonempty_list", "is_number", "is_pid",
		"is_port", "is_reference", "is_tuple":
		return testTermKind(machine, instruction)
	case "is_eq", "is_eq_exact", "is_ne", "is_ne_exact":
		return testEquality(machine, instruction)
	default:
		return result.Err[instructionOutcome, Failure](UnsupportedOpcode(
			instruction.Opcode.Name,
			instruction.Opcode.Arity,
			instruction.Offset,
		))
	}
	return result.Ok[instructionOutcome, Failure](InstructionContinues())
}

func testTermKind(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 2 {
		return malformedCoreInstruction(instruction)
	}
	match machine.resolve(instruction.Operands[1]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		matched := false
		var kind term.Kind = term.TermKind(value)
		match kind {
		case term.InvalidKind:
		case term.IntegerKind:
			matched = instruction.Opcode.Name == "is_integer" || instruction.Opcode.Name == "is_number"
		case term.FloatKind:
			matched = instruction.Opcode.Name == "is_float" || instruction.Opcode.Name == "is_number"
		case term.AtomKind:
			matched = instruction.Opcode.Name == "is_atom" ||
				(instruction.Opcode.Name == "is_boolean" && isBooleanAtom(value))
		case term.BinaryKind:
			matched = instruction.Opcode.Name == "is_binary" || instruction.Opcode.Name == "is_bitstr"
		case term.TupleKind:
			matched = instruction.Opcode.Name == "is_tuple"
		case term.ListKind:
			matched = listKindMatches(instruction.Opcode.Name, value)
		case term.MapKind:
			matched = instruction.Opcode.Name == "is_map"
		case term.PIDKind:
			matched = instruction.Opcode.Name == "is_pid"
		case term.ReferenceKind:
			matched = instruction.Opcode.Name == "is_reference"
		case term.PortKind:
			matched = instruction.Opcode.Name == "is_port"
		}
		return branchOnTest(machine, instruction.Operands[0], matched)
	}
}

func listKindMatches(name string, value term.Term) bool {
	match value {
	case term.ProperListTerm(elements):
		if name == "is_nil" {
			return len(elements) == 0
		}
		if name == "is_nonempty_list" {
			return len(elements) > 0
		}
		return name == "is_list"
	case term.ImproperListTerm(elements, _):
		return (name == "is_list" || name == "is_nonempty_list") && len(elements) > 0
	case _:
		return false
	}
}

func isBooleanAtom(value term.Term) bool {
	match term.AtomName(value) {
	case option.None:
		return false
	case option.Some(name):
		return name == "true" || name == "false"
	}
}

func testArity(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 3 {
		return malformedCoreInstruction(instruction)
	}
	var wanted uint64
	match beam.Uint64(instruction.Operands[2]) {
	case option.None:
		return result.Err[instructionOutcome, Failure](InvalidProgram("test_arity arity is not uint64"))
	case option.Some(value):
		wanted = value
	}
	match machine.resolve(instruction.Operands[1]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		matched := false
		match value {
		case term.TupleTerm(elements):
			matched = uint64(len(elements)) == wanted
		case _:
		}
		return branchOnTest(machine, instruction.Operands[0], matched)
	}
}

func testTaggedTuple(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 4 {
		return malformedCoreInstruction(instruction)
	}
	var wanted uint64
	match beam.Uint64(instruction.Operands[2]) {
	case option.None:
		return result.Err[instructionOutcome, Failure](InvalidProgram("is_tagged_tuple arity is not uint64"))
	case option.Some(value):
		wanted = value
	}
	match machine.resolve(instruction.Operands[1]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		match machine.resolve(instruction.Operands[3]) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(tag):
			matched := false
			match value {
			case term.TupleTerm(elements):
				matched = uint64(len(elements)) == wanted && len(elements) > 0 && term.Equal(elements[0], tag)
			case _:
			}
			return branchOnTest(machine, instruction.Operands[0], matched)
		}
	}
}

func testEquality(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 3 {
		return malformedCoreInstruction(instruction)
	}
	match machine.resolve(instruction.Operands[1]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(left):
		match machine.resolve(instruction.Operands[2]) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(right):
			equal := term.Equal(left, right)
			if instruction.Opcode.Name == "is_eq" || instruction.Opcode.Name == "is_ne" {
				equal = numericOrExactEqual(left, right)
			}
			if instruction.Opcode.Name == "is_ne" || instruction.Opcode.Name == "is_ne_exact" {
				equal = !equal
			}
			return branchOnTest(machine, instruction.Operands[0], equal)
		}
	}
}

func numericOrExactEqual(left term.Term, right term.Term) bool {
	if term.Equal(left, right) {
		return true
	}
	match term.IntegerValue(left) {
	case option.Some(integer):
		match term.FloatValue(right) {
		case option.Some(floating):
			return integerFloatEqual(integer, floating)
		case option.None:
		}
	case option.None:
	}
	match term.FloatValue(left) {
	case option.Some(floating):
		match term.IntegerValue(right) {
		case option.Some(integer):
			return integerFloatEqual(integer, floating)
		case option.None:
		}
	case option.None:
	}
	return false
}

func integerFloatEqual(integer *big.Int, floating float64) bool {
	if math.IsNaN(floating) || math.IsInf(floating, 0) {
		return false
	}
	converted := new(big.Rat).SetFloat64(floating)
	wanted := new(big.Rat).SetInt(integer)
	return converted.Cmp(wanted) == 0
}

func getList(machine *Machine, instruction beam.Instruction, headOnly bool) result.Result[instructionOutcome, Failure] {
	want := 3
	if headOnly {
		want = 2
	}
	if len(instruction.Operands) != want {
		return malformedCoreInstruction(instruction)
	}
	match machine.resolve(instruction.Operands[0]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		match splitList(value) {
		case option.None:
			return result.Err[instructionOutcome, Failure](InvalidProgram(instruction.Opcode.Name + " source is not a nonempty list"))
		case option.Some(parts):
			match machine.assign(instruction.Operands[1], parts.Head) {
			case result.Err(failure):
				return result.Err[instructionOutcome, Failure](failure)
			case result.Ok(MachineMutated):
			}
			if !headOnly {
				match machine.assign(instruction.Operands[2], parts.Tail) {
				case result.Err(failure):
					return result.Err[instructionOutcome, Failure](failure)
				case result.Ok(MachineMutated):
				}
			}
			machine.pc++
			return result.Ok[instructionOutcome, Failure](InstructionContinues())
		}
	}
}

type listParts struct {
	Head term.Term
	Tail term.Term
}

func splitList(value term.Term) option.Option[listParts] {
	match value {
	case term.ProperListTerm(elements):
		if len(elements) == 0 {
			return option.None[listParts]()
		}
		return option.Some(listParts{Head: term.Clone(elements[0]), Tail: term.List(elements[1:]...)})
	case term.ImproperListTerm(elements, tail):
		if len(elements) == 0 {
			return option.None[listParts]()
		}
		remaining := term.Clone(tail)
		if len(elements) > 1 {
			remaining = term.ImproperList(elements[1:], tail)
		}
		return option.Some(listParts{Head: term.Clone(elements[0]), Tail: remaining})
	case _:
		return option.None[listParts]()
	}
}

func getListTail(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 2 {
		return malformedCoreInstruction(instruction)
	}
	match machine.resolve(instruction.Operands[0]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		match splitList(value) {
		case option.None:
			return result.Err[instructionOutcome, Failure](InvalidProgram("get_tl source is not a nonempty list"))
		case option.Some(parts):
			match machine.assign(instruction.Operands[1], parts.Tail) {
			case result.Err(failure):
				return result.Err[instructionOutcome, Failure](failure)
			case result.Ok(MachineMutated):
				machine.pc++
				return result.Ok[instructionOutcome, Failure](InstructionContinues())
			}
		}
	}
}

func putList(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 3 {
		return malformedCoreInstruction(instruction)
	}
	match machine.resolve(instruction.Operands[0]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(head):
		match machine.resolve(instruction.Operands[1]) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(tail):
			value := prependList(head, tail)
			match machine.assign(instruction.Operands[2], value) {
			case result.Err(failure):
				return result.Err[instructionOutcome, Failure](failure)
			case result.Ok(MachineMutated):
				machine.pc++
				return result.Ok[instructionOutcome, Failure](InstructionContinues())
			}
		}
	}
}

func prependList(head term.Term, tail term.Term) term.Term {
	match tail {
	case term.ProperListTerm(elements):
		return term.List(append([]term.Term{term.Clone(head)}, elements...)...)
	case term.ImproperListTerm(elements, improperTail):
		return term.ImproperList(append([]term.Term{term.Clone(head)}, elements...), improperTail)
	case _:
		return term.ImproperList([]term.Term{term.Clone(head)}, tail)
	}
}

func getTupleElement(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 3 {
		return malformedCoreInstruction(instruction)
	}
	var index uint64
	match beam.Uint64(instruction.Operands[1]) {
	case option.None:
		return result.Err[instructionOutcome, Failure](InvalidProgram("tuple element index is not uint64"))
	case option.Some(value):
		index = value
	}
	match machine.resolve(instruction.Operands[0]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		match value {
		case term.TupleTerm(elements):
			if index >= uint64(len(elements)) {
				return result.Err[instructionOutcome, Failure](InvalidProgram("tuple element index is out of range"))
			}
			match machine.assign(instruction.Operands[2], elements[index]) {
			case result.Err(failure):
				return result.Err[instructionOutcome, Failure](failure)
			case result.Ok(MachineMutated):
				machine.pc++
				return result.Ok[instructionOutcome, Failure](InstructionContinues())
			}
		case _:
			return result.Err[instructionOutcome, Failure](InvalidProgram("get_tuple_element source is not a tuple"))
		}
	}
}

func putTuple(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 2 {
		return malformedCoreInstruction(instruction)
	}
	var operands []beam.Operand
	match instruction.Operands[1] {
	case beam.ListOperand(items):
		operands = items
	case _:
		return result.Err[instructionOutcome, Failure](InvalidProgram("put_tuple2 elements are not a list operand"))
	}
	elements := make([]term.Term, len(operands))
	for index, operand := range operands {
		match machine.resolve(operand) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(value):
			elements[index] = value
		}
	}
	match machine.assign(instruction.Operands[0], term.Tuple(elements...)) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(MachineMutated):
		machine.pc++
		return result.Ok[instructionOutcome, Failure](InstructionContinues())
	}
}

func swapRegisters(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 2 {
		return malformedCoreInstruction(instruction)
	}
	match machine.resolve(instruction.Operands[0]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(left):
		match machine.resolve(instruction.Operands[1]) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(right):
			match machine.assign(instruction.Operands[0], right) {
			case result.Err(failure):
				return result.Err[instructionOutcome, Failure](failure)
			case result.Ok(MachineMutated):
			}
			match machine.assign(instruction.Operands[1], left) {
			case result.Err(failure):
				return result.Err[instructionOutcome, Failure](failure)
			case result.Ok(MachineMutated):
				machine.pc++
				return result.Ok[instructionOutcome, Failure](InstructionContinues())
			}
		}
	}
}

func initializeYRegisters(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 1 {
		return malformedCoreInstruction(instruction)
	}
	match instruction.Operands[0] {
	case beam.ListOperand(registers):
		for _, register := range registers {
			match machine.assign(register, term.List()) {
			case result.Err(failure):
				return result.Err[instructionOutcome, Failure](failure)
			case result.Ok(MachineMutated):
			}
		}
		machine.pc++
		return result.Ok[instructionOutcome, Failure](InstructionContinues())
	case _:
		return result.Err[instructionOutcome, Failure](InvalidProgram("init_yregs operand is not a register list"))
	}
}

func selectValue(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 3 {
		return malformedCoreInstruction(instruction)
	}
	match machine.resolve(instruction.Operands[0]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		return selectFromPairs(machine, value, instruction.Operands[1], instruction.Operands[2], false)
	}
}

func selectTupleArity(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 3 {
		return malformedCoreInstruction(instruction)
	}
	match machine.resolve(instruction.Operands[0]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		match value {
		case term.TupleTerm(elements):
			return selectFromPairs(machine, term.Integer(int64(len(elements))), instruction.Operands[1], instruction.Operands[2], true)
		case _:
			return jumpToOperand(machine, instruction.Operands[1])
		}
	}
}

func selectFromPairs(
	machine *Machine,
	value term.Term,
	fail beam.Operand,
	pairsOperand beam.Operand,
	unsignedKeys bool,
) result.Result[instructionOutcome, Failure] {
	var pairs []beam.Operand
	match pairsOperand {
	case beam.ListOperand(items):
		pairs = items
	case _:
		return result.Err[instructionOutcome, Failure](InvalidProgram("select destinations are not a list operand"))
	}
	if len(pairs)%2 != 0 {
		return result.Err[instructionOutcome, Failure](InvalidProgram("select destinations are not key/label pairs"))
	}
	for index := 0; index < len(pairs); index += 2 {
		var key term.Term
		if unsignedKeys {
			match beam.Uint64(pairs[index]) {
			case option.None:
				return result.Err[instructionOutcome, Failure](InvalidProgram("tuple arity key is not uint64"))
			case option.Some(arity):
				key = term.MustBigInteger(new(big.Int).SetUint64(arity))
			}
		} else {
			match machine.resolve(pairs[index]) {
			case result.Err(failure):
				return result.Err[instructionOutcome, Failure](failure)
			case result.Ok(resolved):
				key = resolved
			}
		}
		if term.Equal(value, key) {
			return jumpToOperand(machine, pairs[index+1])
		}
	}
	return jumpToOperand(machine, fail)
}

func branchOnTest(
	machine *Machine,
	fail beam.Operand,
	matched bool,
) result.Result[instructionOutcome, Failure] {
	if matched {
		machine.pc++
		return result.Ok[instructionOutcome, Failure](InstructionContinues())
	}
	return jumpToOperand(machine, fail)
}

func jumpToOperand(machine *Machine, operand beam.Operand) result.Result[instructionOutcome, Failure] {
	match labelIndex(operand) {
	case option.None:
		return result.Err[instructionOutcome, Failure](InvalidProgram("branch destination is not a label"))
	case option.Some(label):
		target, present := machine.labels[label]
		match option.Of(target, present) {
		case option.None:
			return result.Err[instructionOutcome, Failure](MissingLabel(label))
		case option.Some(position):
			machine.pc = position + 1
			return result.Ok[instructionOutcome, Failure](InstructionContinues())
		}
	}
}

func malformedCoreInstruction(instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
		"%s has %d operands",
		instruction.Opcode.Name,
		len(instruction.Operands),
	)))
}
