package release

import (
	"fmt"
	"sort"
	"strings"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type PurgeMethod enum {
	SoftPurge()
	BrutalPurge()
}

type ChangeMode enum {
	Upgrade()
	Downgrade()
}

type SuspendTimeout enum {
	DefaultTimeout()
	InfiniteTimeout()
	FiniteTimeout(Milliseconds int64)
}

type SuspendTarget struct { Module string; Timeout SuspendTimeout }
type ChangeTarget struct { Module string; Extra term.Term }
type MFA struct { Module string; Function string; Arguments []term.Term }

//goplus:derive off
type Instruction enum {
	LoadObjectCode(Library string, Version string, Modules []string)
	PointOfNoReturn()
	LoadCode(Module string, PrePurge PurgeMethod, PostPurge PurgeMethod)
	RemoveCode(Module string, PrePurge PurgeMethod, PostPurge PurgeMethod)
	PurgeCode(Modules []string)
	SuspendCode(Targets []SuspendTarget)
	ResumeCode(Modules []string)
	ChangeCode(Mode ChangeMode, Targets []ChangeTarget)
	StopCode(Modules []string)
	StartCode(Modules []string)
	SyncNodesList(ID term.Term, Nodes []string)
	SyncNodesApply(ID term.Term, Call MFA)
	Apply(Call MFA)
	RestartEmulator()
	RestartNewEmulator()
}

type Script struct {
	Instructions []Instruction
	CommitIndex int
}

type ScriptFailure enum {
	ExpectedInstructionList(Found term.Kind)
	InvalidInstruction(Index int, Detail string)
	InvalidOrdering(Index int, Detail string)
	DuplicateStagedModule(Module string)
	UnstagedModule(Module string)
}

func (failure ScriptFailure) Error() string {
	match failure {
	case ExpectedInstructionList(found): return fmt.Sprintf("gotp/release: expected instruction list; found %v", found)
	case InvalidInstruction(index, detail): return fmt.Sprintf("gotp/release: instruction %d: %s", index, detail)
	case InvalidOrdering(index, detail): return fmt.Sprintf("gotp/release: instruction %d has invalid ordering: %s", index, detail)
	case DuplicateStagedModule(module): return "gotp/release: module staged more than once: " + module
	case UnstagedModule(module): return "gotp/release: load references unstaged module: " + module
	}
}

// assayxport:unit gotp.otp.release-script
func ParseScript(value term.Term) result.Result[Script, ScriptFailure] {
	var encoded []term.Term
	match value {
	case term.ProperListTerm(items): encoded = items
	case _: return result.Err[Script, ScriptFailure](ExpectedInstructionList(value.Kind()))
	}
	instructions := make([]Instruction, len(encoded))
	for index, item := range encoded {
		match parseInstruction(index, item) {
		case result.Err(failure): return result.Err[Script, ScriptFailure](failure)
		case result.Ok(instruction): instructions[index] = instruction
		}
	}
	match validateScript(instructions) {
	case result.Err(failure): return result.Err[Script, ScriptFailure](failure)
	case result.Ok(commit): return result.Ok[Script, ScriptFailure](Script{Instructions: instructions, CommitIndex: commit})
	}
}

func (script Script) Preflight() []Instruction {
	if script.CommitIndex < 0 { return nil }
	return append([]Instruction{}, script.Instructions[:script.CommitIndex]...)
}

func (script Script) Commit() []Instruction {
	if script.CommitIndex < 0 { return append([]Instruction{}, script.Instructions...) }
	return append([]Instruction{}, script.Instructions[script.CommitIndex:]...)
}

func validateScript(instructions []Instruction) result.Result[int, ScriptFailure] {
	commit := -1
	staged := map[string]bool{}
	loading := true
	for index, instruction := range instructions {
		match instruction {
		case RestartNewEmulator:
			if index != 0 { return result.Err[int, ScriptFailure](InvalidOrdering(index, "restart_new_emulator must be first")) }
		case LoadObjectCode(_, _, modules):
			if !loading || commit >= 0 { return result.Err[int, ScriptFailure](InvalidOrdering(index, "load_object_code must precede all committed instructions")) }
			for _, module := range modules { if staged[module] { return result.Err[int, ScriptFailure](DuplicateStagedModule(module)) }; staged[module] = true }
		case PointOfNoReturn:
			if commit >= 0 { return result.Err[int, ScriptFailure](InvalidOrdering(index, "duplicate point_of_no_return")) }
			commit = index; loading = false
		case LoadCode(module, _, _):
			loading = false
			if commit < 0 && len(staged) > 0 { return result.Err[int, ScriptFailure](InvalidOrdering(index, "staged code requires point_of_no_return")) }
			if len(staged) > 0 && !staged[module] { return result.Err[int, ScriptFailure](UnstagedModule(module)) }
		case _:
			loading = false
			if commit < 0 && len(staged) > 0 { return result.Err[int, ScriptFailure](InvalidOrdering(index, "staged code requires point_of_no_return")) }
		}
	}
	if len(staged) > 0 && commit < 0 { return result.Err[int, ScriptFailure](InvalidOrdering(len(instructions), "load_object_code requires point_of_no_return")) }
	return result.Ok[int, ScriptFailure](commit)
}

func parseInstruction(index int, value term.Term) result.Result[Instruction, ScriptFailure] {
	match value {
	case term.AtomTerm(name):
		switch name {
		case "point_of_no_return": return result.Ok[Instruction, ScriptFailure](PointOfNoReturn())
		case "restart_emulator": return result.Ok[Instruction, ScriptFailure](RestartEmulator())
		case "restart_new_emulator": return result.Ok[Instruction, ScriptFailure](RestartNewEmulator())
		default: return invalidInstruction(index, "unknown atom instruction " + name)
		}
	case term.TupleTerm(values): return parseTupleInstruction(index, values)
	case _: return invalidInstruction(index, "instruction must be atom or tuple")
	}
}

func parseTupleInstruction(index int, values []term.Term) result.Result[Instruction, ScriptFailure] {
	if len(values) < 2 { return invalidInstruction(index, "tuple instruction is too short") }
	name := atomName(values[0])
	match name {
	case option.None: return invalidInstruction(index, "instruction name is not atom")
	case option.Some(name):
		switch name {
		case "load_object_code":
			if len(values) != 2 { return invalidInstruction(index, "load_object_code arity differs") }
			match triple(values[1]) { case option.None: return invalidInstruction(index, "load_object_code payload differs"); case option.Some(payload):
				match requiredAtom(payload[0], index, "library") { case result.Err(failure): return result.Err[Instruction, ScriptFailure](failure); case result.Ok(library):
					match textValue(payload[1]) { case option.None: return invalidInstruction(index, "library version is not text"); case option.Some(version):
						match atomList(payload[2]) { case option.None: return invalidInstruction(index, "module list differs"); case option.Some(modules): return result.Ok[Instruction, ScriptFailure](LoadObjectCode(library, version, modules)) }
					}
				}
			}
		case "load", "remove": return parseLoadInstruction(index, name, values)
		case "purge", "resume", "stop", "start": return parseModuleListInstruction(index, name, values)
		case "suspend": return parseSuspendInstruction(index, values)
		case "code_change": return parseChangeInstruction(index, values)
		case "sync_nodes": return parseSyncInstruction(index, values)
		case "apply":
			if len(values) != 2 { return invalidInstruction(index, "apply arity differs") }
			match parseMFA(values[1]) { case option.None: return invalidInstruction(index, "apply MFA differs"); case option.Some(call): return result.Ok[Instruction, ScriptFailure](Apply(call)) }
		default: return invalidInstruction(index, "unknown tuple instruction " + name)
		}
	}
}

func parseLoadInstruction(index int, name string, values []term.Term) result.Result[Instruction, ScriptFailure] {
	if len(values) != 2 { return invalidInstruction(index, name + " arity differs") }
	match triple(values[1]) {
	case option.None: return invalidInstruction(index, name + " payload differs")
	case option.Some(payload):
		match requiredAtom(payload[0], index, "module") {
		case result.Err(failure): return result.Err[Instruction, ScriptFailure](failure)
		case result.Ok(module):
			match purgeMethod(payload[1]) { case option.None: return invalidInstruction(index, "pre-purge method differs"); case option.Some(pre):
				match purgeMethod(payload[2]) { case option.None: return invalidInstruction(index, "post-purge method differs"); case option.Some(post):
					if name == "load" { return result.Ok[Instruction, ScriptFailure](LoadCode(module, pre, post)) }
					return result.Ok[Instruction, ScriptFailure](RemoveCode(module, pre, post))
				}
			}
		}
	}
}

func parseModuleListInstruction(index int, name string, values []term.Term) result.Result[Instruction, ScriptFailure] {
	if len(values) != 2 { return invalidInstruction(index, name + " arity differs") }
	match atomList(values[1]) {
	case option.None: return invalidInstruction(index, name + " module list differs")
	case option.Some(modules):
		switch name { case "purge": return result.Ok[Instruction, ScriptFailure](PurgeCode(modules)); case "resume": return result.Ok[Instruction, ScriptFailure](ResumeCode(modules)); case "stop": return result.Ok[Instruction, ScriptFailure](StopCode(modules)); default: return result.Ok[Instruction, ScriptFailure](StartCode(modules)) }
	}
}

func parseSuspendInstruction(index int, values []term.Term) result.Result[Instruction, ScriptFailure] {
	if len(values) != 2 { return invalidInstruction(index, "suspend arity differs") }
	var items []term.Term
	match values[1] { case term.ProperListTerm(found): items = found; case _: return invalidInstruction(index, "suspend targets differ") }
	targets := make([]SuspendTarget, len(items))
	for position, item := range items {
		match atomName(item) {
		case option.Some(module): targets[position] = SuspendTarget{Module: module, Timeout: DefaultTimeout()}
		case option.None:
			match pair(item) { case option.None: return invalidInstruction(index, "suspend target differs"); case option.Some(target):
				match atomName(target[0]) { case option.None: return invalidInstruction(index, "suspend module differs"); case option.Some(module):
					match timeoutValue(target[1]) { case option.None: return invalidInstruction(index, "suspend timeout differs"); case option.Some(timeout): targets[position] = SuspendTarget{Module: module, Timeout: timeout} }
				}
			}
		}
	}
	return result.Ok[Instruction, ScriptFailure](SuspendCode(targets))
}

func parseChangeInstruction(index int, values []term.Term) result.Result[Instruction, ScriptFailure] {
	var mode ChangeMode = Upgrade()
	var encoded term.Term
	if len(values) == 2 { encoded = values[1] } else if len(values) == 3 {
		match atomName(values[1]) { case option.Some(direction): switch direction { case "up": mode = Upgrade(); case "down": mode = Downgrade(); default: return invalidInstruction(index, "code_change mode differs") }; case option.None: return invalidInstruction(index, "code_change mode differs") }
		encoded = values[2]
	} else { return invalidInstruction(index, "code_change arity differs") }
	var items []term.Term
	match encoded { case term.ProperListTerm(found): items = found; case _: return invalidInstruction(index, "code_change targets differ") }
	targets := make([]ChangeTarget, len(items))
	for position, item := range items { match pair(item) { case option.None: return invalidInstruction(index, "code_change target differs"); case option.Some(pair): match atomName(pair[0]) { case option.None: return invalidInstruction(index, "code_change module differs"); case option.Some(module): targets[position] = ChangeTarget{Module: module, Extra: pair[1].Clone()} } } }
	return result.Ok[Instruction, ScriptFailure](ChangeCode(mode, targets))
}

func parseSyncInstruction(index int, values []term.Term) result.Result[Instruction, ScriptFailure] {
	if len(values) != 3 { return invalidInstruction(index, "sync_nodes arity differs") }
	id := values[1].Clone()
	match parseMFA(values[2]) { case option.Some(call): return result.Ok[Instruction, ScriptFailure](SyncNodesApply(id, call)); case option.None: }
	match atomList(values[2]) { case option.Some(nodes): return result.Ok[Instruction, ScriptFailure](SyncNodesList(id, nodes)); case option.None: return invalidInstruction(index, "sync_nodes target differs") }
}

func parseMFA(value term.Term) option.Option[MFA] {
	match triple(value) { case option.None: return option.None[MFA](); case option.Some(values):
		match atomName(values[0]) { case option.None: return option.None[MFA](); case option.Some(module): match atomName(values[1]) { case option.None: return option.None[MFA](); case option.Some(function): match values[2] { case term.ProperListTerm(arguments): cloned := make([]term.Term, len(arguments)); for index, argument := range arguments { cloned[index] = argument.Clone() }; return option.Some(MFA{Module: module, Function: function, Arguments: cloned}); case _: return option.None[MFA]() } } }
	}
}

func purgeMethod(value term.Term) option.Option[PurgeMethod] { match atomName(value) { case option.Some(name): switch name { case "soft_purge": return option.Some[PurgeMethod](SoftPurge()); case "brutal_purge": return option.Some[PurgeMethod](BrutalPurge()) }; case option.None: }; return option.None[PurgeMethod]() }

func timeoutValue(value term.Term) option.Option[SuspendTimeout] { match atomName(value) { case option.Some(name): switch name { case "default": return option.Some[SuspendTimeout](DefaultTimeout()); case "infinity": return option.Some[SuspendTimeout](InfiniteTimeout()) }; case option.None: }; match term.Int64(value) { case option.Some(milliseconds): if milliseconds >= 0 { return option.Some[SuspendTimeout](FiniteTimeout(milliseconds)) }; case option.None: }; return option.None[SuspendTimeout]() }

func atomList(value term.Term) option.Option[[]string] { match value { case term.ProperListTerm(items): modules := make([]string, len(items)); for index, item := range items { match atomName(item) { case option.None: return option.None[[]string](); case option.Some(module): modules[index] = module } }; return option.Some(modules); case _: return option.None[[]string]() } }
func atomName(value term.Term) option.Option[string] { match value { case term.AtomTerm(name): if name != "" { return option.Some(name) }; case _: }; return option.None[string]() }
func pair(value term.Term) option.Option[[]term.Term] { match value { case term.TupleTerm(items): if len(items) == 2 { return option.Some(items) }; case _: }; return option.None[[]term.Term]() }
func triple(value term.Term) option.Option[[]term.Term] { match value { case term.TupleTerm(items): if len(items) == 3 { return option.Some(items) }; case _: }; return option.None[[]term.Term]() }

func textValue(value term.Term) option.Option[string] {
	match value {
	case term.BinaryTerm(bytes): return option.Some(string(bytes))
	case term.ProperListTerm(items):
		var text strings.Builder
		for _, item := range items { match term.Int64(item) { case option.Some(character): if character < 0 || character > 255 { return option.None[string]() }; text.WriteByte(byte(character)); case option.None: return option.None[string]() } }
		return option.Some(text.String())
	case _: return option.None[string]()
	}
}

func requiredAtom(value term.Term, index int, role string) result.Result[string, ScriptFailure] { match atomName(value) { case option.None: return result.Err[string, ScriptFailure](InvalidInstruction(index, role + " is not atom")); case option.Some(name): return result.Ok[string, ScriptFailure](name) } }
func invalidInstruction(index int, detail string) result.Result[Instruction, ScriptFailure] { return result.Err[Instruction, ScriptFailure](InvalidInstruction(index, detail)) }

func StagedModules(script Script) []string { staged := []string{}; for _, instruction := range script.Preflight() { match instruction { case LoadObjectCode(_, _, modules): staged = append(staged, modules...); case _: } }; sort.Strings(staged); return staged }
