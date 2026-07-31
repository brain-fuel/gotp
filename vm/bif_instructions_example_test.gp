package vm

import (
	"math/big"
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.vm.bif-instruction-laws
func TestGCBIFFailureBranchesToDeclaredLabel(t *testing.T) {
	program := []beam.Instruction{
		externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		externalCallInstruction(
			"gc_bif2",
			beam.LabelOperand{Index: big.NewInt(2)},
			beam.UnsignedOperand{Value: big.NewInt(0)},
			beam.UnsignedOperand{Value: big.NewInt(0)},
			beam.IntegerOperand{Value: big.NewInt(1)},
			beam.IntegerOperand{Value: big.NewInt(0)},
			beam.XRegisterOperand{Index: big.NewInt(0)},
		),
		externalCallInstruction("move", beam.AtomOperand{Index: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		externalCallInstruction("return"),
		externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(2)}),
		externalCallInstruction("move", beam.AtomOperand{Index: big.NewInt(2)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		externalCallInstruction("return"),
	}
	match NewMachine(program, MachineConfig{
		XRegisters: 1,
		StepLimit: 20,
		Atoms: map[uint64]string{1: "continued", 2: "failed"},
		Imports: map[uint64]ExternalFunction{0: {Module: "erlang", Function: "div", Arity: 2}},
	}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(machine):
		var continuation *Continuation
		match machine.Start(1) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(started):
			continuation = started
		}
		var host HostCapabilities
		match HostGrantExternalCalls(NoHostCapabilities(), func(_ ExternalFunction, _ []term.Term) ExternalCallOutcome {
			return ExternalCallRejected("badarith")
		}) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(granted):
			host = granted
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
					if !term.Equal(value, term.MustAtom("failed")) {
						t.Fatalf("BIF failure branch = %v", value)
					}
				case ExecutionSuspended(_), ExecutionWaiting(_), ExecutionRaised(_, _, _):
					t.Fatalf("BIF failure execution = %T", execution)
				}
			}
		}
	}
}
