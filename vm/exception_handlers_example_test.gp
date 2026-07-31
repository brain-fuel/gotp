package vm

import (
	"math/big"
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

func exceptionInstruction(name string, operands ...beam.Operand) beam.Instruction {
	return beam.Instruction{Opcode: beam.Opcode{Name: name, Arity: len(operands)}, Operands: operands}
}

func exceptionProgramResult(t *testing.T, program []beam.Instruction, atoms map[uint64]string) term.Term {
	match NewMachine(program, MachineConfig{XRegisters: 3, Atoms: atoms}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(machine):
		match machine.Run(1) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(run):
			return run.Value
		}
	}
	panic("unreachable")
}

// assayxport:law gotp.vm.exception-handler-laws
func TestTryCaseReceivesClassReasonAndTrace(t *testing.T) {
	program := []beam.Instruction{
		exceptionInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		exceptionInstruction("allocate", beam.UnsignedOperand{Value: big.NewInt(1)}, beam.UnsignedOperand{Value: big.NewInt(0)}),
		exceptionInstruction("try", beam.YRegisterOperand{Index: big.NewInt(0)}, beam.LabelOperand{Index: big.NewInt(2)}),
		exceptionInstruction("case_end", beam.AtomOperand{Index: big.NewInt(1)}),
		exceptionInstruction("try_end", beam.YRegisterOperand{Index: big.NewInt(0)}),
		exceptionInstruction("label", beam.LabelOperand{Index: big.NewInt(2)}),
		exceptionInstruction("try_case", beam.YRegisterOperand{Index: big.NewInt(0)}),
		exceptionInstruction("move", beam.XRegisterOperand{Index: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		exceptionInstruction("deallocate", beam.UnsignedOperand{Value: big.NewInt(1)}),
		exceptionInstruction("return"),
	}
	want := term.Tuple(term.MustAtom("case_clause"), term.MustAtom("missing"))
	if got := exceptionProgramResult(t, program, map[uint64]string{1: "missing"}); !term.Equal(got, want) {
		t.Fatalf("try reason = %v, want %v", got, want)
	}
}

func TestCatchTranslatesThrowExitAndError(t *testing.T) {
	cases := []struct {
		name string
		class string
		want term.Term
	}{
		{name: "throw", class: "throw", want: term.MustAtom("reason")},
		{name: "exit", class: "exit", want: term.Tuple(term.MustAtom("EXIT"), term.MustAtom("reason"))},
		{name: "error", class: "error", want: term.Tuple(term.MustAtom("EXIT"), term.Tuple(term.MustAtom("reason"), term.List()))},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			program := []beam.Instruction{
				exceptionInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
				exceptionInstruction("allocate", beam.UnsignedOperand{Value: big.NewInt(1)}, beam.UnsignedOperand{Value: big.NewInt(0)}),
				exceptionInstruction("catch", beam.YRegisterOperand{Index: big.NewInt(0)}, beam.LabelOperand{Index: big.NewInt(2)}),
				exceptionInstruction("move", beam.AtomOperand{Index: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
				exceptionInstruction("raise", beam.UnsignedOperand{Value: big.NewInt(0)}, beam.AtomOperand{Index: big.NewInt(2)}),
				exceptionInstruction("label", beam.LabelOperand{Index: big.NewInt(2)}),
				exceptionInstruction("catch_end", beam.YRegisterOperand{Index: big.NewInt(0)}),
				exceptionInstruction("deallocate", beam.UnsignedOperand{Value: big.NewInt(1)}),
				exceptionInstruction("return"),
			}
			if got := exceptionProgramResult(t, program, map[uint64]string{1: test.class, 2: "reason"}); !term.Equal(got, test.want) {
				t.Fatalf("catch %s = %v, want %v", test.class, got, test.want)
			}
		})
	}
}

func TestInactiveInnerHandlerUnwindsToOuterHandler(t *testing.T) {
	program := []beam.Instruction{
		exceptionInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		exceptionInstruction("allocate", beam.UnsignedOperand{Value: big.NewInt(2)}, beam.UnsignedOperand{Value: big.NewInt(0)}),
		exceptionInstruction("try", beam.YRegisterOperand{Index: big.NewInt(0)}, beam.LabelOperand{Index: big.NewInt(3)}),
		exceptionInstruction("try", beam.YRegisterOperand{Index: big.NewInt(1)}, beam.LabelOperand{Index: big.NewInt(2)}),
		exceptionInstruction("case_end", beam.AtomOperand{Index: big.NewInt(1)}),
		exceptionInstruction("label", beam.LabelOperand{Index: big.NewInt(2)}),
		exceptionInstruction("badmatch", beam.AtomOperand{Index: big.NewInt(2)}),
		exceptionInstruction("label", beam.LabelOperand{Index: big.NewInt(3)}),
		exceptionInstruction("try_case", beam.YRegisterOperand{Index: big.NewInt(0)}),
		exceptionInstruction("move", beam.XRegisterOperand{Index: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		exceptionInstruction("deallocate", beam.UnsignedOperand{Value: big.NewInt(2)}),
		exceptionInstruction("return"),
	}
	want := term.Tuple(term.MustAtom("badmatch"), term.MustAtom("outer"))
	if got := exceptionProgramResult(t, program, map[uint64]string{1: "inner", 2: "outer"}); !term.Equal(got, want) {
		t.Fatalf("nested reason = %v, want %v", got, want)
	}
}
