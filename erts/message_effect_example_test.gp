package erts

import (
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

// assayxport:unit gotp.erts.message-effect-laws
func TestVMProcessSendsThroughKernelCapability(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{})
	received := term.InvalidValue()
	var recipientResult result.Result[term.PID, kernel.Failure] = runtime.Spawn(
		func(context *kernel.Context) kernel.StepResult {
			match context.ReceiveMessage(nil) {
			case option.None:
				return kernel.Wait()
			case option.Some(envelope):
				received = term.Clone(envelope.Message)
				return kernel.Stop(term.MustAtom("normal"))
			}
		},
		kernel.Unlinked(false),
	)
	match recipientResult {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(recipient):
		program := []beam.Instruction{
			vmInstruction("label", vmLabel(1)),
			vmInstruction("send"),
			vmInstruction("return"),
		}
		match vm.NewMachine(program, vm.MachineConfig{}) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(machine):
			message := term.Tuple(term.MustAtom("hello"), term.Integer(42))
			match machine.SetX(0, term.PIDValue(recipient)) {
			case result.Err(failure): t.Fatal(failure.Error())
			case result.Ok(_):
			}
			match machine.SetX(1, message) {
			case result.Err(failure): t.Fatal(failure.Error())
			case result.Ok(_):
			}
			match NewVMProcess(machine, 1) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(process):
				match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
				case result.Err(failure):
					t.Fatal(failure.Error())
				case result.Ok(_):
					report := runtime.RunSlice(mustKernelBudget(t, 8))
					if report.Run.Exited != 2 || !term.Equal(received, message) {
						t.Fatalf("report=%#v received=%#v", report.Run, received)
					}
					var state VMProcessState = process.State()
					match state {
					case VMProcessCompleted(value, _, _):
						if !term.Equal(value, message) { t.Fatal("send did not return message in x(0)") }
					case _:
						t.Fatal("sender VM did not complete")
					}
				}
			}
		}
	}
}

func TestVMProcessSendToMissingPIDReturnsMessage(t *testing.T) {
	program := []beam.Instruction{
		vmInstruction("label", vmLabel(1)),
		vmInstruction("send"),
		vmInstruction("return"),
	}
	match vm.NewMachine(program, vm.MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		missing := term.PID{Node: 1, Number: 999, Creation: 1}
		message := term.MustAtom("still_returns")
		match machine.SetX(0, term.PIDValue(missing)) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(_):
		}
		match machine.SetX(1, message) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(_):
		}
		match NewVMProcess(machine, 1) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(process):
			runtime := kernel.New(kernel.KernelConfig{})
			match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(_):
				runtime.RunSlice(mustKernelBudget(t, 2))
				var state VMProcessState = process.State()
				match state {
				case VMProcessCompleted(value, _, _):
					if !term.Equal(value, message) { t.Fatal("missing-PID send changed result") }
				case _:
					t.Fatal("missing-PID send did not complete")
				}
			}
		}
	}
}
