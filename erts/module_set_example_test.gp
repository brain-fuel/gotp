package erts

import (
	"testing"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

func loadedImportDemo(t *testing.T) *LoadedModule {
	match DecodeModule(importedExecutableModuleBytes(), ModuleLoaderConfig{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(module):
		return module
	}
	panic("unreachable")
}

// assayxport:law gotp.erts.module-set-laws
func TestModuleSetConstructsLinkedProcess(t *testing.T) {
	module := loadedImportDemo(t)
	match NewModuleSet([]*LoadedModule{module}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(modules):
		match modules.NewProcess("import_demo", "main", 0, clock.Real{}, doublingRegistry()) {
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
					t.Fatalf("module-set result = %v", value)
				}
			case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
				t.Fatalf("module-set process state = %T", state)
			}
		}
	}
}

func TestModuleSetRejectsDuplicateModuleName(t *testing.T) {
	module := loadedImportDemo(t)
	match NewModuleSet([]*LoadedModule{module, module}) {
	case result.Ok(_):
		t.Fatal("duplicate module name was accepted")
	case result.Err(failure):
		var loadFailure ModuleLoadFailure = failure
		match loadFailure {
		case DuplicateLoadedModule(name):
			if name != "import_demo" {
				t.Fatalf("duplicate module = %q", name)
			}
		case NilModule, NilModuleSet, InvocationArityOutOfRange(_), BeamLoadFailure(_), LiteralLoadFailure(_), FunctionLoadFailure(_), MachineLoadFailure(_), ProcessLoadFailure(_), InvalidModuleAtom(_, _), DuplicateModuleExport(_, _), MissingModule(_), MissingExport(_, _), ExportLabelMissing(_, _, _):
			t.Fatalf("duplicate failure = %v", failure)
		}
	}
}
