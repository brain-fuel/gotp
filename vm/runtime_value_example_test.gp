package vm

import (
	"fmt"
	"math/big"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

func ExampleMachine_atomConstant() {
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("move", atomIndex(7), xregister(0)),
		instruction("return"),
	}
	match NewMachine(program, MachineConfig{Atoms: map[uint64]string{7: "ready"}}) {
	case result.Err(failure):
		fmt.Println(failure.Error())
	case result.Ok(machine):
		match machine.Run(1) {
		case result.Err(failure):
			fmt.Println(failure.Error())
		case result.Ok(run):
			match term.AtomName(run.Value) {
			case option.None:
				fmt.Println("not an atom")
			case option.Some(name):
				fmt.Println(name)
			}
		}
	}
	// Output:
	// ready
}

// assayxport:unit gotp.vm.runtime-value-laws
func TestIntegerOperandMaterializationProperty(t *testing.T) {
	property := func(value int64) bool {
		program := []beam.Instruction{
			instruction("label", label(1)),
			instruction("move", integer(value), xregister(0)),
			instruction("return"),
		}
		match NewMachine(program, MachineConfig{}) {
		case result.Err(_):
			return false
		case result.Ok(machine):
			match machine.Run(1) {
			case result.Err(_):
				return false
			case result.Ok(run):
				match term.Int64(run.Value) {
				case option.None:
					return false
				case option.Some(found):
					return found == value
				}
			}
		}
	}
	if failure := quick.Check(property, nil); failure != nil {
		t.Fatal(failure)
	}
}

func TestLiteralPoolPreservesTermEquality(t *testing.T) {
	want := term.Tuple(term.MustAtom("ok"), term.Integer(42))
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("move", literalIndex(3), xregister(0)),
		instruction("return"),
	}
	match NewMachine(program, MachineConfig{Literals: map[uint64]term.Term{3: want}}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match machine.Run(1) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(run):
			if !term.Equal(run.Value, want) { t.Fatal("literal changed during materialization") }
		}
	}
}

func TestMissingConstantIsTypedFailure(t *testing.T) {
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("move", atomIndex(99), xregister(0)),
		instruction("return"),
	}
	match NewMachine(program, MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match machine.Run(1) {
		case result.Ok(_):
			t.Fatal("missing atom constant was accepted")
		case result.Err(failure):
			var executionFailure Failure = failure
			match executionFailure {
			case MissingConstant(kind, index):
				if kind != "atom" || index != 99 { t.Fatalf("constant = %s/%d", kind, index) }
			case _:
				t.Fatalf("unexpected failure: %s", failure.Error())
			}
		}
	}
}

func atomIndex(value int64) beam.Operand {
	return beam.AtomOperand(big.NewInt(value))
}

func literalIndex(value int64) beam.Operand {
	return beam.LiteralOperand(big.NewInt(value))
}
