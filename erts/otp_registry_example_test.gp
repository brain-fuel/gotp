package erts

import (
	"testing"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

// assayxport:law gotp.erts.otp-call-registry-laws
func TestPinnedOTPListsReverseExecutesRuntimeOverride(t *testing.T) {
	var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
	match LoadModuleFile(read, "../beam/testdata/otp-29.0.4/lists.beam", ModuleLoaderConfig{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(module):
		var machine *vm.Machine
		match module.NewMachine() {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(loaded):
			machine = loaded
		}
		match machine.SetX(0, term.List(term.Integer(1), term.Integer(2), term.Integer(3))) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(_):
		}
		var entry uint64
		match module.Entry("reverse", 1) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(label):
			entry = label
		}
		var registry *CallRegistry
		match NewOTPCallRegistry() {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(loaded):
			registry = loaded
		}
		match NewVMProcessWithRegistry(machine, entry, clock.Real{}, registry) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(process):
			runtime := kernel.New(kernel.KernelConfig{})
			match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
			case result.Err(failure):
				t.Fatal(failure)
			case result.Ok(_):
			}
			runtime.Run(20)
			var state VMProcessState = process.State()
			match state {
			case VMProcessCompleted(value, _, _):
				want := term.List(term.Integer(3), term.Integer(2), term.Integer(1))
				if !term.Equal(value, want) {
					t.Fatalf("lists:reverse/1 = %v", value)
				}
			case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
				t.Fatalf("lists:reverse/1 state = %T: %v", state, state)
			}
		}
	}
}
