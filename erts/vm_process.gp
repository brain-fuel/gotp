package erts

import (
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

type AdapterFailure enum {
	NilMachine()
	VMStartFailure(Cause vm.Failure)
	VMBudgetFailure(Cause vm.Failure)
}

func (failure AdapterFailure) Error() string {
	match failure {
	case NilMachine:
		return "gotp/erts: VM machine is nil"
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
	VMProcessFailed(Detail string, TotalReductions int, TotalInstructions int)
}

type VMProcess struct {
	continuation *vm.Continuation
	quantum      vm.VMReductionBudget
	state        VMProcessState
	reductions   int
	instructions int
	receiveMessages []kernel.MessageEnvelope
	receiveCursor int
}

// assayxport:unit gotp.erts.vm-process
func NewVMProcess(
	machine *vm.Machine,
	entryLabel uint64,
) result.Result[*VMProcess, AdapterFailure] {
	if machine == nil {
		return result.Err[*VMProcess, AdapterFailure](NilMachine())
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
	case VMProcessFailed(detail, _, _):
		return kernel.Stop(vmFailureReason(detail))
	}
}

func (process *VMProcess) resume(context *kernel.Context) kernel.StepResult {
	var checked result.Result[vm.HostCapabilities, vm.Failure] = vm.HostWithMessaging(
		vm.MessagingEffects{
		Send: func(destination term.Term, message term.Term) vm.SendOutcome {
			match term.TermPIDValue(destination) {
			case option.None:
				return vm.SendRejected("destination is not a PID")
			case option.Some(pid):
				match context.Send(pid, message) {
				case kernel.Delivered:
					return vm.MessageSent(message)
				case kernel.NoProcess:
					return vm.MessageSent(message)
				}
			}
		},
		Receive: vm.ReceiveEffects{
			Peek: func() vm.ReceiveOutcome { return process.peekMessage(context) },
			Advance: process.advanceMessage,
			Remove: process.removeMessage,
		},
		},
	)
	match checked {
	case result.Err(cause):
		return process.fail(cause.Error())
	case result.Ok(host):
		var resumed result.Result[vm.ExecutionSlice, vm.Failure] = process.continuation.ResumeWithHost(
			process.quantum,
			host,
		)
	match resumed {
	case result.Err(cause):
		return process.fail(cause.Error())
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
		case vm.ExecutionCompleted(value, progress):
			process.reductions += progress.Reductions
			process.instructions = progress.TotalInstructions
			var completed VMProcessState = VMProcessCompleted(
				value,
				process.reductions,
				progress.TotalInstructions,
			)
			process.state = completed
			return kernel.Stop(term.MustAtom("normal"))
		}
	}
	}
}

// assayxport:unit gotp.erts.selective-receive
func (process *VMProcess) peekMessage(context *kernel.Context) vm.ReceiveOutcome {
	if process.receiveCursor < len(process.receiveMessages) {
		return vm.ReceiveMessage(term.Clone(
			process.receiveMessages[process.receiveCursor].Message,
		))
	}
	match context.ReceiveMessage(nil) {
	case option.None:
		return vm.ReceiveEmpty()
	case option.Some(envelope):
		stored := kernel.MessageEnvelope{
			Message: term.Clone(envelope.Message),
			From: envelope.From,
		}
		process.receiveMessages = append(process.receiveMessages, stored)
		return vm.ReceiveMessage(term.Clone(stored.Message))
	}
}

func (process *VMProcess) advanceMessage() vm.AdvanceOutcome {
	if process.receiveCursor >= len(process.receiveMessages) {
		return vm.AdvanceRejected("no current message")
	}
	process.receiveCursor++
	return vm.ReceiveCursorAdvanced()
}

func (process *VMProcess) removeMessage() vm.RemoveOutcome {
	if process.receiveCursor >= len(process.receiveMessages) {
		return vm.RemoveRejected("no current message")
	}
	copy(
		process.receiveMessages[process.receiveCursor:],
		process.receiveMessages[process.receiveCursor+1:],
	)
	process.receiveMessages = process.receiveMessages[:len(process.receiveMessages)-1]
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
	return kernel.Stop(vmFailureReason(detail))
}

func vmFailureReason(detail string) term.Term {
	return term.Tuple(
		term.MustAtom("gotp_vm_failure"),
		term.Binary([]byte(detail)),
	)
}
