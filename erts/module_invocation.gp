package erts

import (
	"math"
	"math/big"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

func invocationInstruction(name string, operands ...beam.Operand) beam.Instruction {
	return beam.Instruction{
		Opcode: beam.Opcode{Name: name, Arity: len(operands)},
		Operands: operands,
	}
}

func invocationProgram(arity uint32) []beam.Instruction {
	return []beam.Instruction{
		invocationInstruction("label", beam.LabelOperand{Index: big.NewInt(1)}),
		invocationInstruction(
			"call_ext_only",
			beam.UnsignedOperand{Value: new(big.Int).SetUint64(uint64(arity))},
			beam.UnsignedOperand{Value: big.NewInt(0)},
		),
	}
}

func invokeLinkedModule(
	target vm.ExternalFunction,
	arguments []term.Term,
	linked map[string]vm.ModuleImage,
	configuredXRegisters int,
	stepLimit int,
	source clock.Clock,
	registry *CallRegistry,
) result.Result[*VMProcess, ModuleLoadFailure] {
	if uint64(len(arguments)) > uint64(math.MaxUint32) {
		return result.Err[*VMProcess, ModuleLoadFailure](InvocationArityOutOfRange(len(arguments)))
	}
	xRegisters := configuredXRegisters
	if xRegisters > 0 && xRegisters < len(arguments) {
		xRegisters = len(arguments)
	}
	config := vm.MachineConfig{
		XRegisters: xRegisters,
		StepLimit: stepLimit,
		Imports: map[uint64]vm.ExternalFunction{0: target},
		ModuleName: "$invoke",
		LinkedModules: linked,
	}
	var machine *vm.Machine
	match vm.NewMachine(invocationProgram(target.Arity), config) {
	case result.Err(failure):
		return result.Err[*VMProcess, ModuleLoadFailure](MachineLoadFailure(failure))
	case result.Ok(created):
		machine = created
	}
	for index, argument := range arguments {
		match machine.SetX(index, argument) {
		case result.Err(failure):
			return result.Err[*VMProcess, ModuleLoadFailure](MachineLoadFailure(failure))
		case result.Ok(_):
		}
	}
	match NewVMProcessWithRegistry(machine, 1, source, registry) {
	case result.Err(failure):
		return result.Err[*VMProcess, ModuleLoadFailure](ProcessLoadFailure(failure))
	case result.Ok(process):
		return result.Ok[*VMProcess, ModuleLoadFailure](process)
	}
}

// assayxport:unit gotp.erts.module-invocation
func (module *LoadedModule) Invoke(
	function string,
	arguments []term.Term,
	source clock.Clock,
	registry *CallRegistry,
) result.Result[*VMProcess, ModuleLoadFailure] {
	if module == nil {
		return result.Err[*VMProcess, ModuleLoadFailure](NilModule())
	}
	if uint64(len(arguments)) > uint64(math.MaxUint32) {
		return result.Err[*VMProcess, ModuleLoadFailure](InvocationArityOutOfRange(len(arguments)))
	}
	arity := uint32(len(arguments))
	match module.Entry(function, arity) {
	case result.Err(failure):
		return result.Err[*VMProcess, ModuleLoadFailure](failure)
	case result.Ok(_):
	}
	target := vm.ExternalFunction{Module: module.name, Function: function, Arity: arity}
	return invokeLinkedModule(
		target,
		arguments,
		map[string]vm.ModuleImage{module.name: module.image()},
		module.config.XRegisters,
		module.config.StepLimit,
		source,
		registryWithModuleInfo(registry, map[string]*LoadedModule{module.name: module}),
	)
}

func (modules *ModuleSet) Invoke(
	moduleName string,
	function string,
	arguments []term.Term,
	source clock.Clock,
	registry *CallRegistry,
) result.Result[*VMProcess, ModuleLoadFailure] {
	if modules == nil {
		return result.Err[*VMProcess, ModuleLoadFailure](NilModuleSet())
	}
	root, present := modules.modules[moduleName]
	match option.Of(root, present) {
	case option.None:
		return result.Err[*VMProcess, ModuleLoadFailure](MissingModule(moduleName))
	case option.Some(module):
		if uint64(len(arguments)) > uint64(math.MaxUint32) {
			return result.Err[*VMProcess, ModuleLoadFailure](InvocationArityOutOfRange(len(arguments)))
		}
		arity := uint32(len(arguments))
		match module.Entry(function, arity) {
		case result.Err(failure):
			return result.Err[*VMProcess, ModuleLoadFailure](failure)
		case result.Ok(_):
		}
		linked := make(map[string]vm.ModuleImage, len(modules.modules))
		for name, loaded := range modules.modules {
			linked[name] = loaded.image()
		}
		created := invokeLinkedModule(
			vm.ExternalFunction{Module: moduleName, Function: function, Arity: arity},
			arguments,
			linked,
			module.config.XRegisters,
			module.config.StepLimit,
			source,
			registryWithModuleInfo(registry, modules.modules),
		)
		match created {
		case result.Err(failure): return result.Err[*VMProcess, ModuleLoadFailure](failure)
		case result.Ok(process): modules.grantProcessSpawning(process, source, registry); return result.Ok[*VMProcess, ModuleLoadFailure](process)
		}
	}
}

func (modules *ModuleSet) grantProcessSpawning(process *VMProcess, source clock.Clock, registry *CallRegistry) {
	process.grantMFASpawning(func(context *kernel.Context, module string, function string, arguments []term.Term, link bool, monitor bool) vm.ExternalCallOutcome {
		return modules.spawnModuleProcess(context, module, function, arguments, link, monitor, source, registry)
	})
}

func (modules *ModuleSet) spawnModuleProcess(context *kernel.Context, module string, function string, arguments []term.Term, link bool, monitor bool, source clock.Clock, registry *CallRegistry) vm.ExternalCallOutcome {
	match modules.Invoke(module, function, arguments, source, registry) {
	case result.Err(failure): return vm.ExternalCallRejected(failure.Error())
	case result.Ok(child): return spawnLoadedProcess(context, child, link, monitor)
	}
}

func spawnLoadedProcess(context *kernel.Context, child *VMProcess, link bool, monitor bool) vm.ExternalCallOutcome {
	var policy kernel.SpawnPolicy = kernel.Unlinked(false)
	if link { policy = kernel.Linked(context.Self(), false) }
	spawned := context.SpawnResult(child.Behavior(), policy)
	if !spawned.Accepted { return vm.ExternalCallRejected(spawned.Detail) }
	if !monitor { return vm.ExternalCallReturned(term.PIDValue(spawned.PID)) }
	return monitorSpawnedProcess(context, spawned.PID)
}

func monitorSpawnedProcess(context *kernel.Context, pid term.PID) vm.ExternalCallOutcome {
	monitored := context.MonitorResult(pid)
	if !monitored.Accepted { return vm.ExternalCallRejected(monitored.Detail) }
	return vm.ExternalCallReturned(term.Tuple(term.PIDValue(pid), term.ReferenceValue(monitored.Reference)))
}
