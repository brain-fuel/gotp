package vm

import (
	"fmt"
	"math/big"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

type exceptionHandlerKind enum {
	oldCatchHandler()
	tryCatchHandler()
}

type pendingException struct {
	class  term.Term
	reason term.Term
	trace  term.Term
}

type exceptionHandler struct {
	token       uint64
	kind        exceptionHandlerKind
	image       *machineImage
	codeLeave   func()
	pc          int
	returnDepth int
	yDepth      int
	active      bool
	pending     option.Option[pendingException]
}

// assayxport:unit gotp.vm.exception-handlers
func executeExceptionSetup(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 2 {
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf("%s has %d operands", instruction.Opcode.Name, len(instruction.Operands))))
	}
	var handlerPC int
	match machine.instructionLabel(instruction, 1) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		handlerPC = value
	}
	var kind exceptionHandlerKind = tryCatchHandler()
	if instruction.Opcode.Name == "catch" {
		kind = oldCatchHandler()
	}
	machine.nextHandler++
	token := machine.nextHandler
	match machine.assign(instruction.Operands[0], term.MustBigInteger(new(big.Int).SetUint64(token))) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(MachineMutated):
	}
	machine.handlers = append(machine.handlers, exceptionHandler{
		token: token,
		kind: kind,
		image: machine.current,
		codeLeave: machine.currentCodeLeave,
		pc: handlerPC,
		returnDepth: len(machine.returnPCs),
		yDepth: machine.y.Len(),
		active: true,
		pending: option.None[pendingException](),
	})
	machine.pc++
	return result.Ok[instructionOutcome, Failure](InstructionContinues())
}

func (machine *Machine) handlerToken(operand beam.Operand) result.Result[uint64, Failure] {
	match machine.resolve(operand) {
	case result.Err(failure):
		return result.Err[uint64, Failure](failure)
	case result.Ok(value):
		match term.IntegerValue(value) {
		case option.None:
			return result.Err[uint64, Failure](InvalidProgram("exception handler token is not an integer"))
		case option.Some(integer):
			if integer.Sign() <= 0 || !integer.IsUint64() {
				return result.Err[uint64, Failure](InvalidProgram("exception handler token is out of range"))
			}
			return result.Ok[uint64, Failure](integer.Uint64())
		}
	}
}

func (machine *Machine) topHandler(operand beam.Operand) result.Result[exceptionHandler, Failure] {
	if len(machine.handlers) == 0 {
		return result.Err[exceptionHandler, Failure](InvalidProgram("exception handler stack is empty"))
	}
	var token uint64
	match machine.handlerToken(operand) {
	case result.Err(failure):
		return result.Err[exceptionHandler, Failure](failure)
	case result.Ok(value):
		token = value
	}
	handler := machine.handlers[len(machine.handlers) - 1]
	if handler.token != token {
		return result.Err[exceptionHandler, Failure](InvalidProgram("exception handler token is not stack top"))
	}
	return result.Ok[exceptionHandler, Failure](handler)
}

func executeExceptionCleanup(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	if len(instruction.Operands) != 1 {
		return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf("%s has %d operands", instruction.Opcode.Name, len(instruction.Operands))))
	}
	var handler exceptionHandler
	match machine.topHandler(instruction.Operands[0]) {
	case result.Err(failure):
		return result.Err[instructionOutcome, Failure](failure)
	case result.Ok(value):
		handler = value
	}
	match handler.kind {
	case oldCatchHandler:
		if instruction.Opcode.Name != "catch_end" {
			return result.Err[instructionOutcome, Failure](InvalidProgram("catch handler requires catch_end"))
		}
	case tryCatchHandler:
		if instruction.Opcode.Name == "catch_end" {
			return result.Err[instructionOutcome, Failure](InvalidProgram("try handler cannot use catch_end"))
		}
	}
	machine.handlers = machine.handlers[:len(machine.handlers) - 1]
	if instruction.Opcode.Name == "catch_end" {
		match handler.pending {
		case option.None:
		case option.Some(raised):
			var caught term.Term
			match term.AtomName(raised.class) {
			case option.Some(name):
				switch name {
				case "throw":
					caught = raised.reason
				case "exit":
					caught = term.Tuple(term.MustAtom("EXIT"), raised.reason)
				case "error":
					caught = term.Tuple(term.MustAtom("EXIT"), term.Tuple(raised.reason, raised.trace))
				default:
					return result.Err[instructionOutcome, Failure](RaisedException(raised.class, raised.reason))
				}
			case option.None:
				return result.Err[instructionOutcome, Failure](RaisedException(raised.class, raised.reason))
			}
			match machine.SetX(0, caught) {
			case result.Err(failure):
				return result.Err[instructionOutcome, Failure](failure)
			case result.Ok(MachineMutated):
			}
		}
	}
	machine.pc++
	return result.Ok[instructionOutcome, Failure](InstructionContinues())
}

func (machine *Machine) unwindException(class term.Term, reason term.Term) result.Result[bool, Failure] {
	for index := len(machine.handlers) - 1; index >= 0; index-- {
		handler := &machine.handlers[index]
		if !handler.active {
			continue
		}
		match machine.SetX(2, term.List()) {
		case result.Err(failure):
			return result.Err[bool, Failure](failure)
		case result.Ok(MachineMutated):
		}
		match machine.SetX(1, reason) {
		case result.Err(failure):
			return result.Err[bool, Failure](failure)
		case result.Ok(MachineMutated):
		}
		match machine.SetX(0, class) {
		case result.Err(failure):
			return result.Err[bool, Failure](failure)
		case result.Ok(MachineMutated):
		}
		handler.active = false
		handler.pending = option.Some(pendingException{
			class: term.Clone(class),
			reason: term.Clone(reason),
			trace: term.List(),
		})
		machine.handlers = machine.handlers[:index + 1]
		if machine.current != handler.image { machine.leaveCurrentCode() }
		for depth := len(machine.returnCodeLeaves) - 1; depth > handler.returnDepth; depth-- { if machine.returnCodeLeaves[depth] != nil { machine.returnCodeLeaves[depth]() } }
		machine.returnPCs = machine.returnPCs[:handler.returnDepth]
		machine.returnImages = machine.returnImages[:handler.returnDepth]
		machine.returnCodeLeaves = machine.returnCodeLeaves[:handler.returnDepth]
		if machine.y.Len() > handler.yDepth {
			machine.y.Truncate(handler.yDepth)
		}
		machine.activate(handler.image)
		machine.currentCodeLeave = handler.codeLeave
		machine.pc = handler.pc
		return result.Ok[bool, Failure](true)
	}
	return result.Ok[bool, Failure](false)
}

func executeExceptionRaise(machine *Machine, instruction beam.Instruction) result.Result[instructionOutcome, Failure] {
	class := term.MustAtom("error")
	var reason term.Term
	switch instruction.Opcode.Name {
	case "raise":
		if len(instruction.Operands) != 2 {
			return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf("raise has %d operands", len(instruction.Operands))))
		}
		match machine.X(0) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): class = value }
		match machine.resolve(instruction.Operands[1]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): reason = value }
	case "case_end":
		if len(instruction.Operands) != 1 { return result.Err[instructionOutcome, Failure](InvalidProgram("case_end must have one operand")) }
		match machine.resolve(instruction.Operands[0]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): reason = term.Tuple(term.MustAtom("case_clause"), value) }
	case "badmatch":
		if len(instruction.Operands) != 1 { return result.Err[instructionOutcome, Failure](InvalidProgram("badmatch must have one operand")) }
		match machine.resolve(instruction.Operands[0]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): reason = term.Tuple(term.MustAtom("badmatch"), value) }
	case "if_end":
		if len(instruction.Operands) != 0 { return result.Err[instructionOutcome, Failure](InvalidProgram("if_end must have no operands")) }
		reason = term.MustAtom("if_clause")
	case "badrecord":
		if len(instruction.Operands) != 1 { return result.Err[instructionOutcome, Failure](InvalidProgram("badrecord must have one operand")) }
		match machine.resolve(instruction.Operands[0]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): reason = term.Tuple(term.MustAtom("badrecord"), value) }
	case "try_case_end":
		if len(instruction.Operands) != 1 { return result.Err[instructionOutcome, Failure](InvalidProgram("try_case_end must have one operand")) }
		match machine.resolve(instruction.Operands[0]) { case result.Err(failure): return result.Err[instructionOutcome, Failure](failure); case result.Ok(value): reason = term.Tuple(term.MustAtom("try_clause"), value) }
	default:
		return result.Err[instructionOutcome, Failure](UnsupportedOpcode(instruction.Opcode.Name, instruction.Opcode.Arity, instruction.Offset))
	}
	return result.Err[instructionOutcome, Failure](RaisedException(class, reason))
}
