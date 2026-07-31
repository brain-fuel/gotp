package release

import (
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func releaseApp(name string, version string) ApplicationSpec { return ApplicationSpec{Name: name, Version: version, Type: "permanent", Modules: []string{name + "_server"}} }
func marker(script []term.Term) string { if len(script) == 0 { return "" }; match script[0] { case term.AtomTerm(name): return name; case term.TupleTerm(fields): if len(fields) > 0 { match fields[0] { case term.AtomTerm(name): return name; case _: } }; case _: }; return "" }

// assayxport:law gotp.otp.relup-delta-laws
func TestRelupDeltaUsesPinnedUpgradeOrdering(t *testing.T) {
	top := ReleaseSpec{Name: "sample", Version: "2", ERTSVersion: "15", Applications: []ApplicationSpec{releaseApp("added", "1"), releaseApp("changed", "2")}}
	base := ReleaseSpec{Name: "sample", Version: "1", ERTSVersion: "14", Applications: []ApplicationSpec{releaseApp("changed", "1"), releaseApp("removed", "1")}}
	changed := Appup{CurrentVersion: "2", Up: []AppupEntry{{Selector: ExactVersion("1"), Instructions: []term.Term{term.MustAtom("changed")}}}}
	match BuildRelupDelta(top, base, UpgradeScripts(), "upgrade", map[string]Appup{"changed": changed}, RelupOptions{RestartEmulator: true}) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(delta):
		want := []string{"restart_new_emulator", "add_application", "changed", "remove_application", "restart_emulator"}
		if len(delta.HighLevelScripts) != len(want) { t.Fatalf("scripts = %d", len(delta.HighLevelScripts)) }
		for index, expected := range want { if found := marker(delta.HighLevelScripts[index]); found != expected { t.Fatalf("script %d = %s; want %s", index, found, expected) } }
	}
}

func TestRelupDeltaReversesApplicationSetChangesForDowngrade(t *testing.T) {
	top := ReleaseSpec{Name: "sample", Version: "2", ERTSVersion: "15", Applications: []ApplicationSpec{releaseApp("top_only", "1"), releaseApp("changed", "2")}}
	base := ReleaseSpec{Name: "sample", Version: "1", ERTSVersion: "15", Applications: []ApplicationSpec{releaseApp("changed", "1"), releaseApp("base_only", "1")}}
	changed := Appup{CurrentVersion: "2", Down: []AppupEntry{{Selector: ExactVersion("1"), Instructions: []term.Term{term.MustAtom("changed_down")}}}}
	match BuildRelupDelta(top, base, DowngradeScripts(), "downgrade", map[string]Appup{"changed": changed}, RelupOptions{}) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(delta):
		want := []string{"add_application", "changed_down", "remove_application"}
		for index, expected := range want { if found := marker(delta.HighLevelScripts[index]); found != expected { t.Fatalf("script %d = %s; want %s", index, found, expected) } }
	}
}

func TestRelupDeltaRejectsUnexplainedChange(t *testing.T) {
	top := ReleaseSpec{Name: "sample", Version: "2", ERTSVersion: "15", Applications: []ApplicationSpec{releaseApp("changed", "2")}}
	base := ReleaseSpec{Name: "sample", Version: "1", ERTSVersion: "15", Applications: []ApplicationSpec{releaseApp("changed", "1")}}
	match BuildRelupDelta(top, base, UpgradeScripts(), "", map[string]Appup{}, RelupOptions{}) { case result.Err(MissingApplicationAppup): case _: t.Fatal("missing appup was accepted") }
}
