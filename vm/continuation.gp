package vm

import (
	"fmt"
	"math"
	"math/big"
	"time"

	"goforge.dev/goplus/std/option"
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
	ExecutionRaised(Class term.Term, Reason term.Term, Progress ExecutionProgress)
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

func (continuation *Continuation) ReleaseMemory() { if continuation == nil || continuation.machine == nil { return }; continuation.machine.resetProcessMemory(); continuation.completed = true }

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
	case "call", "call_only", "call_last", "call_ext", "call_ext_only", "call_ext_last", "call_fun", "call_fun2", "return", "send", "loop_rec_end":
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
	if machine.pc < len(machine.program) && machine.program[machine.pc].Opcode.Name == "func_info" {
		machine.pc++
	}
	machine.steps = 0
	machine.returnPCs = machine.returnPCs[:0]
	machine.returnImages = machine.returnImages[:0]
	machine.releaseAllCode()
	machine.handlers = machine.handlers[:0]
	machine.nextHandler = 0
	if machine.root != nil {
		machine.activate(machine.root)
	}
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
			var checked Failure = failure
			match checked {
			case RaisedException(class, reason):
				match machine.unwindException(class, reason) {
				case result.Err(unwindFailure):
					return result.Err[ExecutionSlice, Failure](unwindFailure)
				case result.Ok(caught):
					if caught {
						continue
					}
				}
				machine.releaseAllCode()
				return result.Ok[ExecutionSlice, Failure](ExecutionRaised(
					term.Clone(class),
					term.Clone(reason),
					ExecutionProgress{
						Reductions: reductions,
						Instructions: instructions,
						TotalInstructions: machine.steps,
					},
				))
			case InvalidConfiguration(_), ImmediateOutOfRange(_), HeapIndexOutOfRange(_, _), MemoryFailure(_), InvalidProgram(_), RegisterOutOfRange(_, _), UninitializedRegister(_, _), MissingConstant(_, _), MissingLabel(_), StepLimitExceeded(_), UnsupportedOpcode(_, _, _):
				return result.Err[ExecutionSlice, Failure](failure)
			}
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
				machine.releaseAllCode()
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
	case "label":
		machine.pc = next
	case "func_info":
		return result.Err[instructionOutcome, Failure](RaisedException(
			term.MustAtom("error"),
			term.MustAtom("function_clause"),
		))
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
			machine.pushReturn(next)
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
	case "call_ext":
		return executeExternalCall(machine, instruction, host, false, false)
	case "call_ext_only":
		return executeExternalCall(machine, instruction, host, true, false)
	case "call_ext_last":
		return executeExternalCall(machine, instruction, host, true, true)
	case "bif0", "bif1", "bif2", "gc_bif1", "gc_bif2", "gc_bif3":
		return executeBIFInstruction(machine, instruction, host)
	case "is_lt", "is_ge":
		return executeTermOrderInstruction(machine, instruction)
	case "make_fun3":
		return executeMakeFun3(machine, instruction)
	case "call_fun", "call_fun2":
		return executeCallFun(machine, instruction)
	case "is_function", "is_function2":
		return executeFunctionTest(machine, instruction)
	case "catch", "try":
		return executeExceptionSetup(machine, instruction)
	case "catch_end", "try_end", "try_case":
		return executeExceptionCleanup(machine, instruction)
	case "raise", "case_end", "badmatch", "if_end", "badrecord", "try_case_end":
		return executeExceptionRaise(machine, instruction)
	case "allocate", "allocate_zero":
		match machine.allocate(instruction, 0) {
		case result.Ok(MachineMutated):
			machine.pc = next
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		}
	case "allocate_heap", "get_hd", "get_list", "get_tl", "get_tuple_element", "init_yregs",
		"is_atom", "is_binary", "is_bitstr", "is_boolean", "is_eq", "is_eq_exact", "is_float",
		"is_integer", "is_list", "is_map", "is_ne", "is_ne_exact", "is_nil", "is_nonempty_list",
		"is_number", "is_pid", "is_port", "is_reference", "is_tagged_tuple", "is_tuple", "line",
		"put_list", "put_tuple2", "select_tuple_arity", "select_val", "swap", "test_arity", "test_heap", "trim":
		return executeCoreTermInstruction(machine, instruction)
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
			var timerCapability TimerCapability = host.Timer
			match timerCapability {
			case TimerUnavailable:
			case TimerAllowed:
				if host.timerCancel == nil {
					return result.Err[instructionOutcome, Failure](InvalidConfiguration("timer cancel effect is nil"))
				}
				var cancelled TimerMutation = host.timerCancel()
				match cancelled {
				case TimerMutationRejected(detail):
					return result.Err[instructionOutcome, Failure](InvalidProgram("timer cancellation rejected: " + detail))
				case TimerChanged, TimerUnchanged:
				}
			}
			machine.pc = next
		}
	case "timeout":
		var timerCapability TimerCapability = host.Timer
		match timerCapability {
		case TimerUnavailable:
			return result.Err[instructionOutcome, Failure](InvalidProgram("timeout requires an explicit timer capability"))
		case TimerAllowed:
			if host.timerFinish == nil {
				return result.Err[instructionOutcome, Failure](InvalidConfiguration("timer finish effect is nil"))
			}
			var finished TimerMutation = host.timerFinish()
			match finished {
			case TimerMutationRejected(detail):
				return result.Err[instructionOutcome, Failure](InvalidProgram("timer completion rejected: " + detail))
			case TimerChanged, TimerUnchanged:
				machine.pc = next
			}
		}
	case "wait":
		match machine.instructionLabel(instruction, 0) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(target):
			machine.pc = target
			return result.Ok[instructionOutcome, Failure](InstructionWaits())
		}
	case "wait_timeout":
		if len(instruction.Operands) != 2 {
			return result.Err[instructionOutcome, Failure](InvalidProgram(fmt.Sprintf(
				"wait_timeout has %d operands",
				len(instruction.Operands),
			)))
		}
		match receiveTimeout(machine, instruction.Operands[1]) {
		case result.Err(failure):
			return result.Err[instructionOutcome, Failure](failure)
		case result.Ok(timeout):
			match timeout {
			case option.None:
				match machine.instructionLabel(instruction, 0) {
				case result.Err(failure):
					return result.Err[instructionOutcome, Failure](failure)
				case result.Ok(target):
					machine.pc = target
					return result.Ok[instructionOutcome, Failure](InstructionWaits())
				}
			case option.Some(delay):
				if delay == 0 {
					machine.pc = next
					return result.Ok[instructionOutcome, Failure](InstructionContinues())
				}
				var timerCapability TimerCapability = host.Timer
				match timerCapability {
				case TimerUnavailable:
					return result.Err[instructionOutcome, Failure](InvalidProgram("wait_timeout requires an explicit timer capability"))
				case TimerAllowed:
					if host.timerWait == nil {
						return result.Err[instructionOutcome, Failure](InvalidConfiguration("timer wait effect is nil"))
					}
					var waited TimerWaitOutcome = host.timerWait(delay)
					match waited {
					case TimerRejected(detail):
						return result.Err[instructionOutcome, Failure](InvalidProgram("timer wait rejected: " + detail))
					case TimerExpired:
						machine.pc = next
					case TimerPending:
						match machine.instructionLabel(instruction, 0) {
						case result.Err(failure):
							return result.Err[instructionOutcome, Failure](failure)
						case result.Ok(target):
							machine.pc = target
							return result.Ok[instructionOutcome, Failure](InstructionWaits())
						}
					}
				}
			}
		}
	case "return":
		if !machine.returnToCaller() {
			return result.Ok[instructionOutcome, Failure](InstructionHalts())
		}
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

func receiveTimeout(
	machine *Machine,
	operand beam.Operand,
) result.Result[option.Option[time.Duration], Failure] {
	match machine.resolve(operand) {
	case result.Err(failure):
		return result.Err[option.Option[time.Duration], Failure](failure)
	case result.Ok(value):
		match term.AtomName(value) {
		case option.Some(name):
			if name == "infinity" {
				return result.Ok[option.Option[time.Duration], Failure](option.None[time.Duration]())
			}
		case option.None:
		}
		match term.IntegerValue(value) {
		case option.None:
			return result.Err[option.Option[time.Duration], Failure](InvalidProgram(
				"receive timeout must be a non-negative integer or infinity",
			))
		case option.Some(integer):
			if !integer.IsInt64() {
				return result.Err[option.Option[time.Duration], Failure](InvalidProgram("receive timeout is out of range"))
			}
			milliseconds := integer.Int64()
			if milliseconds < 0 || milliseconds > math.MaxInt64/int64(time.Millisecond) {
				return result.Err[option.Option[time.Duration], Failure](InvalidProgram("receive timeout is out of range"))
			}
			return result.Ok[option.Option[time.Duration], Failure](
				option.Some(time.Duration(milliseconds) * time.Millisecond),
			)
		}
	}
}
