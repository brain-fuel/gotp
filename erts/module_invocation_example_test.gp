package erts

import (
	"testing"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

func pinnedListsModule(t *testing.T) *LoadedModule {
	var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
	match LoadModuleFile(read, "../beam/testdata/otp-29.0.4/lists.beam", ModuleLoaderConfig{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(module):
		return module
	}
	panic("unreachable")
}

func completedInvocation(t *testing.T, process *VMProcess) term.Term {
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
		t.Fatalf("invocation state = %T: %v", state, state)
	}
	panic("unreachable")
}

func otpRegistryForInvocation(t *testing.T) *CallRegistry {
	match NewOTPCallRegistry() {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(registry):
		return registry
	}
	panic("unreachable")
}

// assayxport:law gotp.erts.module-invocation-laws
func TestLoadedModuleInvocationUsesNativeExportOverride(t *testing.T) {
	module := pinnedListsModule(t)
	registry := otpRegistryForInvocation(t)
	values := term.List(term.Float(1), term.Integer(2))
	match module.Invoke("member", []term.Term{term.Integer(1), values}, clock.Real{}, registry) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(process):
		value := completedInvocation(t, process)
		if !term.Equal(value, term.MustAtom("false")) {
			t.Fatalf("lists:member(1, [1.0, 2]) = %v", value)
		}
	}
	match module.Invoke("member", []term.Term{term.Integer(2), values}, clock.Real{}, registry) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(process):
		value := completedInvocation(t, process)
		if !term.Equal(value, term.MustAtom("true")) {
			t.Fatalf("lists:member(2, [1.0, 2]) = %v", value)
		}
	}
}

func TestLoadedModuleInvocationFallsBackToBEAMExport(t *testing.T) {
	module := pinnedListsModule(t)
	values := term.List(term.Integer(1), term.Integer(2), term.Integer(3))
	match module.Invoke("last", []term.Term{values}, clock.Real{}, otpRegistryForInvocation(t)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(process):
		value := completedInvocation(t, process)
		if !term.Equal(value, term.Integer(3)) {
			t.Fatalf("lists:last/1 = %v", value)
		}
	}
}

func TestModuleSetInvocationUsesSameRootDispatch(t *testing.T) {
	module := pinnedListsModule(t)
	match NewModuleSet([]*LoadedModule{module}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(modules):
		match modules.Invoke(
			"lists",
			"member",
			[]term.Term{term.MustAtom("needle"), term.List(term.MustAtom("needle"))},
			clock.Real{},
			otpRegistryForInvocation(t),
		) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(process):
			value := completedInvocation(t, process)
			if !term.Equal(value, term.MustAtom("true")) {
				t.Fatalf("module-set lists:member/2 = %v", value)
			}
		}
	}
}
