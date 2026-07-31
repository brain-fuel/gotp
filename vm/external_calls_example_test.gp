package vm

import (
	"fmt"
	"math/big"
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

func externalCallInstruction(name string, operands ...beam.Operand) beam.Instruction {
	return beam.Instruction{Opcode: beam.Opcode{Name: name, Arity: len(operands)}, Operands: operands}
}

func doubleExternalCall(target ExternalFunction, arguments []term.Term) ExternalCallOutcome {
	if target != (ExternalFunction{Module: "demo_math", Function: "double", Arity: 1}) {
		return ExternalCallRejected("unexpected target")
	}
	match term.Int64(arguments[0]) {
	case option.None:
		return ExternalCallRejected("argument is not int64")
	case option.Some(value):
		return ExternalCallReturned(term.Integer(value * 2))
	}
}

func externalCallHost() HostCapabilities {
	match HostGrantExternalCalls(
		NoHostCapabilities(),
		doubleExternalCall,
	) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(host):
		return host
	}
}

func externalCallMachine(program []beam.Instruction) *Machine {
	match NewMachine(program, MachineConfig{
		XRegisters: 2,
		StepLimit: 100,
		Imports: map[uint64]ExternalFunction{
			0: {Module: "demo_math", Function: "double", Arity: 1},
		},
	}) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(machine):
		return machine
	}
}

// ExampleHostGrantExternalCalls is the explicit external-call capability example.
func ExampleHostGrantExternalCalls() {
	program := []beam.Instruction{
		externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		externalCallInstruction("move", beam.IntegerOperand{Value: big.NewInt(7)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		externalCallInstruction("call_ext_only", beam.UnsignedOperand{Value: big.NewInt(1)}, beam.UnsignedOperand{Value: big.NewInt(0)}),
	}
	machine := externalCallMachine(program)
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
		match continuation.ResumeWithHost(budget, externalCallHost()) {
		case result.Err(failure):
			panic(failure.Error())
		case result.Ok(slice):
			var execution ExecutionSlice = slice
			match execution {
			case ExecutionCompleted(value, progress):
				match term.Int64(value) {
				case option.None:
					panic("expected integer")
				case option.Some(integer):
					fmt.Println(integer, progress.Reductions)
				}
			case ExecutionSuspended(_), ExecutionWaiting(_):
				panic("external tail call did not complete")
			}
		}
	}
	// Output:
	// 14 1
}

// assayxport:law gotp.vm.external-call-laws
func TestExternalCallAndReturnEachConsumeReduction(t *testing.T) {
	program := []beam.Instruction{
		externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		externalCallInstruction("move", beam.IntegerOperand{Value: big.NewInt(7)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		externalCallInstruction("call_ext", beam.UnsignedOperand{Value: big.NewInt(1)}, beam.UnsignedOperand{Value: big.NewInt(0)}),
		externalCallInstruction("return"),
	}
	machine := externalCallMachine(program)
	var continuation *Continuation
	match machine.Start(1) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(started):
		continuation = started
	}
	var budget VMReductionBudget
	match NewVMReductionBudget(1) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(checked):
		budget = checked
	}
	match continuation.ResumeWithHost(budget, externalCallHost()) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(slice):
		var execution ExecutionSlice = slice
		match execution {
		case ExecutionSuspended(progress):
			if progress.Reductions != 1 {
				t.Fatalf("external call reductions = %d", progress.Reductions)
			}
		case ExecutionWaiting(_), ExecutionCompleted(_, _):
			t.Fatal("external call did not suspend before return")
		}
	}
	match continuation.ResumeWithHost(budget, externalCallHost()) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(slice):
		var execution ExecutionSlice = slice
		match execution {
		case ExecutionCompleted(value, progress):
			if progress.Reductions != 1 || !term.Equal(value, term.Integer(14)) {
				t.Fatalf("return = %v, reductions = %d", value, progress.Reductions)
			}
		case ExecutionSuspended(_), ExecutionWaiting(_):
			t.Fatal("return did not complete")
		}
	}
}

func TestExternalTailCallDeallocatesFrame(t *testing.T) {
	program := []beam.Instruction{
		externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		externalCallInstruction("allocate", beam.UnsignedOperand{Value: big.NewInt(0)}, beam.UnsignedOperand{Value: big.NewInt(0)}),
		externalCallInstruction("move", beam.IntegerOperand{Value: big.NewInt(7)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		externalCallInstruction("call_ext_last", beam.UnsignedOperand{Value: big.NewInt(1)}, beam.UnsignedOperand{Value: big.NewInt(0)}, beam.UnsignedOperand{Value: big.NewInt(0)}),
	}
	machine := externalCallMachine(program)
	var continuation *Continuation
	match machine.Start(1) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(started):
		continuation = started
	}
	match NewVMReductionBudget(1) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(budget):
		match continuation.ResumeWithHost(budget, externalCallHost()) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(slice):
			var execution ExecutionSlice = slice
			match execution {
			case ExecutionCompleted(value, _):
				if !term.Equal(value, term.Integer(14)) {
					t.Fatalf("tail result = %v", value)
				}
			case ExecutionSuspended(_), ExecutionWaiting(_):
				t.Fatal("tail call did not complete")
			}
		}
	}
}
