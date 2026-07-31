package release

import (
	"fmt"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type ModuleClass enum { DynamicModule(); StaticModule() }
type ChangeSpec enum { SoftChange(); AdvancedChange(Extra term.Term) }

type HighInstruction enum {
	UpdateModule(Module string, Class ModuleClass, Timeout SuspendTimeout, Change ChangeSpec, Pre PurgeMethod, Post PurgeMethod, Dependencies []string)
	LoadModule(Module string, Pre PurgeMethod, Post PurgeMethod, Dependencies []string)
	DeleteModule(Module string, Dependencies []string)
	AddApplication(Application string, Type string)
	RemoveApplication(Application string)
	RestartApplication(Application string)
	BeforeCommit(Instruction Instruction)
	LowLevel(Instruction Instruction)
}

type TranslationFailure enum {
	DuplicateModuleInstruction(Module string)
	UndefinedDependency(Module string)
	UnknownApplication(Application string)
	ModuleOutsideApplication(Module string)
	ConflictingApplicationVersions(Application string, Left string, Right string)
	InvalidTranslatedScript(Cause ScriptFailure)
	InvalidHighInstruction(Index int, Detail string)
}

func (failure TranslationFailure) Error() string {
	match failure {
	case DuplicateModuleInstruction(module): return "gotp/release: multiply defined module " + module
	case UndefinedDependency(module): return "gotp/release: undefined dependency " + module
	case UnknownApplication(application): return "gotp/release: unknown application " + application
	case ModuleOutsideApplication(module): return "gotp/release: module is outside every application " + module
	case ConflictingApplicationVersions(application, left, right): return "gotp/release: conflicting versions for " + application + ": " + left + " and " + right
	case InvalidTranslatedScript(cause): return cause.Error()
	case InvalidHighInstruction(index, detail): return "gotp/release: high-level instruction " + fmt.Sprint(index) + ": " + detail
	}
}

type dependentInstruction struct { module string; dependencies []string; instruction HighInstruction; order int }
type translatedGroup struct { before []Instruction; after []Instruction }

// assayxport:unit gotp.otp.systools-rc
func TranslateScripts(direction AppupDirection, scripts [][]HighInstruction, applications []ApplicationSpec, previous []ApplicationSpec) result.Result[Script, TranslationFailure] {
	expanded := []HighInstruction{}
	for _, script := range scripts { for _, instruction := range script { match expandApplicationInstruction(instruction, applications, previous) { case result.Err(failure): return result.Err[Script, TranslationFailure](failure); case result.Ok(found): expanded = append(expanded, found...) } } }
	dependent := map[string]dependentInstruction{}
	for index, instruction := range expanded { candidate := dependencyInstruction(instruction, index); if candidate.module != "" { if _, duplicate := dependent[candidate.module]; duplicate { return result.Err[Script, TranslationFailure](DuplicateModuleInstruction(candidate.module)) }; dependent[candidate.module] = candidate } }
	for _, item := range dependent { for _, dependency := range item.dependencies { if _, present := dependent[dependency]; !present { return result.Err[Script, TranslationFailure](UndefinedDependency(dependency)) } } }
	before := []Instruction{}; after := []Instruction{}; emitted := map[string]bool{}
	for _, instruction := range expanded {
		candidate := dependencyInstruction(instruction, 0)
		if candidate.module != "" {
			module := candidate.module
			if emitted[module] { continue }
			component := dependencyComponent(module, dependent)
			ordered := dependencyOrder(component, dependent)
			for _, member := range component { emitted[member] = true }
			match translateDependencyGroup(direction, ordered, dependent, applications) { case result.Err(failure): return result.Err[Script, TranslationFailure](failure); case result.Ok(group): before = append(before, group.before...); after = append(after, group.after...) }
		} else { match instruction { case BeforeCommit(low): before = append(before, cloneInstruction(low)); case LowLevel(low): after = append(after, cloneInstruction(low)); case _: } }
	}
	match mergeObjectCode(before) { case result.Err(failure): return result.Err[Script, TranslationFailure](failure); case result.Ok(merged): before = merged }
	before, after = relocateRestarts(direction, before, after)
	instructions := append(append(before, PointOfNoReturn()), after...)
	match validateScript(instructions) { case result.Err(failure): return result.Err[Script, TranslationFailure](InvalidTranslatedScript(failure)); case result.Ok(commit): return result.Ok[Script, TranslationFailure](Script{Instructions: instructions, CommitIndex: commit}) }
}

func expandApplicationInstruction(instruction HighInstruction, applications []ApplicationSpec, previous []ApplicationSpec) result.Result[[]HighInstruction, TranslationFailure] {
	match instruction {
	case AddApplication(name, kind):
		match requireApplication(applications, name) { case result.Err(failure): return result.Err[[]HighInstruction, TranslationFailure](failure); case result.Ok(application):
			expanded := []HighInstruction{}; for _, module := range application.Modules { expanded = append(expanded, LoadModule(module, BrutalPurge(), BrutalPurge(), []string{})) }
			if kind == "load" { expanded = append(expanded, LowLevel(Apply(MFA{Module: "application", Function: "load", Arguments: []term.Term{term.MustAtom(name)}}))) } else if kind != "none" { expanded = append(expanded, LowLevel(Apply(MFA{Module: "application", Function: "start", Arguments: []term.Term{term.MustAtom(name), term.MustAtom(kind)}}))) }
			return result.Ok[[]HighInstruction, TranslationFailure](expanded)
		}
	case RemoveApplication(name): return removeApplication(name, previous)
	case RestartApplication(name):
		match removeApplication(name, previous) { case result.Err(failure): return result.Err[[]HighInstruction, TranslationFailure](failure); case result.Ok(removed):
			match expandApplicationInstruction(AddApplication(name, applicationType(applications, name)), applications, previous) { case result.Err(failure): return result.Err[[]HighInstruction, TranslationFailure](failure); case result.Ok(added): return result.Ok[[]HighInstruction, TranslationFailure](append(removed, added...)) }
		}
	case _: return result.Ok[[]HighInstruction, TranslationFailure]([]HighInstruction{instruction})
	}
}

func removeApplication(name string, previous []ApplicationSpec) result.Result[[]HighInstruction, TranslationFailure] {
	match requireApplication(previous, name) { case result.Err(failure): return result.Err[[]HighInstruction, TranslationFailure](failure); case result.Ok(application):
		expanded := []HighInstruction{LowLevel(Apply(MFA{Module: "application", Function: "stop", Arguments: []term.Term{term.MustAtom(name)}}))}
		for _, module := range application.Modules { expanded = append(expanded, LowLevel(RemoveCode(module, BrutalPurge(), BrutalPurge()))) }
		expanded = append(expanded, LowLevel(PurgeCode(append([]string{}, application.Modules...))), LowLevel(Apply(MFA{Module: "application", Function: "unload", Arguments: []term.Term{term.MustAtom(name)}})))
		return result.Ok[[]HighInstruction, TranslationFailure](expanded)
	}
}

func dependencyInstruction(instruction HighInstruction, order int) dependentInstruction {
	match instruction {
	case UpdateModule(module, _, _, _, _, _, dependencies): return dependentInstruction{module: module, dependencies: append([]string{}, dependencies...), instruction: instruction, order: order}
	case LoadModule(module, _, _, dependencies): return dependentInstruction{module: module, dependencies: append([]string{}, dependencies...), instruction: instruction, order: order}
	case DeleteModule(module, dependencies): return dependentInstruction{module: module, dependencies: append([]string{}, dependencies...), instruction: instruction, order: order}
	case _: return dependentInstruction{}
	}
}

func dependencyComponent(root string, items map[string]dependentInstruction) []string {
	seen := map[string]bool{}; queue := []string{root}; component := []string{}
	for len(queue) > 0 { module := queue[0]; queue = queue[1:]; if seen[module] { continue }; seen[module] = true; component = append(component, module); for _, dependency := range items[module].dependencies { if !seen[dependency] { queue = append(queue, dependency) } }; for candidate, item := range items { if containsString(item.dependencies, module) && !seen[candidate] { queue = append(queue, candidate) } } }
	return component
}

func dependencyOrder(component []string, items map[string]dependentInstruction) []string {
	inComponent := map[string]bool{}; for _, module := range component { inComponent[module] = true }
	visiting := map[string]bool{}; visited := map[string]bool{}; ordered := []string{}
	var visit func(string)
	visit = func(module string) { if visited[module] || visiting[module] { return }; visiting[module] = true; ordered = append(ordered, module); for _, dependency := range items[module].dependencies { if inComponent[dependency] { visit(dependency) } }; visiting[module] = false; visited[module] = true }
	for _, module := range component { visit(module) }
	return ordered
}

func translateDependencyGroup(direction AppupDirection, ordered []string, items map[string]dependentInstruction, applications []ApplicationSpec) result.Result[translatedGroup, TranslationFailure] {
	loads := []Instruction{}; updates := []SuspendTarget{}; advanced := []ChangeTarget{}; dynamic := []ChangeTarget{}; static := []ChangeTarget{}; before := []Instruction{}
	for _, module := range ordered {
		match items[module].instruction {
		case UpdateModule(name, class, timeout, change, pre, post, _):
			match moduleLibrary(name, applications) { case result.Err(failure): return result.Err[translatedGroup, TranslationFailure](failure); case result.Ok(library): before = append(before, LoadObjectCode(library.Name, library.Version, []string{name})) }
			updates = append(updates, SuspendTarget{Module: name, Timeout: timeout}); loads = append(loads, LoadCode(name, pre, post))
			match change { case SoftChange: case AdvancedChange(extra): target := ChangeTarget{Module: name, Extra: extra.Clone()}; advanced = append(advanced, target); match class { case DynamicModule: dynamic = append(dynamic, target); case StaticModule: static = append(static, target) } }
		case LoadModule(name, pre, post, _): match moduleLibrary(name, applications) { case result.Err(failure): return result.Err[translatedGroup, TranslationFailure](failure); case result.Ok(library): before = append(before, LoadObjectCode(library.Name, library.Version, []string{name})); loads = append(loads, LoadCode(name, pre, post)) }
		case DeleteModule(name, _): loads = append(loads, RemoveCode(name, BrutalPurge(), BrutalPurge()), PurgeCode([]string{name}))
		case _: 
		}
	}
	after := []Instruction{}; if len(updates) > 0 { after = append(after, SuspendCode(updates)) }
	match direction {
	case UpgradeScripts: reverseInstructions(loads); after = append(after, loads...); if len(advanced) > 0 { after = append(after, ChangeCode(Upgrade(), advanced)) }
	case DowngradeScripts: if len(dynamic) > 0 { after = append(after, ChangeCode(Downgrade(), dynamic)) }; after = append(after, loads...); if len(static) > 0 { after = append(after, ChangeCode(Downgrade(), static)) }
	}
	if len(updates) > 0 { modules := make([]string, len(updates)); for index := range updates { modules[len(updates)-1-index] = updates[index].Module }; after = append(after, ResumeCode(modules)) }
	return result.Ok[translatedGroup, TranslationFailure](translatedGroup{before: before, after: after})
}

func mergeObjectCode(before []Instruction) result.Result[[]Instruction, TranslationFailure] {
	merged := []Instruction{}; positions := map[string]int{}; versions := map[string]string{}
	for _, instruction := range before { match instruction { case LoadObjectCode(library, version, modules):
		if found, present := versions[library]; present && found != version { return result.Err[[]Instruction, TranslationFailure](ConflictingApplicationVersions(library, found, version)) }
		if position, present := positions[library]; present { match merged[position] { case LoadObjectCode(_, _, existing): for _, module := range modules { if !containsString(existing, module) { existing = append(existing, module) } }; merged[position] = LoadObjectCode(library, version, existing); case _: } } else { positions[library] = len(merged); versions[library] = version; merged = append(merged, cloneInstruction(instruction)) }
	case _: merged = append(merged, cloneInstruction(instruction)) } }
	return result.Ok[[]Instruction, TranslationFailure](merged)
}

func relocateRestarts(direction AppupDirection, before []Instruction, after []Instruction) ([]Instruction, []Instruction) {
	newRestart := false; restart := false; kept := []Instruction{}
	for _, instruction := range after { match instruction { case RestartNewEmulator: newRestart = true; case RestartEmulator: restart = true; case _: kept = append(kept, instruction) } }
	if newRestart { match direction { case UpgradeScripts: before = append([]Instruction{RestartNewEmulator()}, before...); case DowngradeScripts: restart = true } }
	if restart { kept = append(kept, RestartEmulator()) }
	return before, kept
}

func moduleLibrary(module string, applications []ApplicationSpec) result.Result[ApplicationSpec, TranslationFailure] { for _, application := range applications { if containsString(application.Modules, module) { return result.Ok[ApplicationSpec, TranslationFailure](application) } }; return result.Err[ApplicationSpec, TranslationFailure](ModuleOutsideApplication(module)) }
func findApplication(applications []ApplicationSpec, name string) (ApplicationSpec, bool) { for _, application := range applications { if application.Name == name { return application, true } }; return ApplicationSpec{}, false }
func applicationType(applications []ApplicationSpec, name string) string { match requireApplication(applications, name) { case result.Ok(application): return application.Type; case result.Err(_): return "" } }
func requireApplication(applications []ApplicationSpec, name string) result.Result[ApplicationSpec, TranslationFailure] { if application, found := findApplication(applications, name); found { return result.Ok[ApplicationSpec, TranslationFailure](application) }; return result.Err[ApplicationSpec, TranslationFailure](UnknownApplication(name)) }
func containsString(values []string, wanted string) bool { for _, value := range values { if value == wanted { return true } }; return false }
func reverseInstructions(values []Instruction) { for left, right := 0, len(values)-1; left < right; left, right = left+1, right-1 { values[left], values[right] = values[right], values[left] } }
