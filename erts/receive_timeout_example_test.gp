package erts

import (
	"math/big"
	"testing"
	"time"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

func adapterTimeoutMachine(milliseconds int64) *vm.Machine {
	program := []beam.Instruction{
		{Opcode: beam.Opcode{Name: "label", Arity: 1}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(1)}}},
		{Opcode: beam.Opcode{Name: "loop_rec", Arity: 2}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(2)}, beam.XRegisterOperand{Index: big.NewInt(0)}}},
		{Opcode: beam.Opcode{Name: "label", Arity: 1}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(2)}}},
		{Opcode: beam.Opcode{Name: "wait_timeout", Arity: 2}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(1)}, beam.IntegerOperand{Value: big.NewInt(milliseconds)}}},
		{Opcode: beam.Opcode{Name: "timeout", Arity: 0}},
		{Opcode: beam.Opcode{Name: "move", Arity: 2}, Operands: []beam.Operand{beam.IntegerOperand{Value: big.NewInt(42)}, beam.XRegisterOperand{Index: big.NewInt(0)}}},
		{Opcode: beam.Opcode{Name: "return", Arity: 0}},
	}
	match vm.NewMachine(program, vm.MachineConfig{XRegisters: 2, StepLimit: 100}) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(machine):
		return machine
	}
}

func adapterMessageBeforeTimeoutMachine(milliseconds int64) *vm.Machine {
	program := []beam.Instruction{
		{Opcode: beam.Opcode{Name: "label", Arity: 1}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(1)}}},
		{Opcode: beam.Opcode{Name: "loop_rec", Arity: 2}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(2)}, beam.XRegisterOperand{Index: big.NewInt(0)}}},
		{Opcode: beam.Opcode{Name: "remove_message", Arity: 0}},
		{Opcode: beam.Opcode{Name: "move", Arity: 2}, Operands: []beam.Operand{beam.IntegerOperand{Value: big.NewInt(7)}, beam.XRegisterOperand{Index: big.NewInt(0)}}},
		{Opcode: beam.Opcode{Name: "return", Arity: 0}},
		{Opcode: beam.Opcode{Name: "label", Arity: 1}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(2)}}},
		{Opcode: beam.Opcode{Name: "wait_timeout", Arity: 2}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(1)}, beam.IntegerOperand{Value: big.NewInt(milliseconds)}}},
		{Opcode: beam.Opcode{Name: "timeout", Arity: 0}},
		{Opcode: beam.Opcode{Name: "move", Arity: 2}, Operands: []beam.Operand{beam.IntegerOperand{Value: big.NewInt(42)}, beam.XRegisterOperand{Index: big.NewInt(0)}}},
		{Opcode: beam.Opcode{Name: "return", Arity: 0}},
	}
	match vm.NewMachine(program, vm.MachineConfig{XRegisters: 2, StepLimit: 100}) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(machine):
		return machine
	}
}

// assayxport:law gotp.erts.receive-timeout-laws
func TestReceiveTimeoutUsesInjectedClock(t *testing.T) {
	source := clock.NewFake(time.Unix(1_000, 0))
	var process *VMProcess
	match NewVMProcessWithClock(adapterTimeoutMachine(10), 1, source) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(created):
		process = created
	}
	runtime := kernel.New(kernel.KernelConfig{})
	match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	runtime.Run(10)
	var waiting VMProcessState = process.State()
	match waiting {
	case VMProcessWaiting(_, _):
	case VMProcessRunning, VMProcessSuspended(_, _), VMProcessCompleted(_, _, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
		t.Fatalf("expected waiting state, got %T", waiting)
	}
	source.Advance(10*time.Millisecond - time.Nanosecond)
	runtime.Run(10)
	var early VMProcessState = process.State()
	match early {
	case VMProcessWaiting(_, _):
	case VMProcessRunning, VMProcessSuspended(_, _), VMProcessCompleted(_, _, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
		t.Fatalf("timer fired early: %T", early)
	}
	source.Advance(time.Nanosecond)
	runtime.Run(10)
	var completed VMProcessState = process.State()
	match completed {
	case VMProcessCompleted(value, _, _):
		if !term.Equal(value, term.Integer(42)) {
			t.Fatalf("unexpected value: %v", value)
		}
	case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
		t.Fatalf("expected completed state, got %T", completed)
	}
}

func TestSelectedMessageCancelsReceiveTimeout(t *testing.T) {
	source := clock.NewFake(time.Unix(2_000, 0))
	var process *VMProcess
	match NewVMProcessWithClock(adapterMessageBeforeTimeoutMachine(100), 1, source) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(created):
		process = created
	}
	runtime := kernel.New(kernel.KernelConfig{})
	var pid term.PID
	match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(spawned):
		pid = spawned
	}
	runtime.Run(10)
	runtime.Send(pid, pid, term.Integer(9))
	runtime.Run(10)
	var selected VMProcessState = process.State()
	match selected {
	case VMProcessCompleted(value, _, _):
		if !term.Equal(value, term.Integer(7)) {
			t.Fatalf("message branch returned %v", value)
		}
	case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
		t.Fatalf("message did not complete receive: %T", selected)
	}
	source.Advance(100 * time.Millisecond)
	runtime.Run(10)
	var afterDeadline VMProcessState = process.State()
	match afterDeadline {
	case VMProcessCompleted(value, _, _):
		if !term.Equal(value, term.Integer(7)) {
			t.Fatalf("cancelled timeout changed result to %v", value)
		}
	case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
		t.Fatalf("cancelled timeout resumed process: %T", afterDeadline)
	}
}
