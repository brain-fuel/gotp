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

func runPinnedLists(t *testing.T, function string, arguments []term.Term) term.Term {
	var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
	var module *LoadedModule
	match LoadModuleFile(read, "../beam/testdata/otp-29.0.4/lists.beam", ModuleLoaderConfig{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(loaded):
		module = loaded
	}
	var machine *vm.Machine
	match module.NewMachine() {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(loaded):
		machine = loaded
	}
	for index, argument := range arguments {
		match machine.SetX(index, argument) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(_):
		}
	}
	var entry uint64
	match module.Entry(function, uint32(len(arguments))) {
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
		runtime.Run(100)
		var state VMProcessState = process.State()
		match state {
		case VMProcessCompleted(value, _, _):
			return value
		case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
			t.Fatalf("lists:%s/%d state = %T: %v", function, len(arguments), state, state)
		}
	}
	panic("unreachable")
}

// assayxport:law gotp.erts.pinned-otp-lists-laws
func TestPinnedOTPListsPureBIFPaths(t *testing.T) {
	values := term.List(term.Integer(1), term.Integer(2), term.Integer(3), term.Integer(4))
	if got := runPinnedLists(t, "sum", []term.Term{values}); !term.Equal(got, term.Integer(10)) {
		t.Fatalf("lists:sum/1 = %v", got)
	}
	appended := runPinnedLists(t, "append", []term.Term{
		term.List(term.Integer(1), term.Integer(2)),
		term.List(term.Integer(3), term.Integer(4)),
	})
	want := term.List(term.Integer(1), term.Integer(2), term.Integer(3), term.Integer(4))
	if !term.Equal(appended, want) {
		t.Fatalf("lists:append/2 = %v", appended)
	}
}

func TestPinnedOTPListsTermOrderPaths(t *testing.T) {
	sequence := runPinnedLists(t, "seq", []term.Term{term.Integer(1), term.Integer(3)})
	if !term.Equal(sequence, term.List(term.Integer(1), term.Integer(2), term.Integer(3))) {
		t.Fatalf("lists:seq/2 = %v", sequence)
	}
	duplicated := runPinnedLists(t, "duplicate", []term.Term{term.Integer(3), term.MustAtom("a")})
	if !term.Equal(duplicated, term.List(term.MustAtom("a"), term.MustAtom("a"), term.MustAtom("a"))) {
		t.Fatalf("lists:duplicate/2 = %v", duplicated)
	}
	values := term.List(term.Integer(3), term.Integer(1), term.Integer(2))
	if got := runPinnedLists(t, "min", []term.Term{values}); !term.Equal(got, term.Integer(1)) {
		t.Fatalf("lists:min/1 = %v", got)
	}
	if got := runPinnedLists(t, "max", []term.Term{values}); !term.Equal(got, term.Integer(3)) {
		t.Fatalf("lists:max/1 = %v", got)
	}
	if got := runPinnedLists(t, "nth", []term.Term{term.Integer(2), values}); !term.Equal(got, term.Integer(1)) {
		t.Fatalf("lists:nth/2 = %v", got)
	}
}
