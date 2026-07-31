package vm

import (
	"math/big"
	"strings"
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

func TestMachineRunsLocalCallAndRegisterMoves(t *testing.T) {
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("move", integer(42), xregister(0)),
		instruction("call", unsigned(0), label(2)),
		instruction("return"),
		instruction("label", label(2)),
		instruction("move", xregister(0), xregister(1)),
		instruction("return"),
		instruction("int_code_end"),
	}
	match NewMachine(program, MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match machine.Run(1) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(run):
			assertIntegerOperand(t, run.Value, 42)
		}
		match machine.X(1) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(value):
			assertIntegerOperand(t, value, 42)
		}
	}
}

func TestMachineSupportsTailCall(t *testing.T) {
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("move", integer(9), xregister(0)),
		instruction("call_only", unsigned(0), label(2)),
		instruction("label", label(2)),
		instruction("return"),
	}
	match NewMachine(program, MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match machine.Run(1) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(run):
			assertIntegerOperand(t, run.Value, 9)
		}
	}
}

func TestMachineBoundsInfiniteControlFlow(t *testing.T) {
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("jump", label(1)),
	}
	match NewMachine(program, MachineConfig{StepLimit: 10}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match machine.Run(1) {
		case result.Err(failure):
			if !strings.Contains(failure.Error(), "step limit") {
				t.Fatalf("failure = %s", failure.Error())
			}
		case result.Ok(_):
			t.Fatal("infinite control flow completed")
		}
	}
}

func TestMachineRejectsUnsupportedOpcode(t *testing.T) {
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("bif0"),
	}
	match NewMachine(program, MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match machine.Run(1) {
		case result.Err(failure):
			if !strings.Contains(failure.Error(), "not implemented") {
				t.Fatalf("failure = %s", failure.Error())
			}
		case result.Ok(_):
			t.Fatal("unsupported opcode completed")
		}
	}
}

func assertIntegerOperand(t *testing.T, value term.Term, want int64) {
	t.Helper()
	match term.Int64(value) {
	case option.Some(found):
		if found != want { t.Fatalf("integer = %d, want %d", found, want) }
	case option.None:
		t.Fatal("runtime value is not an integer")
	}
}

func TestMachineRegistersStoreRuntimeTerms(t *testing.T) {
	match NewMachine([]beam.Instruction{}, MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		pid := term.PID{Node: 1, Number: 7, Creation: 1}
		match machine.SetX(0, term.PIDValue(pid)) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(_):
			match machine.X(0) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(value):
				match term.TermPIDValue(value) {
				case option.Some(found):
					if found != pid { t.Fatalf("PID = %#v", found) }
				case option.None:
					t.Fatal("register value is not a PID")
				}
			}
		}
	}
}

func instruction(name string, operands ...beam.Operand) beam.Instruction {
	return beam.Instruction{
		Opcode: beam.Opcode{Name: name, Arity: len(operands)}, Operands: operands,
	}
}

func unsigned(value int64) beam.Operand {
	return beam.UnsignedOperand(big.NewInt(value))
}

func integer(value int64) beam.Operand {
	return beam.IntegerOperand(big.NewInt(value))
}

func label(value int64) beam.Operand {
	return beam.LabelOperand(big.NewInt(value))
}

func xregister(value int64) beam.Operand {
	return beam.XRegisterOperand(big.NewInt(value))
}
