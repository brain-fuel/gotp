package erts

import (
	"encoding/binary"
	"testing"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

func importedExecutableModuleBytes() []byte {
	code := []byte{
		1, 0x15,
		2, 0x12, 0x22, 0x00,
		64, 0x71, 0x03,
		78, 0x10, 0x00,
		3,
	}
	codeChunk := make([]byte, 20+len(code))
	binary.BigEndian.PutUint32(codeChunk[0:4], 16)
	binary.BigEndian.PutUint32(codeChunk[4:8], 0)
	binary.BigEndian.PutUint32(codeChunk[8:12], 191)
	binary.BigEndian.PutUint32(codeChunk[12:16], 1)
	binary.BigEndian.PutUint32(codeChunk[16:20], 1)
	copy(codeChunk[20:], code)
	return loaderModuleBytes(
		loaderChunk("AtU8", loaderTableAtoms("import_demo", "main", "demo_math", "double")),
		loaderChunk("Code", codeChunk),
		loaderChunk("ImpT", loaderTableWords([]uint32{3, 4, 1})),
		loaderChunk("ExpT", loaderTableWords([]uint32{2, 0, 1})),
	)
}

func doubleRegistryCall(arguments []term.Term) vm.ExternalCallOutcome {
	match term.Int64(arguments[0]) {
	case option.None:
		return vm.ExternalCallRejected("argument is not int64")
	case option.Some(value):
		return vm.ExternalCallReturned(term.Integer(value * 2))
	}
}

func doublingRegistry() *CallRegistry {
	target := vm.ExternalFunction{Module: "demo_math", Function: "double", Arity: 1}
	match NewCallRegistry([]CallBinding{{
		Target: target,
		Implementation: doubleRegistryCall,
	}}) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(registry):
		return registry
	}
}

// assayxport:law gotp.erts.call-registry-laws
func TestLoadedImportExecutesThroughRegistry(t *testing.T) {
	match DecodeModule(importedExecutableModuleBytes(), ModuleLoaderConfig{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(module):
		match module.NewLinkedProcess("main", 0, clock.Real{}, doublingRegistry()) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(process):
			runtime := kernel.New(kernel.KernelConfig{})
			match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
			case result.Err(failure):
				t.Fatal(failure)
			case result.Ok(_):
			}
			runtime.Run(10)
			var state VMProcessState = process.State()
			match state {
			case VMProcessCompleted(value, _, _):
				if !term.Equal(value, term.Integer(14)) {
					t.Fatalf("external result = %v", value)
				}
			case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessFailed(_, _, _):
				t.Fatalf("external process state = %T", state)
			}
		}
	}
}

func TestCallRegistryRejectsDuplicateMFA(t *testing.T) {
	target := vm.ExternalFunction{Module: "demo", Function: "f", Arity: 0}
	call := func(_ []term.Term) vm.ExternalCallOutcome { return vm.ExternalCallReturned(term.MustAtom("ok")) }
	match NewCallRegistry([]CallBinding{
		{Target: target, Implementation: call},
		{Target: target, Implementation: call},
	}) {
	case result.Ok(_):
		t.Fatal("duplicate MFA was accepted")
	case result.Err(failure):
		var duplicate CallRegistryFailure = failure
		match duplicate {
		case DuplicateExternalFunction(found):
			if found != target {
				t.Fatalf("duplicate target = %#v", found)
			}
		case InvalidExternalFunction(_, _), NilExternalImplementation(_):
			t.Fatalf("unexpected failure: %v", failure)
		}
	}
}
