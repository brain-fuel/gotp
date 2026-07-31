package erts

import (
	"time"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/memory"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

type AdapterFailure enum {
	NilMachine()
	NilClock()
	NilCallRegistry()
	VMStartFailure(Cause vm.Failure)
	VMBudgetFailure(Cause vm.Failure)
}

func (failure AdapterFailure) Error() string {
	match failure {
	case NilMachine:
		return "gotp/erts: VM machine is nil"
	case NilClock:
		return "gotp/erts: VM process clock is nil"
	case NilCallRegistry:
		return "gotp/erts: VM process call registry is nil"
	case VMStartFailure(cause):
		return "gotp/erts: start VM process: " + cause.Error()
	case VMBudgetFailure(cause):
		return "gotp/erts: create VM reduction budget: " + cause.Error()
	}
}

type VMProcessState enum {
	VMProcessRunning()
	VMProcessSuspended(TotalReductions int, TotalInstructions int)
	VMProcessWaiting(TotalReductions int, TotalInstructions int)
	VMProcessCompleted(Value term.Term, TotalReductions int, TotalInstructions int)
	VMProcessRaised(Class term.Term, Reason term.Term, TotalReductions int, TotalInstructions int)
	VMProcessFailed(Detail string, TotalReductions int, TotalInstructions int)
}

type VMProcess struct {
	continuation *vm.Continuation
	quantum      vm.VMReductionBudget
	state        VMProcessState
	reductions   int
	instructions int
	receiveMessages memory.Buffer[kernel.MessageEnvelope]
	receiveCursor int
	clock           clock.Clock
	timer           *kernel.WakeTimer
	callRegistry    *CallRegistry
}

// assayxport:unit gotp.erts.vm-process
func NewVMProcess(
	machine *vm.Machine,
	entryLabel uint64,
) result.Result[*VMProcess, AdapterFailure] {
	return NewVMProcessWithClock(machine, entryLabel, clock.Real{})
}

// assayxport:unit gotp.erts.receive-timeout
func NewVMProcessWithClock(
	machine *vm.Machine,
	entryLabel uint64,
	source clock.Clock,
) result.Result[*VMProcess, AdapterFailure] {
	return newVMProcess(machine, entryLabel, source, nil)
}

func NewVMProcessWithRegistry(
	machine *vm.Machine,
	entryLabel uint64,
	source clock.Clock,
	registry *CallRegistry,
) result.Result[*VMProcess, AdapterFailure] {
	if registry == nil {
		return result.Err[*VMProcess, AdapterFailure](NilCallRegistry())
	}
	return newVMProcess(machine, entryLabel, source, registry)
}

func newVMProcess(
	machine *vm.Machine,
	entryLabel uint64,
	source clock.Clock,
	registry *CallRegistry,
) result.Result[*VMProcess, AdapterFailure] {
	if machine == nil {
		return result.Err[*VMProcess, AdapterFailure](NilMachine())
	}
	if source == nil {
		return result.Err[*VMProcess, AdapterFailure](NilClock())
	}
	var started result.Result[*vm.Continuation, vm.Failure] = machine.Start(entryLabel)
	match started {
	case result.Err(cause):
		return result.Err[*VMProcess, AdapterFailure](VMStartFailure(cause))
	case result.Ok(continuation):
		var checked result.Result[vm.VMReductionBudget, vm.Failure] = vm.NewVMReductionBudget(1)
		match checked {
		case result.Err(cause):
			return result.Err[*VMProcess, AdapterFailure](VMBudgetFailure(cause))
		case result.Ok(quantum):
			var initial VMProcessState = VMProcessRunning()
			return result.Ok[*VMProcess, AdapterFailure](&VMProcess{
				continuation: continuation,
				quantum: quantum,
				state: initial,
				clock: source,
				callRegistry: registry,
				receiveMessages: memory.NewBuffer[kernel.MessageEnvelope](8),
			})
		}
	}
}

func (process *VMProcess) Behavior() kernel.Behavior {
	return func(context *kernel.Context) kernel.StepResult {
		return process.Step(context)
	}
}

func (process *VMProcess) State() VMProcessState {
	return process.state
}

func (process *VMProcess) Step(context *kernel.Context) kernel.StepResult {
	match process.state {
	case VMProcessRunning:
		return process.resume(context)
	case VMProcessSuspended(_, _):
		return process.resume(context)
	case VMProcessWaiting(_, _):
		return process.resume(context)
	case VMProcessCompleted(_, _, _):
		return kernel.Stop(term.MustAtom("normal"))
	case VMProcessRaised(class, reason, _, _):
		return kernel.Stop(vmExceptionReason(class, reason))
	case VMProcessFailed(detail, _, _):
		return kernel.Stop(vmFailureReason(detail))
	}
}

func (process *VMProcess) resume(context *kernel.Context) kernel.StepResult {
	var checked result.Result[vm.HostCapabilities, vm.Failure] = vm.HostWithTimedMessaging(
		vm.TimedMessagingEffects{
		Messaging: vm.MessagingEffects{
		Send: func(destination term.Term, message term.Term) vm.SendOutcome {
			match term.TermPIDValue(destination) {
			case option.Some(pid):
				match context.Send(pid, message) {
				case kernel.Delivered:
					return vm.MessageSent(message)
				case kernel.NoProcess:
					return vm.MessageSent(message)
				}
			case option.None:
				match term.TermReferenceValue(destination) {
				case option.None:
					return vm.SendRejected("destination is not a PID or alias")
				case option.Some(reference):
					match context.SendAlias(reference, message) {
					case kernel.Delivered:
						return vm.MessageSent(message)
					case kernel.NoProcess:
						return vm.MessageSent(message)
					}
				}
			}
		},
			Receive: vm.ReceiveEffects{
			Peek: func() vm.ReceiveOutcome { return process.peekMessage(context) },
			Advance: process.advanceMessage,
				Remove: process.removeMessage,
			},
			},
			Timer: vm.TimerEffects{
			Wait: func(delay time.Duration) vm.TimerWaitOutcome { return process.waitTimer(context, delay) },
			Cancel: process.cancelTimer,
				Finish: process.finishTimer,
				},
			},
	)
	match checked {
	case result.Err(cause):
		return process.fail(cause.Error())
	case result.Ok(host):
		if process.callRegistry != nil {
			match vm.HostGrantExternalCalls(host, func(target vm.ExternalFunction, arguments []term.Term) vm.ExternalCallOutcome {
				return process.contextualCall(context, target, arguments)
			}) {
			case result.Err(cause):
				return process.fail(cause.Error())
			case result.Ok(granted):
				host = granted
			}
		}
		var resumed result.Result[vm.ExecutionSlice, vm.Failure] = process.continuation.ResumeWithHost(
			process.quantum,
			host,
		)
	match resumed {
	case result.Err(cause):
		return process.failVM(cause)
	case result.Ok(slice):
		var execution vm.ExecutionSlice = slice
		match execution {
		case vm.ExecutionSuspended(progress):
			process.reductions += progress.Reductions
			process.instructions = progress.TotalInstructions
			var suspended VMProcessState = VMProcessSuspended(
				process.reductions,
				progress.TotalInstructions,
			)
			process.state = suspended
			return kernel.Yield()
		case vm.ExecutionWaiting(progress):
			process.reductions += progress.Reductions
			process.instructions = progress.TotalInstructions
			var waiting VMProcessState = VMProcessWaiting(
				process.reductions,
				progress.TotalInstructions,
			)
			process.state = waiting
			return kernel.Wait()
		case vm.ExecutionRaised(class, reason, progress):
			process.reductions += progress.Reductions
			process.instructions = progress.TotalInstructions
			var raised VMProcessState = VMProcessRaised(
				term.Clone(class),
				term.Clone(reason),
				process.reductions,
				progress.TotalInstructions,
			)
			process.state = raised
			process.receiveMessages.Release()
			return kernel.Stop(vmExceptionReason(class, reason))
		case vm.ExecutionCompleted(value, progress):
			process.reductions += progress.Reductions
			process.instructions = progress.TotalInstructions
			var completed VMProcessState = VMProcessCompleted(
				value,
				process.reductions,
				progress.TotalInstructions,
			)
			process.state = completed
			process.receiveMessages.Release()
			return kernel.Stop(term.MustAtom("normal"))
		}
	}
	}
}

// assayxport:unit gotp.erts.vm-process-exceptions
func (process *VMProcess) failVM(failure vm.Failure) kernel.StepResult {
	var checked vm.Failure = failure
	match checked {
	case vm.RaisedException(class, reason):
		var raised VMProcessState = VMProcessRaised(
			term.Clone(class),
			term.Clone(reason),
			process.reductions,
			process.instructions,
		)
		process.state = raised
		process.receiveMessages.Release()
		return kernel.Stop(vmExceptionReason(class, reason))
	case vm.InvalidConfiguration(_), vm.ImmediateOutOfRange(_), vm.HeapIndexOutOfRange(_, _), vm.MemoryFailure(_), vm.InvalidProgram(_), vm.RegisterOutOfRange(_, _), vm.UninitializedRegister(_, _), vm.MissingConstant(_, _), vm.MissingLabel(_), vm.StepLimitExceeded(_), vm.UnsupportedOpcode(_, _, _):
		return process.fail(failure.Error())
	}
}

func vmExceptionReason(class term.Term, reason term.Term) term.Term {
	return term.Tuple(
		term.MustAtom("gotp_exception"),
		term.Clone(class),
		term.Clone(reason),
	)
}

func (process *VMProcess) waitTimer(context *kernel.Context, delay time.Duration) vm.TimerWaitOutcome {
	if process.timer != nil {
		var status kernel.WakeTimerStatus = process.timer.Status()
		match status {
		case kernel.WakeTimerPending:
			return vm.TimerPending()
		case kernel.WakeTimerFired:
			return vm.TimerExpired()
		case kernel.WakeTimerCancelled:
			process.timer = nil
		}
	}
	match context.WakeTimerAfter(process.clock, delay) {
	case result.Err(failure):
		return vm.TimerRejected(failure.Error())
	case result.Ok(timer):
		process.timer = timer
		return vm.TimerPending()
	}
}

func (process *VMProcess) cancelTimer() vm.TimerMutation {
	if process.timer == nil {
		return vm.TimerUnchanged()
	}
	changed := process.timer.Stop()
	process.timer = nil
	if changed {
		return vm.TimerChanged()
	}
	return vm.TimerUnchanged()
}

func (process *VMProcess) finishTimer() vm.TimerMutation {
	changed := process.timer != nil || process.receiveCursor != 0
	process.timer = nil
	process.receiveCursor = 0
	if changed {
		return vm.TimerChanged()
	}
	return vm.TimerUnchanged()
}

// assayxport:unit gotp.erts.selective-receive
func (process *VMProcess) peekMessage(context *kernel.Context) vm.ReceiveOutcome {
	if process.receiveCursor < process.receiveMessages.Len() {
		match process.receiveMessages.At(process.receiveCursor) { case option.None: return vm.ReceiveEmpty(); case option.Some(envelope): return vm.ReceiveMessage(term.Clone(envelope.Message)) }
	}
	match context.ReceiveMessage(nil) {
	case option.None:
		return vm.ReceiveEmpty()
	case option.Some(envelope):
		stored := kernel.MessageEnvelope{
			Message: term.Clone(envelope.Message),
			From: envelope.From,
		}
		process.receiveMessages.Append(stored)
		return vm.ReceiveMessage(term.Clone(stored.Message))
	}
}

func (process *VMProcess) advanceMessage() vm.AdvanceOutcome {
	if process.receiveCursor >= process.receiveMessages.Len() {
		return vm.AdvanceRejected("no current message")
	}
	process.receiveCursor++
	return vm.ReceiveCursorAdvanced()
}

func (process *VMProcess) removeMessage() vm.RemoveOutcome {
	if process.receiveCursor >= process.receiveMessages.Len() {
		return vm.RemoveRejected("no current message")
	}
	match process.receiveMessages.Remove(process.receiveCursor) { case option.None: return vm.RemoveRejected("no current message"); case option.Some(_): }
	process.receiveCursor = 0
	return vm.ReceiveMessageRemoved()
}

func (process *VMProcess) fail(detail string) kernel.StepResult {
	var failed VMProcessState = VMProcessFailed(
		detail,
		process.reductions,
		process.instructions,
	)
	process.state = failed
	process.receiveMessages.Release()
	return kernel.Stop(vmFailureReason(detail))
}

func vmFailureReason(detail string) term.Term {
	return term.Tuple(
		term.MustAtom("gotp_vm_failure"),
		term.Binary([]byte(detail)),
	)
}
