package vm

import (
	"fmt"
	"math/big"
	"testing"
	"testing/quick"
	"time"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

func receiveTimeoutProgram(milliseconds int64) []beam.Instruction {
	return []beam.Instruction{
		{Opcode: beam.Opcode{Name: "label", Arity: 1}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(1)}}},
		{Opcode: beam.Opcode{Name: "loop_rec", Arity: 2}, Operands: []beam.Operand{
			beam.LabelOperand{Index: big.NewInt(2)},
			beam.XRegisterOperand{Index: big.NewInt(0)},
		}},
		{Opcode: beam.Opcode{Name: "label", Arity: 1}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(2)}}},
		{Opcode: beam.Opcode{Name: "wait_timeout", Arity: 2}, Operands: []beam.Operand{
			beam.LabelOperand{Index: big.NewInt(1)},
			beam.IntegerOperand{Value: big.NewInt(milliseconds)},
		}},
		{Opcode: beam.Opcode{Name: "timeout", Arity: 0}},
		{Opcode: beam.Opcode{Name: "move", Arity: 2}, Operands: []beam.Operand{
			beam.IntegerOperand{Value: big.NewInt(42)},
			beam.XRegisterOperand{Index: big.NewInt(0)},
		}},
		{Opcode: beam.Opcode{Name: "return", Arity: 0}},
	}
}

func timeoutMachine(milliseconds int64) *Machine {
	match NewMachine(receiveTimeoutProgram(milliseconds), MachineConfig{XRegisters: 2, StepLimit: 100}) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(machine):
		return machine
	}
}

func timeoutHost(expired *bool, waited *time.Duration, finishes *int) HostCapabilities {
	match HostWithTimedMessaging(TimedMessagingEffects{
		Messaging: MessagingEffects{
			Send: func(_ term.Term, message term.Term) SendOutcome { return MessageSent(message) },
			Receive: ReceiveEffects{
				Peek: func() ReceiveOutcome { return ReceiveEmpty() },
				Advance: func() AdvanceOutcome { return AdvanceRejected("empty") },
				Remove: func() RemoveOutcome { return RemoveRejected("empty") },
			},
		},
		Timer: TimerEffects{
			Wait: func(delay time.Duration) TimerWaitOutcome {
				*waited = delay
				if *expired {
					return TimerExpired()
				}
				return TimerPending()
			},
			Cancel: func() TimerMutation { return TimerChanged() },
			Finish: func() TimerMutation {
				*finishes = *finishes + 1
				return TimerChanged()
			},
		},
	}) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(host):
		return host
	}
}

// ExampleContinuation_receiveTimeout is the deployable receive-timeout usage example.
func ExampleContinuation_receiveTimeout() {
	machine := timeoutMachine(25)
	var continuation *Continuation
	match machine.Start(1) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(started):
		continuation = started
	}
	match NewVMReductionBudget(1) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(budget):
		expired := false
		waited := time.Duration(0)
		finishes := 0
		host := timeoutHost(&expired, &waited, &finishes)
		match continuation.ResumeWithHost(budget, host) {
		case result.Err(failure):
			panic(failure.Error())
		case result.Ok(slice):
			var execution ExecutionSlice = slice
			match execution {
			case ExecutionWaiting(_), ExecutionRaised(_, _, _):
				fmt.Println(waited)
			case ExecutionSuspended(_), ExecutionCompleted(_, _):
				panic("expected wait")
			}
		}
		expired = true
		match continuation.ResumeWithHost(budget, host) {
		case result.Err(failure):
			panic(failure.Error())
		case result.Ok(slice):
			var execution ExecutionSlice = slice
			match execution {
			case ExecutionCompleted(value, _):
				match term.IntegerValue(value) {
				case option.Some(integer):
					fmt.Println(integer, finishes)
				case option.None:
					panic("expected integer")
				}
			case ExecutionSuspended(_), ExecutionWaiting(_), ExecutionRaised(_, _, _):
				panic("expected completion")
			}
		}
	}
	// Output:
	// 25ms
	// 42 1
}

// assayxport:law gotp.vm.receive-timeout-laws
func TestReceiveTimeoutDurationLaw(t *testing.T) {
	law := func(raw uint16) bool {
		milliseconds := int64(raw) + 1
		machine := timeoutMachine(milliseconds)
		var continuation *Continuation
		match machine.Start(1) {
		case result.Err(_):
			return false
		case result.Ok(started):
			continuation = started
		}
		var budget VMReductionBudget
		match NewVMReductionBudget(1) {
		case result.Err(_):
			return false
		case result.Ok(checked):
			budget = checked
		}
		expired := false
		waited := time.Duration(0)
		finishes := 0
		host := timeoutHost(&expired, &waited, &finishes)
		match continuation.ResumeWithHost(budget, host) {
		case result.Err(_):
			return false
		case result.Ok(slice):
			var execution ExecutionSlice = slice
			match execution {
			case ExecutionWaiting(_), ExecutionRaised(_, _, _):
			case ExecutionSuspended(_), ExecutionCompleted(_, _):
				return false
			}
		}
		if waited != time.Duration(milliseconds)*time.Millisecond {
			return false
		}
		expired = true
		match continuation.ResumeWithHost(budget, host) {
		case result.Err(_):
			return false
		case result.Ok(slice):
			var execution ExecutionSlice = slice
			match execution {
			case ExecutionCompleted(_, _):
				return finishes == 1
			case ExecutionSuspended(_), ExecutionWaiting(_), ExecutionRaised(_, _, _):
				return false
			}
		}
	}
	match result.Of(true, quick.Check(law, nil)) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}
