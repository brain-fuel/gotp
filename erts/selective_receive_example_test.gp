package erts

import (
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

// assayxport:unit gotp.erts.selective-receive-laws
func TestVMSelectiveReceivePreservesSkippedMessage(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{})
	program := []beam.Instruction{
		vmInstruction("label", vmLabel(1)),
		vmInstruction("loop_rec", vmLabel(3), vmXRegister(0)),
		vmInstruction("loop_rec_end", vmLabel(2)),
		vmInstruction("label", vmLabel(2)),
		vmInstruction("loop_rec", vmLabel(3), vmXRegister(0)),
		vmInstruction("remove_message"),
		vmInstruction("return"),
		vmInstruction("label", vmLabel(3)),
		vmInstruction("wait", vmLabel(1)),
	}
	match vm.NewMachine(program, vm.MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match NewVMProcess(machine, 1) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(process):
			match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(pid):
				runtime.Send(pid, pid, term.Integer(1))
				runtime.Send(pid, pid, term.Integer(2))
				runtime.RunSlice(mustKernelBudget(t, 2))
				var state VMProcessState = process.State()
				match state {
				case VMProcessCompleted(value, reductions, _):
					if !term.Equal(value, term.Integer(2)) || reductions != 2 {
						t.Fatalf("value=%#v reductions=%d", value, reductions)
					}
				case _:
					t.Fatal("selective receive VM did not complete")
				}
				if process.receiveMessages.Len() != 0 || process.receiveMessages.Cap() != 0 { t.Fatalf("terminal receive memory=%d/%d", process.receiveMessages.Len(), process.receiveMessages.Cap()) }
			}
		}
	}
}

func TestWaitingVMWakesOnNewMessage(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{})
	program := []beam.Instruction{
		vmInstruction("label", vmLabel(1)),
		vmInstruction("loop_rec", vmLabel(2), vmXRegister(0)),
		vmInstruction("remove_message"),
		vmInstruction("return"),
		vmInstruction("label", vmLabel(2)),
		vmInstruction("wait", vmLabel(1)),
	}
	match vm.NewMachine(program, vm.MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match NewVMProcess(machine, 1) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(process):
			match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(pid):
				runtime.RunSlice(mustKernelBudget(t, 1))
				match runtime.ProcessInfo(pid) {
				case option.None: t.Fatal("waiting VM disappeared")
				case option.Some(info):
					match info.Status {
					case kernel.Waiting:
					case _: t.Fatal("empty receive did not wait")
					}
				}
				runtime.Send(pid, pid, term.Integer(77))
				runtime.RunSlice(mustKernelBudget(t, 1))
				var state VMProcessState = process.State()
				match state {
				case VMProcessCompleted(value, _, _):
					if !term.Equal(value, term.Integer(77)) { t.Fatal("woken VM received wrong message") }
				case _: t.Fatal("message did not wake and complete VM")
				}
			}
		}
	}
}
