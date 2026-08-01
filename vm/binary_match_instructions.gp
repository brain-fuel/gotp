package vm

import (
	"math"
	"unicode/utf8"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

func binaryMatchHandle(identifier uint64) term.Term {
	return term.Tuple(term.MustAtom("$gotp_binary_match"), term.Integer(int64(identifier)))
}

func binaryMatchIdentifier(value term.Term) option.Option[uint64] {
	match term.Elements(value) {
	case option.None: return option.None[uint64]()
	case option.Some(parts):
		if len(parts) != 2 { return option.None[uint64]() }
		match term.AtomName(parts[0]) { case option.Some(name): if name != "$gotp_binary_match" { return option.None[uint64]() }; case option.None: return option.None[uint64]() }
		match term.Int64(parts[1]) { case option.Some(identifier): if identifier > 0 { return option.Some(uint64(identifier)) }; return option.None[uint64](); case option.None: return option.None[uint64]() }
	}
}

func (machine *Machine) newBinaryMatch(value term.Term) option.Option[term.Term] {
	var context binaryMatchContext
	match term.BinaryValue(value) {
	case option.Some(bytes): context = binaryMatchContext{bytes: bytes}
	case option.None:
		match binaryMatchIdentifier(value) {
		case option.None: return option.None[term.Term]()
		case option.Some(identifier):
			found, present := machine.binaryMatches[identifier]
			if !present { return option.None[term.Term]() }
			context = binaryMatchContext{bytes: append([]byte(nil), found.bytes...), bitPosition: found.bitPosition}
		}
	}
	identifier := machine.nextBinaryMatch
	if identifier == math.MaxUint64 { return option.None[term.Term]() }
	machine.nextBinaryMatch++
	machine.binaryMatches[identifier] = context
	return option.Some(binaryMatchHandle(identifier))
}

func (machine *Machine) binaryMatch(value term.Term) option.Option[uint64] {
	match binaryMatchIdentifier(value) {
	case option.None: return option.None[uint64]()
	case option.Some(identifier):
		_, present := machine.binaryMatches[identifier]
		if !present { return option.None[uint64]() }
		return option.Some(identifier)
	}
}

func binaryMatchFailure(machine *Machine, instruction beam.Instruction, failIndex int) result.Result[instructionOutcome, Failure] {
	match machine.instructionLabel(instruction, failIndex) {
	case result.Err(failure): return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(target): machine.pc = target; return result.Ok[instructionOutcome, Failure](InstructionContinues())
	}
}

func executeBinaryMatchInstruction(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	next := machine.pc + 1
	switch instruction.Opcode.Name {
	case "is_any_native_record":
		if len(instruction.Operands) != 2 { return result.Err[instructionOutcome, Failure](InvalidProgram("is_any_native_record must have two operands")) }
		var value term.Term
		match machine.resolve(instruction.Operands[1]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(found): value = found }
		match machine.binaryMatch(value) { case option.None: return binaryMatchFailure(machine, instruction, 0); case option.Some(_): machine.pc = next }
	case "bs_start_match3", "bs_start_match4":
		if len(instruction.Operands) != 4 { return result.Err[instructionOutcome, Failure](InvalidProgram("binary match start must have four operands")) }
		var source term.Term
		match machine.resolve(instruction.Operands[2]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): source = value }
		match machine.newBinaryMatch(source) {
		case option.None:
			if instruction.Opcode.Name == "bs_start_match3" { return binaryMatchFailure(machine, instruction, 0) }
			return result.Err[instructionOutcome, Failure](RaisedException(term.MustAtom("error"), term.MustAtom("badarg")))
		case option.Some(handle):
			match machine.assign(instruction.Operands[3], handle) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(_): machine.pc = next }
		}
	case "bs_get_position":
		if len(instruction.Operands) != 3 { return result.Err[instructionOutcome, Failure](InvalidProgram("bs_get_position must have three operands")) }
		var handle term.Term
		match machine.resolve(instruction.Operands[0]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): handle = value }
		match machine.binaryMatch(handle) {
		case option.None: return result.Err[instructionOutcome, Failure](InvalidProgram("bs_get_position requires a match context"))
		case option.Some(identifier):
			position := machine.binaryMatches[identifier].bitPosition
			match machine.assign(instruction.Operands[1], term.Integer(int64(position))) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(_): machine.pc = next }
		}
	case "bs_set_position":
		if len(instruction.Operands) != 2 { return result.Err[instructionOutcome, Failure](InvalidProgram("bs_set_position must have two operands")) }
		var handle, positionTerm term.Term
		match machine.resolve(instruction.Operands[0]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): handle = value }
		match machine.resolve(instruction.Operands[1]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): positionTerm = value }
		match machine.binaryMatch(handle) {
		case option.None: return result.Err[instructionOutcome, Failure](InvalidProgram("bs_set_position requires a match context"))
		case option.Some(identifier):
			match term.Int64(positionTerm) {
			case option.None: return result.Err[instructionOutcome, Failure](RaisedException(term.MustAtom("error"), term.MustAtom("badarg")))
			case option.Some(position):
				context := machine.binaryMatches[identifier]
				if position < 0 || position > int64(len(context.bytes))*8 { return result.Err[instructionOutcome, Failure](RaisedException(term.MustAtom("error"), term.MustAtom("badarg"))) }
				context.bitPosition = int(position); machine.binaryMatches[identifier] = context; machine.pc = next
			}
		}
	case "bs_get_tail":
		if len(instruction.Operands) != 3 { return result.Err[instructionOutcome, Failure](InvalidProgram("bs_get_tail must have three operands")) }
		var handle term.Term
		match machine.resolve(instruction.Operands[0]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): handle = value }
		match machine.binaryMatch(handle) {
		case option.None: return result.Err[instructionOutcome, Failure](InvalidProgram("bs_get_tail requires a match context"))
		case option.Some(identifier):
			context := machine.binaryMatches[identifier]
			if context.bitPosition%8 != 0 { return result.Err[instructionOutcome, Failure](InvalidProgram("unaligned bitstring tails are not represented")) }
			match machine.assign(instruction.Operands[1], term.Binary(context.bytes[context.bitPosition/8:])) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(_): machine.pc = next }
		}
	case "bs_get_utf8", "bs_skip_utf8":
		minimum := 4
		if instruction.Opcode.Name == "bs_get_utf8" { minimum = 5 }
		if len(instruction.Operands) != minimum { return result.Err[instructionOutcome, Failure](InvalidProgram("UTF-8 match instruction has invalid operands")) }
		var handle term.Term
		match machine.resolve(instruction.Operands[1]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): handle = value }
		match machine.binaryMatch(handle) {
		case option.None: return binaryMatchFailure(machine, instruction, 0)
		case option.Some(identifier):
			context := machine.binaryMatches[identifier]
			if context.bitPosition%8 != 0 || context.bitPosition >= len(context.bytes)*8 { return binaryMatchFailure(machine, instruction, 0) }
			codepoint, width := utf8.DecodeRune(context.bytes[context.bitPosition/8:])
			if codepoint == utf8.RuneError && width == 1 { return binaryMatchFailure(machine, instruction, 0) }
			context.bitPosition += width*8; machine.binaryMatches[identifier] = context
			if instruction.Opcode.Name == "bs_get_utf8" {
				match machine.assign(instruction.Operands[4], term.Integer(int64(codepoint))) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(_): }
			}
			machine.pc = next
		}
	}
	return result.Ok[instructionOutcome, Failure](InstructionContinues())
}
