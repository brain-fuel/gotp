package vm

import (
	"math/big"
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.vm.register-memory-laws
func TestCompletedContinuationClearsProcessRegisters(t *testing.T) {
	program := []beam.Instruction{{Opcode: beam.Opcode{Name: "label", Arity: 1}, Operands: []beam.Operand{beam.LabelOperand{Index: big.NewInt(1)}}}, {Opcode: beam.Opcode{Name: "return", Arity: 0}}}
	match NewMachine(program, MachineConfig{XRegisters: 4}) { case result.Err(failure): t.Fatal(failure); case result.Ok(machine):
		match machine.SetX(0, term.Tuple(term.MustAtom("retained"), term.Binary([]byte("payload")))) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
		match machine.Start(1) { case result.Err(failure): t.Fatal(failure); case result.Ok(continuation): match continuation.Resume(VMReductionBudget{value: 1}) { case result.Err(failure): t.Fatal(failure); case result.Ok(execution): match execution { case ExecutionCompleted(_, _): continuation.ReleaseMemory(); for index := 0; index < machine.x.Len(); index++ { match machine.x.At(index) { case option.Some(slot): match slot { case option.None: case option.Some(_): t.Fatalf("x%d retained a term", index) }; case option.None: t.Fatalf("x%d disappeared", index) } }; if machine.y.Cap() != 0 { t.Fatalf("y capacity = %d", machine.y.Cap()) }; case _: t.Fatal("continuation did not complete") } } }
	}
}
