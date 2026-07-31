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
			case ExecutionSuspended(_), ExecutionWaiting(_), ExecutionRaised(_, _, _):
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
		case ExecutionWaiting(_), ExecutionRaised(_, _, _), ExecutionCompleted(_, _):
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
		case ExecutionSuspended(_), ExecutionWaiting(_), ExecutionRaised(_, _, _):
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
			case ExecutionSuspended(_), ExecutionWaiting(_), ExecutionRaised(_, _, _):
				t.Fatal("tail call did not complete")
			}
		}
	}
}

func linkedExternalMachine(tail bool) *Machine {
	call := "call_ext"
	if tail {
		call = "call_ext_only"
	}
	root := []beam.Instruction{
		externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		externalCallInstruction(call, beam.UnsignedOperand{Value: big.NewInt(0)}, beam.UnsignedOperand{Value: big.NewInt(0)}),
		externalCallInstruction("move", beam.AtomOperand{Index: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		externalCallInstruction("return"),
	}
	linkedTarget := ExternalFunction{Module: "linked", Function: "answer", Arity: 0}
	linked := ModuleImage{
		Name: "linked",
		Program: []beam.Instruction{
			externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(2)}),
			externalCallInstruction("move", beam.AtomOperand{Index: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
			externalCallInstruction("return"),
		},
		Atoms: map[uint64]string{1: "linked"},
		Exports: map[ExternalFunction]uint64{linkedTarget: 2},
	}
	match NewMachine(root, MachineConfig{
		XRegisters: 1,
		StepLimit: 20,
		Atoms: map[uint64]string{1: "caller"},
		Imports: map[uint64]ExternalFunction{0: linkedTarget},
		ModuleName: "caller",
		LinkedModules: map[string]ModuleImage{"linked": linked},
	}) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(machine):
		return machine
	}
}

func runLinkedExternalMachine(t *testing.T, machine *Machine, host HostCapabilities) term.Term {
	var continuation *Continuation
	match machine.Start(1) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(started):
		continuation = started
	}
	match NewVMReductionBudget(10) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(budget):
		match continuation.ResumeWithHost(budget, host) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(slice):
			var execution ExecutionSlice = slice
			match execution {
			case ExecutionCompleted(value, _):
				return value
			case ExecutionSuspended(_), ExecutionWaiting(_), ExecutionRaised(_, _, _):
				t.Fatalf("linked execution = %T", execution)
			}
		}
	}
	panic("unreachable")
}

// assayxport:law gotp.vm.module-continuation-laws
func TestLinkedCallRestoresCallerImage(t *testing.T) {
	value := runLinkedExternalMachine(t, linkedExternalMachine(false), NoHostCapabilities())
	if !term.Equal(value, term.MustAtom("caller")) {
		t.Fatalf("ordinary linked result = %v", value)
	}
}

func TestLinkedTailCallRetainsTargetImage(t *testing.T) {
	value := runLinkedExternalMachine(t, linkedExternalMachine(true), NoHostCapabilities())
	if !term.Equal(value, term.MustAtom("linked")) {
		t.Fatalf("tail linked result = %v", value)
	}
}

func TestNativeCallOverridesLinkedBeamExport(t *testing.T) {
	hostResult := HostGrantExternalCalls(NoHostCapabilities(), func(_ ExternalFunction, _ []term.Term) ExternalCallOutcome {
		return ExternalCallReturned(term.MustAtom("native"))
	})
	var host HostCapabilities
	match hostResult {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(granted):
		host = granted
	}
	value := runLinkedExternalMachine(t, linkedExternalMachine(true), host)
	if !term.Equal(value, term.MustAtom("native")) {
		t.Fatalf("native override result = %v", value)
	}
}

func TestUnboundNativeCallFallsBackToLinkedExport(t *testing.T) {
	hostResult := HostGrantExternalCalls(NoHostCapabilities(), func(_ ExternalFunction, _ []term.Term) ExternalCallOutcome {
		return ExternalCallUnbound()
	})
	var host HostCapabilities
	match hostResult {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(granted):
		host = granted
	}
	value := runLinkedExternalMachine(t, linkedExternalMachine(true), host)
	if !term.Equal(value, term.MustAtom("linked")) {
		t.Fatalf("linked fallback result = %v", value)
	}
}
