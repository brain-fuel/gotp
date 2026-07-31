package erts

import (
	"fmt"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

type ModuleLoadFailure enum {
	NilModule()
	BeamLoadFailure(Cause beam.Failure)
	LiteralLoadFailure(Cause beam.LiteralFailure)
	MachineLoadFailure(Cause vm.Failure)
	ProcessLoadFailure(Cause AdapterFailure)
	InvalidModuleAtom(Index uint64, Cause term.ValidationFailure)
	DuplicateModuleExport(Function string, Arity uint32)
	MissingExport(Function string, Arity uint32)
	ExportLabelMissing(Function string, Arity uint32, Label uint64)
}

func (failure ModuleLoadFailure) Error() string {
	match failure {
	case NilModule:
		return "gotp/erts: BEAM module is nil"
	case BeamLoadFailure(cause):
		return "gotp/erts: load BEAM module: " + cause.Error()
	case LiteralLoadFailure(cause):
		return "gotp/erts: load BEAM literals: " + cause.Error()
	case MachineLoadFailure(cause):
		return "gotp/erts: construct module machine: " + cause.Error()
	case ProcessLoadFailure(cause):
		return "gotp/erts: construct module process: " + cause.Error()
	case InvalidModuleAtom(index, cause):
		return fmt.Sprintf("gotp/erts: atom %d is invalid: %v", index, cause)
	case DuplicateModuleExport(function, arity):
		return fmt.Sprintf("gotp/erts: duplicate export %s/%d", function, arity)
	case MissingExport(function, arity):
		return fmt.Sprintf("gotp/erts: missing export %s/%d", function, arity)
	case ExportLabelMissing(function, arity, label):
		return fmt.Sprintf("gotp/erts: export %s/%d references missing label %d", function, arity, label)
	}
}

type ModuleLoaderConfig struct {
	CodeLimits beam.CodeDecodeLimits
	LiteralLimits beam.LiteralDecodeLimits
	XRegisters int
	StepLimit  int
}

type ExportKey struct {
	Function string
	Arity    uint32
}

type LoadedModule struct {
	name         string
	digest       string
	instructions []beam.Instruction
	config       vm.MachineConfig
	exports      map[ExportKey]uint64
}

func (module *LoadedModule) Name() string {
	return module.name
}

func (module *LoadedModule) Digest() string {
	return module.digest
}

func (module *LoadedModule) LiteralCount() int {
	return len(module.config.Literals)
}

func (module *LoadedModule) Entry(function string, arity uint32) result.Result[uint64, ModuleLoadFailure] {
	label, present := module.exports[ExportKey{Function: function, Arity: arity}]
	match option.Of(label, present) {
	case option.None:
		return result.Err[uint64, ModuleLoadFailure](MissingExport(function, arity))
	case option.Some(entry):
		return result.Ok[uint64, ModuleLoadFailure](entry)
	}
}

func (module *LoadedModule) NewMachine() result.Result[*vm.Machine, ModuleLoadFailure] {
	match vm.NewMachine(module.instructions, module.config) {
	case result.Err(failure):
		return result.Err[*vm.Machine, ModuleLoadFailure](MachineLoadFailure(failure))
	case result.Ok(machine):
		return result.Ok[*vm.Machine, ModuleLoadFailure](machine)
	}
}

func (module *LoadedModule) NewProcess(
	function string,
	arity uint32,
	source clock.Clock,
) result.Result[*VMProcess, ModuleLoadFailure] {
	match module.Entry(function, arity) {
	case result.Err(failure):
		return result.Err[*VMProcess, ModuleLoadFailure](failure)
	case result.Ok(entry):
		match module.NewMachine() {
		case result.Err(failure):
			return result.Err[*VMProcess, ModuleLoadFailure](failure)
		case result.Ok(machine):
			match NewVMProcessWithClock(machine, entry, source) {
			case result.Err(failure):
				return result.Err[*VMProcess, ModuleLoadFailure](ProcessLoadFailure(failure))
			case result.Ok(process):
				return result.Ok[*VMProcess, ModuleLoadFailure](process)
			}
		}
	}
}

func (module *LoadedModule) NewLinkedProcess(
	function string,
	arity uint32,
	source clock.Clock,
	registry *CallRegistry,
) result.Result[*VMProcess, ModuleLoadFailure] {
	match module.Entry(function, arity) {
	case result.Err(failure):
		return result.Err[*VMProcess, ModuleLoadFailure](failure)
	case result.Ok(entry):
		match module.NewMachine() {
		case result.Err(failure):
			return result.Err[*VMProcess, ModuleLoadFailure](failure)
		case result.Ok(machine):
			match NewVMProcessWithRegistry(machine, entry, source, registry) {
			case result.Err(failure):
				return result.Err[*VMProcess, ModuleLoadFailure](ProcessLoadFailure(failure))
			case result.Ok(process):
				return result.Ok[*VMProcess, ModuleLoadFailure](process)
			}
		}
	}
}

// assayxport:unit gotp.erts.module-loader
func DecodeModule(
	data []byte,
	config ModuleLoaderConfig,
) result.Result[*LoadedModule, ModuleLoadFailure] {
	match beam.Parse(data) {
	case result.Err(failure):
		return result.Err[*LoadedModule, ModuleLoadFailure](BeamLoadFailure(failure))
	case result.Ok(module):
		return LoadModule(module, config)
	}
}

func LoadModuleFile(
	capability beam.ReadFileCapability,
	path string,
	config ModuleLoaderConfig,
) result.Result[*LoadedModule, ModuleLoadFailure] {
	match beam.Load(capability, path) {
	case result.Err(failure):
		return result.Err[*LoadedModule, ModuleLoadFailure](BeamLoadFailure(failure))
	case result.Ok(module):
		return LoadModule(module, config)
	}
}

func LoadModule(
	module *beam.Module,
	config ModuleLoaderConfig,
) result.Result[*LoadedModule, ModuleLoadFailure] {
	if module == nil {
		return result.Err[*LoadedModule, ModuleLoadFailure](NilModule())
	}
	var code []byte
	match module.Chunk("Code") {
	case option.None:
		return result.Err[*LoadedModule, ModuleLoadFailure](BeamLoadFailure(beam.MissingChunk("Code")))
	case option.Some(chunk):
		code = chunk
	}
	var decoded beam.DecodedCode
	match beam.DecodeCodeChunk(code, config.CodeLimits) {
	case result.Err(failure):
		return result.Err[*LoadedModule, ModuleLoadFailure](BeamLoadFailure(failure))
	case result.Ok(value):
		decoded = value
	}
	atoms := make(map[uint64]string, len(module.Atoms))
	for offset, name := range module.Atoms {
		index := uint64(offset + 1)
		match term.Atom(name) {
		case result.Err(failure):
			return result.Err[*LoadedModule, ModuleLoadFailure](InvalidModuleAtom(index, failure))
		case result.Ok(_):
			atoms[index] = name
		}
	}
	var literals map[uint64]term.Term
	match beam.DecodeModuleLiterals(module, config.LiteralLimits) {
	case result.Err(failure):
		return result.Err[*LoadedModule, ModuleLoadFailure](LiteralLoadFailure(failure))
	case result.Ok(values):
		literals = values
	}
	imports := make(map[uint64]vm.ExternalFunction, len(module.Imports))
	for index, imported := range module.Imports {
		imports[uint64(index)] = vm.ExternalFunction{
			Module: imported.Module,
			Function: imported.Function,
			Arity: imported.Arity,
		}
	}
	labels := make(map[uint64]bool)
	for _, instruction := range decoded.Instructions {
		if instruction.Opcode.Name != "label" || len(instruction.Operands) != 1 {
			continue
		}
		match beam.Uint64(instruction.Operands[0]) {
		case option.None:
		case option.Some(label):
			labels[label] = true
		}
	}
	exports := make(map[ExportKey]uint64, len(module.Exports))
	vmExports := make(map[vm.ExternalFunction]uint64, len(module.Exports))
	for _, exported := range module.Exports {
		key := ExportKey{Function: exported.Function, Arity: exported.Arity}
		if _, duplicate := exports[key]; duplicate {
			return result.Err[*LoadedModule, ModuleLoadFailure](DuplicateModuleExport(
				exported.Function,
				exported.Arity,
			))
		}
		if !labels[uint64(exported.Label)] {
			return result.Err[*LoadedModule, ModuleLoadFailure](ExportLabelMissing(
				exported.Function,
				exported.Arity,
				uint64(exported.Label),
			))
		}
		exports[key] = uint64(exported.Label)
		vmExports[vm.ExternalFunction{
			Module: module.Name,
			Function: exported.Function,
			Arity: exported.Arity,
		}] = uint64(exported.Label)
	}
	machineConfig := vm.MachineConfig{
		XRegisters: config.XRegisters,
		StepLimit:  config.StepLimit,
		Atoms:      atoms,
		Literals:   literals,
		Imports:    imports,
		ModuleName: module.Name,
		Exports:    vmExports,
	}
	match vm.NewMachine(decoded.Instructions, machineConfig) {
	case result.Err(failure):
		return result.Err[*LoadedModule, ModuleLoadFailure](MachineLoadFailure(failure))
	case result.Ok(_):
	}
	return result.Ok[*LoadedModule, ModuleLoadFailure](&LoadedModule{
		name: module.Name,
		digest: module.Digest,
		instructions: append([]beam.Instruction(nil), decoded.Instructions...),
		config: machineConfig,
		exports: exports,
	})
}
