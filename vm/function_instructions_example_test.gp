package vm

import (
	"math/big"
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.vm.function-instruction-laws
func TestMakeFun3CapturesAndCallFunRestoresCaller(t *testing.T) {
	program := []beam.Instruction{
		externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		externalCallInstruction("move", beam.IntegerOperand{Value: big.NewInt(10)}, beam.XRegisterOperand{Index: big.NewInt(1)}),
		externalCallInstruction(
			"make_fun3",
			beam.UnsignedOperand{Value: big.NewInt(0)},
			beam.XRegisterOperand{Index: big.NewInt(1)},
			beam.ListOperand{Items: []beam.Operand{beam.XRegisterOperand{Index: big.NewInt(1)}}},
		),
		externalCallInstruction("move", beam.IntegerOperand{Value: big.NewInt(5)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		externalCallInstruction("call_fun", beam.UnsignedOperand{Value: big.NewInt(1)}),
		externalCallInstruction("return"),
		externalCallInstruction("label", beam.LabelOperand{Index: big.NewInt(2)}),
		externalCallInstruction("move", beam.XRegisterOperand{Index: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		externalCallInstruction("return"),
	}
	match NewMachine(program, MachineConfig{
		XRegisters: 3,
		StepLimit: 20,
		ModuleName: "closure_demo",
		Functions: map[uint64]beam.FunctionTemplate{
			0: {Function: "captured", Arity: 1, Label: 2, Index: 0, Free: 1, Unique: 7},
		},
	}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(machine):
		match machine.Run(1) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(run):
			if !term.Equal(run.Value, term.Integer(10)) {
				t.Fatalf("captured result = %v", run.Value)
			}
		}
	}
}
