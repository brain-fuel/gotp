package release

import (
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

// assayxport:unit gotp.otp.systools-rc-parser
func ParseHighScripts(encoded [][]term.Term) result.Result[[][]HighInstruction, TranslationFailure] {
	scripts := make([][]HighInstruction, len(encoded)); offset := 0
	for scriptIndex, values := range encoded {
		parsed := make([]HighInstruction, 0, len(values)); commit := -1
		for index, value := range values {
			isCommit := false; match value { case term.AtomTerm(name): isCommit = name == "point_of_no_return"; case _: }
			if isCommit { if commit >= 0 { return invalidHigh(offset+index, "duplicate point_of_no_return") }; commit = len(parsed); continue }
			match parseHighInstruction(offset+index, value) { case result.Err(failure): return result.Err[[][]HighInstruction, TranslationFailure](failure); case result.Ok(instruction): parsed = append(parsed, instruction) }
		}
		if commit >= 0 { for index := 0; index < commit; index++ { match parsed[index] { case LowLevel(low): match low { case LoadObjectCode(_, _, _): parsed[index] = BeforeCommit(low); case Apply(_): parsed[index] = BeforeCommit(low); case _: return invalidHigh(offset+index, "only load_object_code and apply may precede point_of_no_return") }; case _: return invalidHigh(offset+index, "high-level operation precedes point_of_no_return") } } }
		scripts[scriptIndex] = parsed; offset += len(values)
	}
	return result.Ok[[][]HighInstruction, TranslationFailure](scripts)
}

func CompileRelupDelta(direction AppupDirection, delta RelupDelta, applications []ApplicationSpec, previous []ApplicationSpec) result.Result[Script, TranslationFailure] {
	match ParseHighScripts(delta.HighLevelScripts) { case result.Err(failure): return result.Err[Script, TranslationFailure](failure); case result.Ok(scripts): return TranslateScripts(direction, scripts, applications, previous) }
}

func parseHighInstruction(index int, encoded term.Term) result.Result[HighInstruction, TranslationFailure] {
	match encoded {
	case term.AtomTerm(name):
		switch name { case "mnesia_backup": return invalidHighInstruction(index, "mnesia_backup is not implemented by pinned OTP"); case "restart", "reboot": return invalidHighInstruction(index, "legacy restart atom has no low-level translation"); default: }
	case term.TupleTerm(fields):
		if len(fields) > 0 { match atomName(fields[0]) { case option.Some(name): switch name {
			case "update": return parseUpdate(index, fields)
			case "load_module": return parseLoadModule(index, fields)
			case "add_module": return parseModuleDependency(index, fields, true)
			case "delete_module": return parseModuleDependency(index, fields, false)
			case "add_application": return parseAddApplication(index, fields)
			case "remove_application", "restart_application": if len(fields) != 2 { return invalidHighInstruction(index, name + " arity differs") }; match atomName(fields[1]) { case option.None: return invalidHighInstruction(index, "application is not atom"); case option.Some(application): if name == "remove_application" { return validHigh(RemoveApplication(application)) }; return validHigh(RestartApplication(application)) }
		}; case option.None: } }
	case _: return invalidHighInstruction(index, "instruction is neither atom nor tuple")
	}
	match parseInstruction(index, encoded) { case result.Ok(instruction): return validHigh(LowLevel(instruction)); case result.Err(failure): return invalidHighInstruction(index, failure.Error()) }
}

func parseUpdate(index int, fields []term.Term) result.Result[HighInstruction, TranslationFailure] {
	if len(fields) < 2 { return invalidHighInstruction(index, "update arity differs") }
	match atomName(fields[1]) { case option.None: return invalidHighInstruction(index, "update module is not atom"); case option.Some(module):
		var class ModuleClass = DynamicModule(); var timeout SuspendTimeout = DefaultTimeout(); var change ChangeSpec = SoftChange(); var pre PurgeMethod = BrutalPurge(); var post PurgeMethod = BrutalPurge(); dependencies := []string{}
		switch len(fields) {
		case 2:
		case 3:
			match atomName(fields[2]) { case option.Some(name): if name == "supervisor" { class = StaticModule(); change = AdvancedChange(term.List()) } else { return invalidHighInstruction(index, "update shorthand differs") }; case option.None: match atomList(fields[2]) { case option.Some(found): dependencies = found; case option.None: match highChange(fields[2]) { case option.Some(found): change = found; case option.None: return invalidHighInstruction(index, "update shorthand differs") } } }
		case 4: match highChange(fields[2]) { case option.None: return invalidHighInstruction(index, "update change differs"); case option.Some(found): change = found }; match atomList(fields[3]) { case option.None: return invalidHighInstruction(index, "update dependencies differ"); case option.Some(found): dependencies = found }
		case 6: match highChange(fields[2]) { case option.None: return invalidHighInstruction(index, "update change differs"); case option.Some(found): change = found }; match highPurgePair(fields[3], fields[4]) { case option.None: return invalidHighInstruction(index, "update purge differs"); case option.Some(pair): pre = pair[0]; post = pair[1] }; match atomList(fields[5]) { case option.None: return invalidHighInstruction(index, "update dependencies differ"); case option.Some(found): dependencies = found }
		case 7: match highTimeout(fields[2]) { case option.None: return invalidHighInstruction(index, "update timeout differs"); case option.Some(found): timeout = found }; match highChange(fields[3]) { case option.None: return invalidHighInstruction(index, "update change differs"); case option.Some(found): change = found }; match highPurgePair(fields[4], fields[5]) { case option.None: return invalidHighInstruction(index, "update purge differs"); case option.Some(pair): pre = pair[0]; post = pair[1] }; match atomList(fields[6]) { case option.None: return invalidHighInstruction(index, "update dependencies differ"); case option.Some(found): dependencies = found }
		case 8: match highClass(fields[2]) { case option.None: return invalidHighInstruction(index, "update module class differs"); case option.Some(found): class = found }; match highTimeout(fields[3]) { case option.None: return invalidHighInstruction(index, "update timeout differs"); case option.Some(found): timeout = found }; match highChange(fields[4]) { case option.None: return invalidHighInstruction(index, "update change differs"); case option.Some(found): change = found }; match highPurgePair(fields[5], fields[6]) { case option.None: return invalidHighInstruction(index, "update purge differs"); case option.Some(pair): pre = pair[0]; post = pair[1] }; match atomList(fields[7]) { case option.None: return invalidHighInstruction(index, "update dependencies differ"); case option.Some(found): dependencies = found }
		default: return invalidHighInstruction(index, "update arity differs")
		}
		return validHigh(UpdateModule(module, class, timeout, change, pre, post, dependencies))
	}
}

func parseLoadModule(index int, fields []term.Term) result.Result[HighInstruction, TranslationFailure] {
	if len(fields) < 2 { return invalidHighInstruction(index, "load_module arity differs") }; match atomName(fields[1]) { case option.None: return invalidHighInstruction(index, "load_module module differs"); case option.Some(module):
		var pre PurgeMethod = BrutalPurge(); var post PurgeMethod = BrutalPurge(); dependencies := []string{}
		if len(fields) == 3 { match atomList(fields[2]) { case option.None: return invalidHighInstruction(index, "load_module dependencies differ"); case option.Some(found): dependencies = found } } else if len(fields) == 5 { match highPurgePair(fields[2], fields[3]) { case option.None: return invalidHighInstruction(index, "load_module purge differs"); case option.Some(pair): pre = pair[0]; post = pair[1] }; match atomList(fields[4]) { case option.None: return invalidHighInstruction(index, "load_module dependencies differ"); case option.Some(found): dependencies = found } } else if len(fields) != 2 { return invalidHighInstruction(index, "load_module arity differs") }
		return validHigh(LoadModule(module, pre, post, dependencies))
	}
}

func parseModuleDependency(index int, fields []term.Term, add bool) result.Result[HighInstruction, TranslationFailure] { if len(fields) != 2 && len(fields) != 3 { return invalidHighInstruction(index, "module instruction arity differs") }; match atomName(fields[1]) { case option.None: return invalidHighInstruction(index, "module is not atom"); case option.Some(module): dependencies := []string{}; if len(fields) == 3 { match atomList(fields[2]) { case option.None: return invalidHighInstruction(index, "dependencies differ"); case option.Some(found): dependencies = found } }; if add { return validHigh(LoadModule(module, BrutalPurge(), BrutalPurge(), dependencies)) }; return validHigh(DeleteModule(module, dependencies)) } }
func parseAddApplication(index int, fields []term.Term) result.Result[HighInstruction, TranslationFailure] { if len(fields) != 2 && len(fields) != 3 { return invalidHighInstruction(index, "add_application arity differs") }; match atomName(fields[1]) { case option.None: return invalidHighInstruction(index, "application is not atom"); case option.Some(application): kind := "permanent"; if len(fields) == 3 { match atomName(fields[2]) { case option.Some(found): switch found { case "none", "load", "temporary", "transient", "permanent": kind = found; default: return invalidHighInstruction(index, "application start type differs") }; case option.None: return invalidHighInstruction(index, "application start type differs") } }; return validHigh(AddApplication(application, kind)) } }

func highChange(value term.Term) option.Option[ChangeSpec] { match atomName(value) { case option.Some(name): if name == "soft" { return option.Some[ChangeSpec](SoftChange()) }; case option.None: }; match value { case term.TupleTerm(fields): if len(fields) == 2 { match atomName(fields[0]) { case option.Some(name): if name == "advanced" { return option.Some[ChangeSpec](AdvancedChange(fields[1].Clone())) }; case option.None: } }; case _: }; return option.None[ChangeSpec]() }
func highClass(value term.Term) option.Option[ModuleClass] { match atomName(value) { case option.Some(name): if name == "dynamic" { return option.Some[ModuleClass](DynamicModule()) }; if name == "static" { return option.Some[ModuleClass](StaticModule()) }; case option.None: }; return option.None[ModuleClass]() }
func highTimeout(value term.Term) option.Option[SuspendTimeout] { match timeoutValue(value) { case option.Some(found): match found { case FiniteTimeout(milliseconds): if milliseconds <= 0 { return option.None[SuspendTimeout]() }; case _: }; return option.Some[SuspendTimeout](found); case option.None: return option.None[SuspendTimeout]() } }
func highPurgePair(left term.Term, right term.Term) option.Option[[]PurgeMethod] { match purgeMethod(left) { case option.None: return option.None[[]PurgeMethod](); case option.Some(pre): match purgeMethod(right) { case option.None: return option.None[[]PurgeMethod](); case option.Some(post): return option.Some([]PurgeMethod{pre, post}) } } }
func validHigh(instruction HighInstruction) result.Result[HighInstruction, TranslationFailure] { return result.Ok[HighInstruction, TranslationFailure](instruction) }
func invalidHighInstruction(index int, detail string) result.Result[HighInstruction, TranslationFailure] { return result.Err[HighInstruction, TranslationFailure](InvalidHighInstruction(index, detail)) }
func invalidHigh(index int, detail string) result.Result[[][]HighInstruction, TranslationFailure] { return result.Err[[][]HighInstruction, TranslationFailure](InvalidHighInstruction(index, detail)) }
