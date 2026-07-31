package release

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.otp.systools-rc-parser-laws
func TestRawRelupCompilesThroughTypedReleaseScript(t *testing.T) {
	update := term.Tuple(term.MustAtom("update"), term.MustAtom("server"), term.Tuple(term.MustAtom("advanced"), term.MustAtom("extra")), term.MustAtom("soft_purge"), term.MustAtom("brutal_purge"), term.List())
	delta := RelupDelta{BaseVersion: "1", HighLevelScripts: [][]term.Term{{update}}}
	applications := []ApplicationSpec{{Name: "sample", Version: "2", Type: "permanent", Modules: []string{"server"}}}
	match CompileRelupDelta(UpgradeScripts(), delta, applications, applications) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(script): if script.CommitIndex != 1 { t.Fatalf("commit = %d", script.CommitIndex) } }
}

func TestRawSystoolsShorthandsAndCommitBoundary(t *testing.T) {
	encoded := [][]term.Term{{
		term.Tuple(term.MustAtom("load_object_code"), term.Tuple(term.MustAtom("sample"), appupString("2"), term.List(term.MustAtom("server")))),
		term.MustAtom("point_of_no_return"),
		term.Tuple(term.MustAtom("load_module"), term.MustAtom("server")),
		term.Tuple(term.MustAtom("add_application"), term.MustAtom("sample")),
	}}
	match ParseHighScripts(encoded) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(scripts):
		preflight := false; match scripts[0][0] { case BeforeCommit(low): match low { case LoadObjectCode(_, _, _): preflight = true; case _: }; case _: }; if !preflight { t.Fatal("preflight load was not typed") }
		defaults := false; match scripts[0][1] { case LoadModule(_, pre, post, _): match pre { case BrutalPurge: match post { case BrutalPurge: defaults = true; case _: }; case _: }; case _: }; if !defaults { t.Fatal("load_module defaults differ") }
	}
}

func TestRawSystoolsParserNeverPanics(t *testing.T) {
	law := func(raw []byte) bool { if len(raw) > 4096 { raw = raw[:4096] }; ParseHighScripts([][]term.Term{{term.Binary(raw)}}); return true }
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2000})) { case result.Err(cause): t.Fatal(cause); case result.Ok(_): }
}
