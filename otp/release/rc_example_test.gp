package release

import (
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.otp.systools-rc-laws
func TestSystoolsRCOrdersUpgradeDependenciesAndBalancesProcesses(t *testing.T) {
	applications := []ApplicationSpec{{Name: "sample", Version: "2", Type: "permanent", Modules: []string{"root", "dependency"}}}
	scripts := [][]HighInstruction{{
		UpdateModule("root", DynamicModule(), DefaultTimeout(), AdvancedChange(term.MustAtom("extra")), SoftPurge(), BrutalPurge(), []string{"dependency"}),
		LoadModule("dependency", BrutalPurge(), BrutalPurge(), []string{}),
	}}
	match TranslateScripts(UpgradeScripts(), scripts, applications, applications) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(script):
		if script.CommitIndex != 1 { t.Fatalf("commit = %d", script.CommitIndex) }
		match script.Instructions[2] { case SuspendCode(targets): if len(targets) != 1 || targets[0].Module != "root" { t.Fatalf("suspend = %v", targets) }; case _: t.Fatal("suspend differs") }
		match script.Instructions[3] { case LoadCode(module, _, _): if module != "dependency" { t.Fatalf("first load = %s", module) }; case _: t.Fatal("dependency was not loaded first") }
		match script.Instructions[len(script.Instructions)-1] { case ResumeCode(modules): if len(modules) != 1 || modules[0] != "root" { t.Fatalf("resume = %v", modules) }; case _: t.Fatal("resume differs") }
	}
}

func TestSystoolsRCExpandsApplicationLifecycle(t *testing.T) {
	current := []ApplicationSpec{{Name: "new_app", Version: "1", Type: "permanent", Modules: []string{"new_server"}}}
	previous := []ApplicationSpec{{Name: "old_app", Version: "1", Type: "permanent", Modules: []string{"old_server"}}}
	scripts := [][]HighInstruction{{AddApplication("new_app", "permanent"), RemoveApplication("old_app")}}
	match TranslateScripts(UpgradeScripts(), scripts, current, previous) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(script): if len(script.Instructions) < 7 { t.Fatalf("expanded script = %d", len(script.Instructions)) } }
}

func TestSystoolsRCRejectsUndefinedAndDuplicateDependencies(t *testing.T) {
	applications := []ApplicationSpec{{Name: "sample", Version: "1", Type: "permanent", Modules: []string{"a", "b"}}}
	undefined := [][]HighInstruction{{LoadModule("a", SoftPurge(), SoftPurge(), []string{"missing"})}}
	match TranslateScripts(UpgradeScripts(), undefined, applications, applications) { case result.Err(UndefinedDependency): case _: t.Fatal("undefined dependency was accepted") }
	duplicate := [][]HighInstruction{{LoadModule("a", SoftPurge(), SoftPurge(), []string{}), DeleteModule("a", []string{})}}
	match TranslateScripts(UpgradeScripts(), duplicate, applications, applications) { case result.Err(DuplicateModuleInstruction): case _: t.Fatal("duplicate module was accepted") }
}
