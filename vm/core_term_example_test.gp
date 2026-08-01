package vm

import (
	"fmt"
	"math/big"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

func coreInstruction(name string, operands ...beam.Operand) beam.Instruction {
	return beam.Instruction{Opcode: beam.Opcode{Name: name, Arity: len(operands)}, Operands: operands}
}

// assayxport:law gotp.vm.core-term-laws
func TestPutThenGetListLaw(t *testing.T) {
	law := func(rawHead int16, rawTail []int8) bool {
		tailElements := make([]term.Term, len(rawTail))
		for index, value := range rawTail {
			tailElements[index] = term.Integer(int64(value))
		}
		program := []beam.Instruction{
			coreInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
			coreInstruction("put_list", beam.XRegisterOperand{Index: big.NewInt(0)}, beam.XRegisterOperand{Index: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(2)}),
			coreInstruction("get_list", beam.XRegisterOperand{Index: big.NewInt(2)}, beam.XRegisterOperand{Index: big.NewInt(3)}, beam.XRegisterOperand{Index: big.NewInt(4)}),
			coreInstruction("return"),
		}
		var machine *Machine
		match NewMachine(program, MachineConfig{XRegisters: 5, StepLimit: 20}) {
		case result.Err(_):
			return false
		case result.Ok(created):
			machine = created
		}
		head := term.Integer(int64(rawHead))
		tail := term.List(tailElements...)
		match machine.SetX(0, head) {
		case result.Err(_):
			return false
		case result.Ok(MachineMutated):
		}
		match machine.SetX(1, tail) {
		case result.Err(_):
			return false
		case result.Ok(MachineMutated):
		}
		match machine.Run(1) {
		case result.Err(_):
			return false
		case result.Ok(_):
		}
		match machine.X(3) {
		case result.Err(_):
			return false
		case result.Ok(found):
			if !term.Equal(found, head) {
				return false
			}
		}
		match machine.X(4) {
		case result.Err(_):
			return false
		case result.Ok(found):
			return term.Equal(found, tail)
		}
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 500})) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}

// ExampleMachine_updateRecord documents OTP's one-based record-field update semantics.
func ExampleMachine_updateRecord() {
	program := []beam.Instruction{
		coreInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		coreInstruction("update_record",
			beam.AtomOperand{Index: big.NewInt(1)},
			beam.UnsignedOperand{Value: big.NewInt(3)},
			beam.XRegisterOperand{Index: big.NewInt(0)},
			beam.XRegisterOperand{Index: big.NewInt(1)},
			beam.ListOperand{Items: []beam.Operand{
				beam.UnsignedOperand{Value: big.NewInt(3)}, beam.XRegisterOperand{Index: big.NewInt(2)},
			}},
		),
		coreInstruction("return"),
	}
	var machine *Machine
	match NewMachine(program, MachineConfig{XRegisters: 3, StepLimit: 10, Atoms: map[uint64]string{1: "copy"}}) {
	case result.Err(failure): panic(failure)
	case result.Ok(created): machine = created
	}
	match machine.SetX(0, term.Tuple(term.MustAtom("state"), term.Integer(1), term.Integer(2))) { case result.Err(failure): panic(failure); case result.Ok(MachineMutated): }
	match machine.SetX(2, term.Integer(9)) { case result.Err(failure): panic(failure); case result.Ok(MachineMutated): }
	match machine.Run(1) { case result.Err(failure): panic(failure); case result.Ok(_): }
	expected := term.Tuple(term.MustAtom("state"), term.Integer(1), term.Integer(9))
	match machine.X(1) { case result.Err(failure): panic(failure); case result.Ok(found): fmt.Println(term.Equal(found, expected)) }
	// Output: true
}

// assayxport:law gotp.vm.update-record-laws
func TestUpdateRecordReplacementAndSourceImmutabilityLaw(t *testing.T) {
	law := func(first, second, replacementA, replacementB int16) bool {
		program := []beam.Instruction{
			coreInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
			coreInstruction("update_record",
				beam.AtomOperand{Index: big.NewInt(1)},
				beam.UnsignedOperand{Value: big.NewInt(4)},
				beam.XRegisterOperand{Index: big.NewInt(0)},
				beam.XRegisterOperand{Index: big.NewInt(1)},
				beam.ListOperand{Items: []beam.Operand{
					beam.UnsignedOperand{Value: big.NewInt(2)}, beam.XRegisterOperand{Index: big.NewInt(2)},
					beam.UnsignedOperand{Value: big.NewInt(4)}, beam.XRegisterOperand{Index: big.NewInt(3)},
				}},
			),
			coreInstruction("return"),
		}
		match NewMachine(program, MachineConfig{XRegisters: 4, StepLimit: 10, Atoms: map[uint64]string{1: "copy"}}) {
		case result.Err(_): return false
		case result.Ok(machine):
			source := term.Tuple(term.MustAtom("state"), term.Integer(int64(first)), term.Integer(int64(second)), term.Integer(0))
			match machine.SetX(0, source) { case result.Err(_): return false; case result.Ok(MachineMutated): }
			match machine.SetX(2, term.Integer(int64(replacementA))) { case result.Err(_): return false; case result.Ok(MachineMutated): }
			match machine.SetX(3, term.Integer(int64(replacementB))) { case result.Err(_): return false; case result.Ok(MachineMutated): }
			match machine.Run(1) { case result.Err(_): return false; case result.Ok(_): }
			match machine.X(0) {
			case result.Err(_): return false
			case result.Ok(found): if !term.Equal(found, source) { return false }
			}
			expected := term.Tuple(term.MustAtom("state"), term.Integer(int64(replacementA)), term.Integer(int64(second)), term.Integer(int64(replacementB)))
			match machine.X(1) { case result.Err(_): return false; case result.Ok(found): return term.Equal(found, expected) }
		}
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 500})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}

func TestTupleArityAndValueSelection(t *testing.T) {
	program := []beam.Instruction{
		coreInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		coreInstruction("test_arity", beam.LabelOperand{Index: big.NewInt(3)}, beam.XRegisterOperand{Index: big.NewInt(0)}, beam.UnsignedOperand{Value: big.NewInt(2)}),
		coreInstruction("get_tuple_element", beam.XRegisterOperand{Index: big.NewInt(0)}, beam.UnsignedOperand{Value: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(1)}),
		coreInstruction("select_val", beam.XRegisterOperand{Index: big.NewInt(1)}, beam.LabelOperand{Index: big.NewInt(3)}, beam.ListOperand{Items: []beam.Operand{
			beam.IntegerOperand{Value: big.NewInt(42)}, beam.LabelOperand{Index: big.NewInt(2)},
		}}),
		coreInstruction("label", beam.LabelOperand{Index: big.NewInt(2)}),
		coreInstruction("move", beam.AtomOperand{Index: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		coreInstruction("return"),
		coreInstruction("label", beam.LabelOperand{Index: big.NewInt(3)}),
		coreInstruction("move", beam.AtomOperand{Index: big.NewInt(2)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		coreInstruction("return"),
	}
	match NewMachine(program, MachineConfig{
		XRegisters: 2,
		StepLimit: 20,
		Atoms: map[uint64]string{1: "ok", 2: "error"},
	}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(machine):
		match machine.SetX(0, term.Tuple(term.MustAtom("tag"), term.Integer(42))) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(MachineMutated):
		}
		match machine.Run(1) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(run):
			if !term.Equal(run.Value, term.MustAtom("ok")) {
				t.Fatalf("selection result = %v", run.Value)
			}
		}
	}
}

func TestNumericEqualityDoesNotRoundLargeInteger(t *testing.T) {
	integer := new(big.Int).SetUint64(9_007_199_254_740_993)
	if integerFloatEqual(integer, 9_007_199_254_740_992.0) {
		t.Fatal("large integer compared equal through float rounding")
	}
}
