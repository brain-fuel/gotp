package erts

import (
	"math/big"
	"testing"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

func aliasInstruction(name string, operands ...beam.Operand) beam.Instruction {
	return beam.Instruction{Opcode: beam.Opcode{Name: name, Arity: len(operands)}, Operands: operands}
}

// assayxport:law gotp.erts.otp-alias-laws
func TestBEAMAliasBIFRoutesReferenceSendIntoReceive(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{})
	var alias option.Option[term.Reference] = option.None[term.Reference]
	observer := mustKernelSpawn(t, runtime, func(context *kernel.Context) kernel.StepResult {
		match context.ReceiveMessage(nil) {
		case option.None:
			return kernel.Wait()
		case option.Some(envelope):
			match term.TermReferenceValue(envelope.Message) {
			case option.None:
				return kernel.Stop(term.MustAtom("bad_alias"))
			case option.Some(reference):
				alias = option.Some[term.Reference](reference)
				context.SendAlias(reference, term.MustAtom("through_alias"))
				return kernel.Stop(term.MustAtom("normal"))
			}
		}
	}, kernel.Unlinked(false))

	target := vm.ExternalFunction{Module: "erlang", Function: "alias", Arity: 0}
	program := []beam.Instruction{
		aliasInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		aliasInstruction("move", beam.XRegisterOperand{Index: big.NewInt(0)}, beam.XRegisterOperand{Index: big.NewInt(1)}),
		aliasInstruction("call_ext", beam.UnsignedOperand{Value: big.NewInt(0)}, beam.UnsignedOperand{Value: big.NewInt(0)}),
		aliasInstruction("move", beam.XRegisterOperand{Index: big.NewInt(0)}, beam.XRegisterOperand{Index: big.NewInt(2)}),
		aliasInstruction("move", beam.XRegisterOperand{Index: big.NewInt(1)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		aliasInstruction("move", beam.XRegisterOperand{Index: big.NewInt(2)}, beam.XRegisterOperand{Index: big.NewInt(1)}),
		aliasInstruction("send"),
		aliasInstruction("label", beam.LabelOperand{Index: big.NewInt(2)}),
		aliasInstruction("loop_rec", beam.LabelOperand{Index: big.NewInt(3)}, beam.XRegisterOperand{Index: big.NewInt(0)}),
		aliasInstruction("remove_message"),
		aliasInstruction("return"),
		aliasInstruction("label", beam.LabelOperand{Index: big.NewInt(3)}),
		aliasInstruction("wait", beam.LabelOperand{Index: big.NewInt(2)}),
	}
	var machine *vm.Machine
	match vm.NewMachine(program, vm.MachineConfig{XRegisters: 3, Imports: map[uint64]vm.ExternalFunction{0: target}}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(created):
		machine = created
	}
	match machine.SetX(0, term.PIDValue(observer)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	var registry *CallRegistry
	match NewOTPCallRegistry() {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(created):
		registry = created
	}
	var process *VMProcess
	match NewVMProcessWithRegistry(machine, 1, clock.Real{}, registry) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(created):
		process = created
	}
	mustKernelSpawn(t, runtime, process.Behavior(), kernel.Unlinked(false))
	runtime.Run(100)
	match alias {
	case option.None:
		t.Fatal("alias BIF did not return a reference")
	case option.Some(_):
	}
	var state VMProcessState = process.State()
	match state {
	case VMProcessCompleted(value, _, _):
		if !term.Equal(value, term.MustAtom("through_alias")) {
			t.Fatalf("alias receive = %v", value)
		}
	case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
		t.Fatalf("alias process = %T", state)
	}
}

func mustKernelSpawn(t *testing.T, runtime *kernel.Kernel, behavior kernel.Behavior, policy kernel.SpawnPolicy) term.PID {
	match runtime.Spawn(behavior, policy) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(pid):
		return pid
	}
	panic("unreachable")
}
