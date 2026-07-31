package vm

import (
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

// assayxport:unit gotp.vm.selective-receive-laws
func TestSelectiveReceiveWaitsAndResumes(t *testing.T) {
	messages := []term.Term{}
	cursor := 0
	removed := 0
	host := mustReceiveHost(t, &messages, &cursor, &removed)
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("loop_rec", label(2), xregister(0)),
		instruction("remove_message"),
		instruction("return"),
		instruction("label", label(2)),
		instruction("wait", label(1)),
	}
	match NewMachine(program, MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match machine.Start(1) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(continuation):
			budget := mustVMReceiveBudget(t, 1)
			match continuation.ResumeWithHost(budget, host) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(slice):
				var execution ExecutionSlice = slice
				match execution {
				case ExecutionWaiting(_):
				case _:
					t.Fatal("empty receive did not wait")
				}
			}
			messages = append(messages, term.Integer(42))
			match continuation.ResumeWithHost(budget, host) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(slice):
				var execution ExecutionSlice = slice
				match execution {
				case ExecutionCompleted(value, _):
					if !term.Equal(value, term.Integer(42)) || removed != 1 {
						t.Fatalf("value=%#v removed=%d", value, removed)
					}
				case _:
					t.Fatal("resumed receive did not complete")
				}
			}
		}
	}
}

func TestLoopRecEndAdvancesAndConsumesReduction(t *testing.T) {
	messages := []term.Term{term.Integer(1), term.Integer(2)}
	cursor := 0
	removed := 0
	host := mustReceiveHost(t, &messages, &cursor, &removed)
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("loop_rec", label(3), xregister(0)),
		instruction("loop_rec_end", label(2)),
		instruction("label", label(2)),
		instruction("loop_rec", label(3), xregister(0)),
		instruction("remove_message"),
		instruction("return"),
		instruction("label", label(3)),
		instruction("wait", label(1)),
	}
	match NewMachine(program, MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match machine.Start(1) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(continuation):
			match continuation.ResumeWithHost(mustVMReceiveBudget(t, 2), host) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(slice):
				var execution ExecutionSlice = slice
				match execution {
				case ExecutionCompleted(value, progress):
					if !term.Equal(value, term.Integer(2)) || progress.Reductions != 2 ||
						len(messages) != 1 || !term.Equal(messages[0], term.Integer(1)) {
						t.Fatalf("value=%#v progress=%#v messages=%#v", value, progress, messages)
					}
				case _:
					t.Fatal("selective receive did not complete")
				}
			}
		}
	}
}

func mustReceiveHost(
	t *testing.T,
	messages *[]term.Term,
	cursor *int,
	removed *int,
) HostCapabilities {
	t.Helper()
	match HostWithReceive(ReceiveEffects{
		Peek: func() ReceiveOutcome {
			if *cursor >= len(*messages) { return ReceiveEmpty() }
			return ReceiveMessage(term.Clone((*messages)[*cursor]))
		},
		Advance: func() AdvanceOutcome {
			if *cursor >= len(*messages) { return AdvanceRejected("no current message") }
			(*cursor)++
			return ReceiveCursorAdvanced()
		},
		Remove: func() RemoveOutcome {
			if *cursor >= len(*messages) { return RemoveRejected("no current message") }
			copy((*messages)[*cursor:], (*messages)[*cursor+1:])
			*messages = (*messages)[:len(*messages)-1]
			*cursor = 0
			(*removed)++
			return ReceiveMessageRemoved()
		},
	}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
		return NoHostCapabilities()
	case result.Ok(host):
		return host
	}
}

func mustVMReceiveBudget(t *testing.T, value int) VMReductionBudget {
	t.Helper()
	match NewVMReductionBudget(value) {
	case result.Err(failure):
		t.Fatal(failure.Error())
		return VMReductionBudget{}
	case result.Ok(budget):
		return budget
	}
}
