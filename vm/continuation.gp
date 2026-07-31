package vm

import (
	"fmt"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

type VMReductionBudget struct {
	value int
}

type ExecutionProgress struct {
	Reductions        int
	Instructions      int
	TotalInstructions int
}

type ExecutionSlice enum {
	ExecutionSuspended(Progress ExecutionProgress)
	ExecutionWaiting(Progress ExecutionProgress)
	ExecutionCompleted(Value term.Term, Progress ExecutionProgress)
}

type instructionOutcome enum {
	InstructionContinues()
	InstructionWaits()
	InstructionHalts()
}

type ReductionClass enum {
	ReductionFree()
	DispatchReduction()
}

type Continuation struct {
	machine   *Machine
	completed bool
}

// assayxport:unit gotp.vm.reduction-continuation
func NewVMReductionBudget(value int) result.Result[VMReductionBudget, Failure] {
	if value <= 0 {
		return result.Err[VMReductionBudget, Failure](InvalidConfiguration(fmt.Sprintf(
			"VM reduction budget must be positive, got %d",
			value,
		)))
	}
	return result.Ok[VMReductionBudget, Failure](VMReductionBudget{value: value})
}

func VMReductionBudgetValue(budget VMReductionBudget) int {
	return budget.value
}

func OpcodeReductionClass(name string) ReductionClass {
	switch name {
	case "call", "call_only", "call_last", "return", "send", "loop_rec_end":
		return DispatchReduction()
	default:
		return ReductionFree()
	}
}

func OpcodeReductionCost(name string) int {
	match OpcodeReductionClass(name) {
	case ReductionFree:
		return 0
	case DispatchReduction:
		return 1
	}
}

func (machine *Machine) Start(entryLabel uint64) result.Result[*Continuation, Failure] {
	entry, present := machine.labels[entryLabel]
	if !present {
		return result.Err[*Continuation, Failure](MissingLabel(entryLabel))
	}
	machine.pc = entry + 1
	machine.steps = 0
	machine.returnPCs = machine.returnPCs[:0]
	return result.Ok[*Continuation, Failure](&Continuation{machine: machine})
}

func (continuation *Continuation) Resume(
	budget VMReductionBudget,
) result.Result[ExecutionSlice, Failure] {
	return continuation.ResumeWithHost(budget, NoHostCapabilities())
}

func (continuation *Continuation) ResumeWithHost(
	budget VMReductionBudget,
	host HostCapabilities,
) result.Result[ExecutionSlice, Failure] {
	if continuation == nil || continuation.machine == nil {
		return result.Err[ExecutionSlice, Failure](InvalidConfiguration("nil continuation"))
	}
	if continuation.completed {
		return result.Err[ExecutionSlice, Failure](InvalidProgram("continuation has completed"))
	}
	if budget.value <= 0 {
		return result.Err[ExecutionSlice, Failure](InvalidConfiguration(
			"VM reduction budget must be positive",
		))
	}
	machine := continuation.machine
	remaining := budget.value
	reductions := 0
	instructions := 0
	for {
		if machine.steps >= machine.stepLimit {
			return result.Err[ExecutionSlice, Failure](StepLimitExceeded(machine.stepLimit))
		}
		if machine.pc < 0 || machine.pc >= len(machine.program) {
			return result.Err[ExecutionSlice, Failure](InvalidProgram(fmt.Sprintf(
				"program counter %d is out of range",
				machine.pc,
			)))
		}
		instruction := machine.program[machine.pc]
		cost := OpcodeReductionCost(instruction.Opcode.Name)
		if cost > remaining {
			return result.Ok[ExecutionSlice, Failure](ExecutionSuspended(ExecutionProgress{
				Reductions: reductions,
				Instructions: instructions,
				TotalInstructions: machine.steps,
			}))
		}
		machine.steps++
		instructions++
		remaining -= cost
		reductions += cost
		var executed result.Result[instructionOutcome, Failure] = executeInstruction(
			machine,
			instruction,
			host,
		)
		match executed {
		case result.Err(failure):
			return result.Err[ExecutionSlice, Failure](failure)
		case result.Ok(outcome):
			var instructionState instructionOutcome = outcome
			match instructionState {
			case InstructionContinues:
			case InstructionWaits:
				return result.Ok[ExecutionSlice, Failure](ExecutionWaiting(ExecutionProgress{
					Reductions: reductions,
					Instructions: instructions,
					TotalInstructions: machine.steps,
				}))
			case InstructionHalts:
				continuation.completed = true
				match machine.X(0) {
				case result.Err(failure):
					return result.Err[ExecutionSlice, Failure](failure)
				case result.Ok(value):
					return result.Ok[ExecutionSlice, Failure](ExecutionCompleted(
						value,
						ExecutionProgress{
							Reductions: reductions,
							Instructions: instructions,
							TotalInstructions: machine.steps,
						},
					))
				}
			}
		}
	}
}

// OTP-29.0.4 macros.tab charges FCALLS at DISPATCH and DISPATCH_RETURN.
func executeInstruction(
	machine *Machine,
	instruction beam.Instruction,
	host HostCapabilities,
) result.Result[instructionOutcome, Failure] {
	next := machine.pc + 1
	switch instruction.Opcode.Name {
	case "label", "func_info":
		machine.pc = next
	case "move":
		match machine.move(instruction) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(MachineMutated):
			machine.pc = next
		}
	case "jump":
		match machine.instructionLabel(instruction, 0) {
		case result.Ok(target):
			machine.pc = target
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		}
	case "call":
		match machine.instructionLabel(instruction, 1) {
		case result.Ok(target):
			machine.returnPCs = append(machine.returnPCs, next)
			machine.pc = target
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		}
	case "call_only":
		match machine.instructionLabel(instruction, 1) {
		case result.Ok(target):
			machine.pc = target
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		}
	case "call_last":
		match machine.deallocate(instruction, 2) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(MachineMutated):
		}
		match machine.instructionLabel(instruction, 1) {
		case result.Ok(target):
			machine.pc = target
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		}
	case "allocate", "allocate_zero":
		match machine.allocate(instruction, 0) {
		case result.Ok(MachineMutated):
			machine.pc = next
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		}
	case "deallocate":
		match machine.deallocate(instruction, 0) {
		case result.Ok(MachineMutated):
			machine.pc = next
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		}
	case "send":
		match machine.X(0) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(destination):
			match machine.X(1) {
			case result.Err(failure):
				return result.Err[instructionOutcome, Failure](failure)
			case result.Ok(message):
				var sendCapability SendCapability = host.Send
				match sendCapability {
				case SendUnavailable:
					return result.Err[instructionOutcome, Failure](InvalidProgram(
						"send requires an explicit host capability",
					))
				case SendAllowed:
					effect := host.send
					if effect == nil {
						return result.Err[instructionOutcome, Failure](InvalidConfiguration(
							"send capability effect is nil",
						))
					}
					var outcome SendOutcome = effect(destination, message)
					match outcome {
					case SendRejected(detail):
						return result.Err[instructionOutcome, Failure](InvalidProgram(
							"send rejected: " + detail,
						))
					case MessageSent(value):
						match machine.SetX(0, value) {
						case result.Err(failure):
							return result.Err[instructionOutcome, Failure](failure)
						case result.Ok(MachineMutated):
							machine.pc = next
						}
					}
				}
			}
		}
	case "loop_rec":
		if len(instruction.Operands) != 2 {
			return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
				"loop_rec has %d operands",
				len(instruction.Operands),
			)))
		}
		var receiveCapability ReceiveCapability = host.Receive
		match receiveCapability {
		case ReceiveUnavailable:
			return result.Err[instructionOutcome, Failure](InvalidProgram(
				"loop_rec requires an explicit receive capability",
			))
		case ReceiveAllowed:
			if host.peek == nil {
				return result.Err[instructionOutcome, Failure](InvalidConfiguration(
					"receive peek effect is nil",
				))
			}
			var outcome ReceiveOutcome = host.peek()
			match outcome {
			case ReceiveRejected(detail):
				return result.Err[instructionOutcome, Failure](InvalidProgram(
					"receive rejected: " + detail,
				))
			case ReceiveEmpty:
				match machine.instructionLabel(instruction, 0) {
				case result.Err(failure):
					return result.Err[instructionOutcome, Failure](failure)
				case result.Ok(target):
					machine.pc = target
				}
			case ReceiveMessage(message):
				match machine.assign(instruction.Operands[1], message) {
				case result.Err(failure):
					return result.Err[instructionOutcome, Failure](failure)
				case result.Ok(MachineMutated):
					machine.pc = next
				}
			}
		}
	case "loop_rec_end":
		if host.advance == nil {
			return result.Err[instructionOutcome, Failure](InvalidProgram(
				"loop_rec_end requires an explicit receive capability",
			))
		}
		var advanced AdvanceOutcome = host.advance()
		match advanced {
		case AdvanceRejected(detail):
			return result.Err[instructionOutcome, Failure](InvalidProgram(
				"receive advance rejected: " + detail,
			))
		case ReceiveCursorAdvanced:
			match machine.instructionLabel(instruction, 0) {
			case result.Err(failure):
				return result.Err[instructionOutcome, Failure](failure)
			case result.Ok(target):
				machine.pc = target
			}
		}
	case "remove_message":
		if host.remove == nil {
			return result.Err[instructionOutcome, Failure](InvalidProgram(
				"remove_message requires an explicit receive capability",
			))
		}
		var removed RemoveOutcome = host.remove()
		match removed {
		case RemoveRejected(detail):
			return result.Err[instructionOutcome, Failure](InvalidProgram(
				"receive removal rejected: " + detail,
			))
		case ReceiveMessageRemoved:
			machine.pc = next
		}
	case "wait":
		match machine.instructionLabel(instruction, 0) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(target):
			machine.pc = target
			return result.Ok[instructionOutcome, Failure](InstructionWaits())
		}
	case "return":
		if len(machine.returnPCs) == 0 {
			return result.Ok[instructionOutcome, Failure](InstructionHalts())
		}
		last := len(machine.returnPCs) - 1
		machine.pc = machine.returnPCs[last]
		machine.returnPCs = machine.returnPCs[:last]
	case "int_code_end":
		return result.Ok[instructionOutcome, Failure](InstructionHalts())
	default:
		return result.Err[instructionOutcome, Failure](UnsupportedOpcode(
			instruction.Opcode.Name,
			instruction.Opcode.Arity,
			instruction.Offset,
		))
	}
	return result.Ok[instructionOutcome, Failure](InstructionContinues())
}
