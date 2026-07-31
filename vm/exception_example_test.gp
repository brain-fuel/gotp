package vm

import (
	"math/big"
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.vm.exception-propagation-laws
func TestExternalRaisePreservesTermsAndProgress(t *testing.T) {
	target := ExternalFunction{Module: "erlang", Function: "error", Arity: 1}
	program := []beam.Instruction{
		externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		externalCallInstruction("move", beam.AtomOperand{Index: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		externalCallInstruction("call_ext_only", beam.UnsignedOperand{Value: big.NewInt(1)}, beam.UnsignedOperand{Value: big.NewInt(0)}),
	}
	match NewMachine(program, MachineConfig{
		XRegisters: 1,
		Atoms: map[uint64]string{1: "badarg"},
		Imports: map[uint64]ExternalFunction{0: target},
	}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(machine):
		var continuation *Continuation
		match machine.Start(1) { case result.Err(failure): t.Fatal(failure); case result.Ok(value): continuation = value }
		var host HostCapabilities
		match HostGrantExternalCalls(NoHostCapabilities(), func(_ ExternalFunction, arguments []term.Term) ExternalCallOutcome {
			return ExternalCallRaised(term.MustAtom("error"), arguments[0])
		}) { case result.Err(failure): t.Fatal(failure); case result.Ok(value): host = value }
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
				case ExecutionRaised(class, reason, progress):
					if !term.Equal(class, term.MustAtom("error")) || !term.Equal(reason, term.MustAtom("badarg")) {
						t.Fatalf("raised = %v:%v", class, reason)
					}
					if progress.Reductions != 1 || progress.Instructions != 2 || progress.TotalInstructions != 2 {
						t.Fatalf("raised progress = %#v", progress)
					}
				case ExecutionSuspended(_), ExecutionWaiting(_), ExecutionCompleted(_, _):
					t.Fatalf("raised execution = %T", execution)
				}
			}
		}
	}
}

func TestFuncInfoRaisesFunctionClause(t *testing.T) {
	program := []beam.Instruction{
		externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		externalCallInstruction("jump", beam.LabelOperand{Index: big.NewInt(2)}),
		externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(2)}),
		externalCallInstruction("func_info", beam.AtomOperand{Index: big.NewInt(1)}, beam.AtomOperand{Index: big.NewInt(2)}, beam.UnsignedOperand{Value: big.NewInt(0)}),
	}
	match NewMachine(program, MachineConfig{Atoms: map[uint64]string{1: "demo", 2: "f"}}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(machine):
		match machine.Run(1) {
		case result.Ok(_):
			t.Fatal("func_info fall-through completed")
		case result.Err(failure):
			var checked Failure = failure
			match checked {
			case RaisedException(class, reason):
				if !term.Equal(class, term.MustAtom("error")) || !term.Equal(reason, term.MustAtom("function_clause")) {
					t.Fatalf("func_info raised = %v:%v", class, reason)
				}
			case InvalidConfiguration(_), ImmediateOutOfRange(_), HeapIndexOutOfRange(_, _), MemoryFailure(_), InvalidProgram(_), RegisterOutOfRange(_, _), UninitializedRegister(_, _), MissingConstant(_, _), MissingLabel(_), StepLimitExceeded(_), UnsupportedOpcode(_, _, _):
				t.Fatalf("func_info failure = %v", failure)
			}
		}
	}
}
