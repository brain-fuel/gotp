package release

import (
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type ApplicationSpec struct {
	Name string
	Version string
	Type string
	Modules []string
}

type ReleaseSpec struct {
	Name string
	Version string
	ERTSVersion string
	Applications []ApplicationSpec
}

type RelupOptions struct { RestartEmulator bool }

type RelupDelta struct {
	BaseVersion string
	Description string
	HighLevelScripts [][]term.Term
}

type RelupFailure enum {
	InvalidReleaseSpec(Release string, Detail string)
	MissingApplicationAppup(Application string)
	ApplicationAppupFailure(Application string, Cause AppupFailure)
}

func (failure RelupFailure) Error() string {
	match failure {
	case InvalidReleaseSpec(release, detail): return "gotp/release: invalid release " + release + ": " + detail
	case MissingApplicationAppup(application): return "gotp/release: changed application has no appup: " + application
	case ApplicationAppupFailure(application, cause): return "gotp/release: application " + application + ": " + cause.Error()
	}
}

// assayxport:unit gotp.otp.relup-delta
func BuildRelupDelta(top ReleaseSpec, base ReleaseSpec, direction AppupDirection, description string, appups map[string]Appup, options RelupOptions) result.Result[RelupDelta, RelupFailure] {
	match indexApplications(top) { case result.Err(failure): return result.Err[RelupDelta, RelupFailure](failure); case result.Ok(_): }
	match indexApplications(base) {
	case result.Err(failure): return result.Err[RelupDelta, RelupFailure](failure)
	case result.Ok(baseByName):
		from := base; to := top
		match direction { case UpgradeScripts: case DowngradeScripts: from = top; to = base }
		scripts := [][]term.Term{}
		if top.ERTSVersion != base.ERTSVersion { scripts = append(scripts, []term.Term{term.MustAtom("restart_new_emulator")}) }
		for _, application := range to.Applications { if _, present := applicationByName(from.Applications, application.Name); !present { scripts = append(scripts, []term.Term{addApplication(application)}) } }
		for _, application := range top.Applications {
			baseApplication, common := baseByName[application.Name]
			if !common || application.Version == baseApplication.Version { continue }
			appup, present := appups[application.Name]
			if !present { return result.Err[RelupDelta, RelupFailure](MissingApplicationAppup(application.Name)) }
			match appup.Select(direction, baseApplication.Version) {
			case result.Err(failure): return result.Err[RelupDelta, RelupFailure](ApplicationAppupFailure(application.Name, failure))
			case result.Ok(script): scripts = append(scripts, script)
			}
		}
		for _, application := range from.Applications { if _, present := applicationByName(to.Applications, application.Name); !present { scripts = append(scripts, []term.Term{term.Tuple(term.MustAtom("remove_application"), term.MustAtom(application.Name))}) } }
		if options.RestartEmulator { scripts = append(scripts, []term.Term{term.MustAtom("restart_emulator")}) }
		return result.Ok[RelupDelta, RelupFailure](RelupDelta{BaseVersion: base.Version, Description: description, HighLevelScripts: cloneScripts(scripts)})
	}
}

func indexApplications(release ReleaseSpec) result.Result[map[string]ApplicationSpec, RelupFailure] {
	if release.Name == "" || release.Version == "" || release.ERTSVersion == "" { return result.Err[map[string]ApplicationSpec, RelupFailure](InvalidReleaseSpec(release.Name, "name, version, and ERTS version are required")) }
	indexed := map[string]ApplicationSpec{}
	for _, application := range release.Applications {
		if application.Name == "" || application.Version == "" || application.Type == "" { return result.Err[map[string]ApplicationSpec, RelupFailure](InvalidReleaseSpec(release.Name, "application identity is incomplete")) }
		if _, duplicate := indexed[application.Name]; duplicate { return result.Err[map[string]ApplicationSpec, RelupFailure](InvalidReleaseSpec(release.Name, "duplicate application " + application.Name)) }
		indexed[application.Name] = application
	}
	return result.Ok[map[string]ApplicationSpec, RelupFailure](indexed)
}

func applicationByName(applications []ApplicationSpec, name string) (ApplicationSpec, bool) { for _, application := range applications { if application.Name == name { return application, true } }; return ApplicationSpec{}, false }
func addApplication(application ApplicationSpec) term.Term { return term.Tuple(term.MustAtom("add_application"), term.MustAtom(application.Name), term.MustAtom(application.Type)) }
func cloneScripts(scripts [][]term.Term) [][]term.Term { cloned := make([][]term.Term, len(scripts)); for index, script := range scripts { cloned[index] = cloneInstructions(script) }; return cloned }
