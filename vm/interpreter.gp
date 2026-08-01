package vm

import (
	"fmt"
	"math/big"

	"goforge.dev/goplus/std/memory"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

type MachineConfig struct {
	XRegisters int
	StepLimit  int
	HeapBytes  int
	Atoms      map[uint64]string
	Literals   map[uint64]term.Term
	Imports    map[uint64]ExternalFunction
	Functions  map[uint64]beam.FunctionTemplate
	ModuleName string
	Exports    map[ExternalFunction]uint64
	LinkedModules map[string]ModuleImage
}

type ModuleImage struct {
	Name     string
	Program  []beam.Instruction
	Atoms    map[uint64]string
	Literals map[uint64]term.Term
	Imports  map[uint64]ExternalFunction
	Functions map[uint64]beam.FunctionTemplate
	Exports  map[ExternalFunction]uint64
}

type machineImage struct {
	name     string
	program  []beam.Instruction
	labels   map[uint64]int
	atoms    map[uint64]string
	literals map[uint64]term.Term
	imports  map[uint64]ExternalFunction
	functions map[uint64]beam.FunctionTemplate
	exports  map[ExternalFunction]uint64
}

type RunResult struct {
	Value term.Term
	Steps int
}

type MachineMutation enum {
	MachineMutated()
}

type returnFrame struct { pc int; image *machineImage; codeLeave func() }

type binaryMatchContext struct { bytes []byte; bitPosition int }

type Machine struct {
	program   []beam.Instruction
	labels    map[uint64]int
	x         memory.Buffer[option.Option[term.Term]]
	y         memory.Buffer[option.Option[term.Term]]
	atoms     map[uint64]string
	literals  map[uint64]term.Term
	imports   map[uint64]ExternalFunction
	functions map[uint64]beam.FunctionTemplate
	returns memory.Buffer[returnFrame]
	current   *machineImage
	currentCodeLeave func()
	root      *machineImage
	modules   map[string]*machineImage
	handlers  memory.Buffer[exceptionHandler]
	processMemory *ProcessMemory
	nextHandler uint64
	binaryMatches map[uint64]binaryMatchContext
	nextBinaryMatch uint64
	pc        int
	steps     int
	stepLimit int
}

func NewMachine(
	program []beam.Instruction,
	config MachineConfig,
) result.Result[*Machine, Failure] {
	if config.XRegisters <= 0 {
		config.XRegisters = 256
	}
	if config.StepLimit <= 0 {
		config.StepLimit = 1_000_000
	}
	if config.HeapBytes <= 0 {
		config.HeapBytes = 1 << 20
	}
	labels := make(map[uint64]int)
	for index, instruction := range program {
		if instruction.Opcode.Name != "label" {
			continue
		}
		if len(instruction.Operands) != 1 {
			return result.Err[*Machine, Failure](InvalidProgram(fmt.Sprintf(
				"label at instruction %d has %d operands",
				index,
				len(instruction.Operands),
			)))
		}
		match labelIndex(instruction.Operands[0]) {
		case option.None:
			return result.Err[*Machine, Failure](InvalidProgram(fmt.Sprintf(
				"label at instruction %d is not a nonnegative uint64",
				index,
			)))
		case option.Some(label):
			_, duplicate := labels[label]
			if duplicate {
				return result.Err[*Machine, Failure](InvalidProgram(fmt.Sprintf(
					"duplicate label %d",
					label,
				)))
			}
			labels[label] = index
		}
	}
	registers := memory.NewBuffer[option.Option[term.Term]](config.XRegisters)
	for index := 0; index < config.XRegisters; index++ { registers.Append(option.None[term.Term]()) }
	moduleName := config.ModuleName
	if moduleName == "" {
		moduleName = "$root"
	}
	root := &machineImage{
		name: moduleName,
		program: append([]beam.Instruction(nil), program...),
		labels: labels,
		atoms: cloneAtomPool(config.Atoms),
		literals: cloneLiteralPool(config.Literals),
		imports: cloneImportPool(config.Imports),
		functions: cloneFunctionPool(config.Functions),
		exports: cloneExportPool(config.Exports),
	}
	match validateImageExports(root) {
	case result.Err(failure):
		return result.Err[*Machine, Failure](failure)
	case result.Ok(_):
	}
	modules := map[string]*machineImage{moduleName: root}
	for name, linked := range config.LinkedModules {
		if name == moduleName {
			return result.Err[*Machine, Failure](InvalidProgram("linked module duplicates root module " + name))
		}
		if linked.Name != "" && linked.Name != name {
			return result.Err[*Machine, Failure](InvalidProgram("linked module name differs from its registry key"))
		}
		linked.Name = name
		match newMachineImage(linked) {
		case result.Err(failure):
			return result.Err[*Machine, Failure](failure)
		case result.Ok(image):
			modules[name] = image
		}
	}
	var processMemory *ProcessMemory
	match NewProcessMemory(config.HeapBytes) {
	case result.Err(failure):
		return result.Err[*Machine, Failure](failure)
	case result.Ok(owned):
		processMemory = owned
	}
	return result.Ok[*Machine, Failure](&Machine{
		program: root.program,
		labels: root.labels,
		x: registers,
		y: memory.NewBuffer[option.Option[term.Term]](64),
		returns: memory.NewBuffer[returnFrame](32),
		handlers: memory.NewBuffer[exceptionHandler](8),
		binaryMatches: make(map[uint64]binaryMatchContext),
		nextBinaryMatch: 1,
		processMemory: processMemory,
		atoms: root.atoms,
		literals: root.literals,
		imports: root.imports,
		functions: root.functions,
		current: root,
		root: root,
		modules: modules,
		stepLimit: config.StepLimit,
	})
}

func (machine *Machine) SetX(
	index int,
	value term.Term,
) result.Result[MachineMutation, Failure] {
	if index < 0 || index >= machine.x.Len() {
		return result.Err[MachineMutation, Failure](RegisterOutOfRange("x", index))
	}
	machine.x.Set(index, option.Some[term.Term](term.Clone(value)))
	return result.Ok[MachineMutation, Failure](MachineMutated())
}

func (machine *Machine) resetProcessMemory() { machine.releaseAllCode(); for index := 0; index < machine.x.Len(); index++ { machine.x.Set(index, option.None[term.Term]()) }; machine.y.Release(); machine.returns.Release(); machine.handlers.Release(); if machine.processMemory != nil { machine.processMemory.Reset() } }

func (machine *Machine) ensureHeap(words int) result.Result[HeapMutation, Failure] {
	match machine.processMemory.Ensure(words) {
	case result.Ok(_): return result.Ok[HeapMutation, Failure](HeapMutated())
	case result.Err(failure):
		match failure {
		case MemoryFailure(cause):
			match cause {
			case memory.CapacityExhausted: return machine.processMemory.Collect(machine.liveTerms(), words)
			case memory.ArenaClosed, memory.InvalidHandle, memory.InvalidCheckpoint, memory.InvalidConfiguration(_), memory.BoundsViolation(_), memory.PlatformFailure(_), memory.GroupReleased: return result.Err[HeapMutation, Failure](failure)
			}
		case RaisedException(_, _), InvalidConfiguration(_), ImmediateOutOfRange(_), HeapIndexOutOfRange(_, _), InvalidProgram(_), RegisterOutOfRange(_, _), UninitializedRegister(_, _), MissingConstant(_, _), MissingLabel(_), StepLimitExceeded(_), UnsupportedOpcode(_, _, _): return result.Err[HeapMutation, Failure](failure)
		}
	}
}

func (machine *Machine) trackHeapTerm(value term.Term, words int) result.Result[HeapMutation, Failure] {
	match machine.processMemory.Track(value, words) {
	case result.Ok(_): return result.Ok[HeapMutation, Failure](HeapMutated())
	case result.Err(failure):
		match failure {
		case MemoryFailure(cause):
			match cause {
			case memory.CapacityExhausted:
				match machine.processMemory.Collect(machine.liveTerms(), words) {
				case result.Err(collectionFailure): return result.Err[HeapMutation, Failure](collectionFailure)
				case result.Ok(HeapMutated): return machine.processMemory.Track(value, words)
				}
			case memory.ArenaClosed, memory.InvalidHandle, memory.InvalidCheckpoint, memory.InvalidConfiguration(_), memory.BoundsViolation(_), memory.PlatformFailure(_), memory.GroupReleased: return result.Err[HeapMutation, Failure](failure)
			}
		case RaisedException(_, _), InvalidConfiguration(_), ImmediateOutOfRange(_), HeapIndexOutOfRange(_, _), InvalidProgram(_), RegisterOutOfRange(_, _), UninitializedRegister(_, _), MissingConstant(_, _), MissingLabel(_), StepLimitExceeded(_), UnsupportedOpcode(_, _, _): return result.Err[HeapMutation, Failure](failure)
		}
	}
}

func (machine *Machine) liveTerms() []term.Term {
	live := make([]term.Term, 0, machine.x.Len()+machine.y.Len())
	for index := 0; index < machine.x.Len(); index++ {
		match machine.x.At(index) {
		case option.None:
		case option.Some(slot): match slot { case option.None: case option.Some(value): live = append(live, value) }
		}
	}
	for index := 0; index < machine.y.Len(); index++ {
		match machine.y.At(index) {
		case option.None:
		case option.Some(slot): match slot { case option.None: case option.Some(value): live = append(live, value) }
		}
	}
	for index := 0; index < machine.handlers.Len(); index++ {
		match machine.handlers.At(index) {
		case option.None:
		case option.Some(handler):
			match handler.pending { case option.None: case option.Some(pending): live = append(live, pending.class, pending.reason, pending.trace) }
		}
	}
	return live
}

func (machine *Machine) X(index int) result.Result[term.Term, Failure] {
	return machine.register(machine.x, "x", index)
}

func (machine *Machine) Run(entryLabel uint64) result.Result[RunResult, Failure] {
	var started result.Result[*Continuation, Failure] = machine.Start(entryLabel)
	match started {
	case result.Err(failure):
		return result.Err[RunResult, Failure](failure)
	case result.Ok(continuation):
		var resumed result.Result[ExecutionSlice, Failure] = continuation.Resume(
			VMReductionBudget{value: machine.stepLimit},
		)
		match resumed {
		case result.Err(failure):
			return result.Err[RunResult, Failure](failure)
		case result.Ok(slice):
			var execution ExecutionSlice = slice
			match execution {
			case ExecutionSuspended(_):
				return result.Err[RunResult, Failure](StepLimitExceeded(machine.stepLimit))
			case ExecutionWaiting(_):
				return result.Err[RunResult, Failure](InvalidProgram(
					"execution waited without a process scheduler",
				))
			case ExecutionRaised(class, reason, _):
				return result.Err[RunResult, Failure](RaisedException(class, reason))
			case ExecutionCompleted(value, _):
				return result.Ok[RunResult, Failure](RunResult{Value: value, Steps: machine.steps})
			}
		}
	}
}

func (machine *Machine) finish() result.Result[RunResult, Failure] {
	match machine.X(0) {
	case result.Ok(value):
		return result.Ok[RunResult, Failure](RunResult{Value: value, Steps: machine.steps})
	case result.Err(failure):
		return result.Err[RunResult, Failure](failure)
	}
}

func (machine *Machine) move(
	instruction beam.Instruction,
) result.Result[MachineMutation, Failure] {
	if len(instruction.Operands) != 2 {
		return result.Err[MachineMutation, Failure](InvalidProgram(fmt.Sprintf(
			"move has %d operands",
			len(instruction.Operands),
		)))
	}
	match machine.resolve(instruction.Operands[0]) {
	case result.Err(failure):
		return result.Err[MachineMutation, Failure](failure)
	case result.Ok(value):
		return machine.assign(instruction.Operands[1], value)
	}
}

func (machine *Machine) resolve(
	operand beam.Operand,
) result.Result[term.Term, Failure] {
	match operand {
	case beam.TypedRegisterOperand(register, _):
		return machine.resolve(register)
	case beam.XRegisterOperand(index):
		return machine.readIndexed(machine.x, "x", index)
	case beam.YRegisterOperand(index):
		match machine.yPosition(index) {
		case result.Ok(position):
			return machine.register(machine.y, "y", position)
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		}
	case beam.UnsignedOperand(value):
		return result.Ok[term.Term, Failure](integerTerm(value))
	case beam.IntegerOperand(value):
		return result.Ok[term.Term, Failure](integerTerm(value))
	case beam.AtomOperand(index):
		return machine.atomConstant(index)
	case beam.CharacterOperand(value):
		return result.Ok[term.Term, Failure](integerTerm(value))
	case beam.LiteralOperand(index):
		return machine.literalConstant(index)
	case _:
		return result.Err[term.Term, Failure](InvalidProgram("operand is not a value"))
	}
}

func (machine *Machine) assign(
	destination beam.Operand,
	value term.Term,
) result.Result[MachineMutation, Failure] {
	match destination {
	case beam.TypedRegisterOperand(register, _):
		return machine.assign(register, value)
	case beam.XRegisterOperand(index):
		return machine.writeIndexed(&machine.x, "x", index, value)
	case beam.YRegisterOperand(index):
		match machine.yPosition(index) {
		case result.Err(failure):
			return result.Err[MachineMutation, Failure](failure)
		case result.Ok(position):
			machine.y.Set(position, option.Some[term.Term](term.Clone(value)))
			return result.Ok[MachineMutation, Failure](MachineMutated())
		}
	case _:
		return result.Err[MachineMutation, Failure](InvalidProgram("move destination is not a register"))
	}
}

func (machine *Machine) readIndexed(
	registers memory.Buffer[option.Option[term.Term]],
	name string,
	index *big.Int,
) result.Result[term.Term, Failure] {
	match registerIndex(index) {
	case option.None:
		return result.Err[term.Term, Failure](InvalidProgram(name + " register index is not uint64"))
	case option.Some(value):
		if value > uint64(maxInt()) {
			return result.Err[term.Term, Failure](RegisterOutOfRange(name, maxInt()))
		}
		return machine.register(registers, name, int(value))
	}
}

func (machine *Machine) writeIndexed(
	registers *memory.Buffer[option.Option[term.Term]],
	name string,
	index *big.Int,
	value term.Term,
) result.Result[MachineMutation, Failure] {
	match registerIndex(index) {
	case option.None:
		return result.Err[MachineMutation, Failure](InvalidProgram(name + " register index is not uint64"))
	case option.Some(position):
		if position >= uint64(registers.Len()) {
			return result.Err[MachineMutation, Failure](RegisterOutOfRange(name, int(position)))
		}
		registers.Set(int(position), option.Some[term.Term](term.Clone(value)))
		return result.Ok[MachineMutation, Failure](MachineMutated())
	}
}

func (machine *Machine) register(
	registers memory.Buffer[option.Option[term.Term]],
	name string,
	index int,
) result.Result[term.Term, Failure] {
	if index < 0 || index >= registers.Len() {
		return result.Err[term.Term, Failure](RegisterOutOfRange(name, index))
	}
	match registers.At(index) {
	case option.None: return result.Err[term.Term, Failure](RegisterOutOfRange(name, index))
	case option.Some(slot): match slot {
	case option.Some(value):
		return result.Ok[term.Term, Failure](term.Clone(value))
	case option.None:
		return result.Err[term.Term, Failure](UninitializedRegister(name, index))
	}
	}
}

func (machine *Machine) yPosition(index *big.Int) result.Result[int, Failure] {
	match registerIndex(index) {
	case option.None:
		return result.Err[int, Failure](InvalidProgram("y register index is not uint64"))
	case option.Some(value):
		if value >= uint64(machine.y.Len()) {
			return result.Err[int, Failure](RegisterOutOfRange("y", int(value)))
		}
		return result.Ok[int, Failure](machine.y.Len() - 1 - int(value))
	}
}

func (machine *Machine) instructionLabel(
	instruction beam.Instruction,
	operandIndex int,
) result.Result[int, Failure] {
	if operandIndex < 0 || operandIndex >= len(instruction.Operands) {
		return result.Err[int, Failure](InvalidProgram(fmt.Sprintf(
			"%s is missing label operand %d",
			instruction.Opcode.Name,
			operandIndex,
		)))
	}
	match labelIndex(instruction.Operands[operandIndex]) {
	case option.None:
		return result.Err[int, Failure](InvalidProgram(fmt.Sprintf(
			"%s operand %d is not a label",
			instruction.Opcode.Name,
			operandIndex,
		)))
	case option.Some(label):
		target, present := machine.labels[label]
		match option.Of(target, present) {
		case option.Some(position):
			return result.Ok[int, Failure](position + 1)
		case option.None:
			return result.Err[int, Failure](MissingLabel(label))
		}
	}
}

func (machine *Machine) allocate(
	instruction beam.Instruction,
	operandIndex int,
) result.Result[MachineMutation, Failure] {
	match allocationCount(instruction, operandIndex) {
	case result.Err(failure):
		return result.Err[MachineMutation, Failure](failure)
	case result.Ok(count):
		for index := 0; index < count; index++ {
			machine.y.Append(option.None[term.Term]())
		}
		return result.Ok[MachineMutation, Failure](MachineMutated())
	}
}

func (machine *Machine) deallocate(
	instruction beam.Instruction,
	operandIndex int,
) result.Result[MachineMutation, Failure] {
	match allocationCount(instruction, operandIndex) {
	case result.Err(failure):
		return result.Err[MachineMutation, Failure](failure)
	case result.Ok(count):
		if count > machine.y.Len() {
			return result.Err[MachineMutation, Failure](InvalidProgram("invalid deallocation count"))
		}
		machine.y.Truncate(machine.y.Len()-count)
		return result.Ok[MachineMutation, Failure](MachineMutated())
	}
}

func allocationCount(
	instruction beam.Instruction,
	operandIndex int,
) result.Result[int, Failure] {
	if operandIndex < 0 || operandIndex >= len(instruction.Operands) {
		return result.Err[int, Failure](InvalidProgram(fmt.Sprintf(
			"%s is missing allocation operand",
			instruction.Opcode.Name,
		)))
	}
	match instruction.Operands[operandIndex] {
	case beam.UnsignedOperand(value):
		match registerIndex(value) {
		case option.Some(count):
			if count <= 1_000_000 {
				return result.Ok[int, Failure](int(count))
			}
		case option.None:
		}
	case _:
	}
	return result.Err[int, Failure](InvalidProgram("invalid allocation count"))
}

func labelIndex(operand beam.Operand) option.Option[uint64] {
	match operand {
	case beam.LabelOperand(index):
		return registerIndex(index)
	case beam.UnsignedOperand(index):
		return registerIndex(index)
	case _:
		return option.None[uint64]
	}
}

func registerIndex(index *big.Int) option.Option[uint64] {
	if index.Sign() < 0 || !index.IsUint64() {
		return option.None[uint64]
	}
	return option.Some[uint64](index.Uint64())
}

func maxInt() int {
	return int(^uint(0) >> 1)
}

func integerTerm(value *big.Int) term.Term {
	if value.IsInt64() {
		return term.Integer(value.Int64())
	}
	return term.MustBigInteger(value)
}

func (machine *Machine) atomConstant(index *big.Int) result.Result[term.Term, Failure] {
	if !index.IsUint64() {
		return result.Err[term.Term, Failure](InvalidProgram("atom index is not uint64"))
	}
	position := index.Uint64()
	if position == 0 {
		return result.Ok[term.Term, Failure](term.List())
	}
	name, present := machine.atoms[position]
	if !present {
		return result.Err[term.Term, Failure](MissingConstant("atom", position))
	}
	return result.Ok[term.Term, Failure](term.MustAtom(name))
}

func (machine *Machine) literalConstant(index *big.Int) result.Result[term.Term, Failure] {
	if !index.IsUint64() {
		return result.Err[term.Term, Failure](InvalidProgram("literal index is not uint64"))
	}
	position := index.Uint64()
	value, present := machine.literals[position]
	if !present {
		return result.Err[term.Term, Failure](MissingConstant("literal", position))
	}
	return result.Ok[term.Term, Failure](term.Clone(value))
}

func cloneAtomPool(values map[uint64]string) map[uint64]string {
	cloned := make(map[uint64]string, len(values))
	for index, value := range values {
		cloned[index] = value
	}
	return cloned
}

func cloneLiteralPool(values map[uint64]term.Term) map[uint64]term.Term {
	cloned := make(map[uint64]term.Term, len(values))
	for index, value := range values {
		cloned[index] = term.Clone(value)
	}
	return cloned
}

func cloneImportPool(source map[uint64]ExternalFunction) map[uint64]ExternalFunction {
	cloned := make(map[uint64]ExternalFunction, len(source))
	for index, target := range source {
		cloned[index] = target
	}
	return cloned
}

func cloneFunctionPool(source map[uint64]beam.FunctionTemplate) map[uint64]beam.FunctionTemplate {
	cloned := make(map[uint64]beam.FunctionTemplate, len(source))
	for index, function := range source {
		cloned[index] = function
	}
	return cloned
}

func cloneExportPool(source map[ExternalFunction]uint64) map[ExternalFunction]uint64 {
	cloned := make(map[ExternalFunction]uint64, len(source))
	for target, label := range source {
		cloned[target] = label
	}
	return cloned
}

func labelsForProgram(program []beam.Instruction) result.Result[map[uint64]int, Failure] {
	labels := make(map[uint64]int)
	for index, instruction := range program {
		if instruction.Opcode.Name != "label" {
			continue
		}
		if len(instruction.Operands) != 1 {
			return result.Err[map[uint64]int, Failure](InvalidProgram(fmt.Sprintf(
				"label at instruction %d has %d operands",
				index,
				len(instruction.Operands),
			)))
		}
		match labelIndex(instruction.Operands[0]) {
		case option.None:
			return result.Err[map[uint64]int, Failure](InvalidProgram(fmt.Sprintf(
				"label at instruction %d is not a nonnegative uint64",
				index,
			)))
		case option.Some(label):
			if _, duplicate := labels[label]; duplicate {
				return result.Err[map[uint64]int, Failure](InvalidProgram(fmt.Sprintf("duplicate label %d", label)))
			}
			labels[label] = index
		}
	}
	return result.Ok[map[uint64]int, Failure](labels)
}

func newMachineImage(config ModuleImage) result.Result[*machineImage, Failure] {
	if config.Name == "" {
		return result.Err[*machineImage, Failure](InvalidProgram("linked module name is empty"))
	}
	match labelsForProgram(config.Program) {
	case result.Err(failure):
		return result.Err[*machineImage, Failure](failure)
	case result.Ok(labels):
		image := &machineImage{
			name: config.Name,
			program: append([]beam.Instruction(nil), config.Program...),
			labels: labels,
			atoms: cloneAtomPool(config.Atoms),
			literals: cloneLiteralPool(config.Literals),
			imports: cloneImportPool(config.Imports),
			functions: cloneFunctionPool(config.Functions),
			exports: cloneExportPool(config.Exports),
		}
		match validateImageExports(image) {
		case result.Err(failure):
			return result.Err[*machineImage, Failure](failure)
		case result.Ok(_):
			return result.Ok[*machineImage, Failure](image)
		}
	}
}

func validateImageExports(image *machineImage) result.Result[bool, Failure] {
	for target, label := range image.exports {
		if target.Module != image.name {
			return result.Err[bool, Failure](InvalidProgram("module export identity differs from image name"))
		}
		if _, present := image.labels[label]; !present {
			return result.Err[bool, Failure](MissingLabel(label))
		}
	}
	return result.Ok[bool, Failure](true)
}

func (machine *Machine) activate(image *machineImage) {
	machine.current = image
	machine.program = image.program
	machine.labels = image.labels
	machine.atoms = image.atoms
	machine.literals = image.literals
	machine.imports = image.imports
	machine.functions = image.functions
}

func (machine *Machine) pushReturn(pc int) {
	machine.returns.Append(returnFrame{pc: pc, image: machine.current, codeLeave: machine.currentCodeLeave})
}

func (machine *Machine) returnToCaller() bool {
	if machine.returns.Len() == 0 {
		machine.leaveCurrentCode()
		return false
	}
	last := machine.returns.Len() - 1; var frame returnFrame
	match machine.returns.Remove(last) { case option.None: return false; case option.Some(found): frame = found }
	machine.leaveCurrentCode()
	machine.activate(frame.image)
	machine.currentCodeLeave = frame.codeLeave
	machine.pc = frame.pc
	return true
}

func (machine *Machine) activateLinkedCode(image *machineImage, leave func()) {
	machine.activate(image)
	machine.currentCodeLeave = leave
}

func (machine *Machine) leaveCurrentCode() {
	if machine.currentCodeLeave != nil { leave := machine.currentCodeLeave; machine.currentCodeLeave = nil; leave() }
}

func (machine *Machine) releaseAllCode() {
	machine.leaveCurrentCode()
	for index := machine.returns.Len() - 1; index >= 0; index-- { match machine.returns.At(index) { case option.Some(frame): if frame.codeLeave != nil { frame.codeLeave() }; case option.None: } }
	machine.returns.Reset()
}
