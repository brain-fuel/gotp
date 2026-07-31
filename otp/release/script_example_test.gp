package release

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func tuple(name string, values ...term.Term) term.Term { return term.Tuple(append([]term.Term{term.MustAtom(name)}, values...)...) }
func atoms(values ...string) term.Term { items := make([]term.Term, len(values)); for index, value := range values { items[index] = term.MustAtom(value) }; return term.List(items...) }

// assayxport:law gotp.otp.release-script-laws
func TestPinnedReleaseScriptVocabularyAndTransactionSplit(t *testing.T) {
	encoded := term.List(
		tuple("load_object_code", term.Tuple(term.MustAtom("sample"), term.Binary([]byte("2.0")), atoms("alpha", "beta"))),
		term.MustAtom("point_of_no_return"),
		tuple("suspend", term.List(term.MustAtom("alpha"), term.Tuple(term.MustAtom("beta"), term.MustAtom("infinity")))),
		tuple("load", term.Tuple(term.MustAtom("alpha"), term.MustAtom("soft_purge"), term.MustAtom("brutal_purge"))),
		tuple("code_change", term.MustAtom("up"), term.List(term.Tuple(term.MustAtom("alpha"), term.Tuple(term.MustAtom("extra"), term.Integer(1))))),
		tuple("resume", atoms("alpha", "beta")),
		tuple("sync_nodes", term.MustAtom("phase"), atoms("node1", "node2")),
		tuple("apply", term.Tuple(term.MustAtom("application"), term.MustAtom("start"), term.List(term.MustAtom("sample")))),
		term.MustAtom("restart_emulator"),
	)
	match ParseScript(encoded) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(script):
		if script.CommitIndex != 1 || len(script.Preflight()) != 1 || len(script.Commit()) != 8 { t.Fatalf("split = %d/%d/%d", script.CommitIndex, len(script.Preflight()), len(script.Commit())) }
		staged := StagedModules(script); if len(staged) != 2 || staged[0] != "alpha" || staged[1] != "beta" { t.Fatalf("staged = %v", staged) }
		match script.Instructions[4] { case ChangeCode(Upgrade, targets): if len(targets) != 1 || targets[0].Module != "alpha" { t.Fatalf("change targets = %v", targets) }; case _: t.Fatal("code_change differs") }
	}
}

func TestReleaseScriptRejectsCommitAndStagingDrift(t *testing.T) {
	cases := []term.Term{
		term.List(tuple("load_object_code", term.Tuple(term.MustAtom("sample"), term.Binary([]byte("1")), atoms("alpha")))),
		term.List(term.MustAtom("point_of_no_return"), tuple("load_object_code", term.Tuple(term.MustAtom("sample"), term.Binary([]byte("1")), atoms("alpha")))),
		term.List(tuple("load_object_code", term.Tuple(term.MustAtom("sample"), term.Binary([]byte("1")), atoms("alpha"))), term.MustAtom("point_of_no_return"), tuple("load", term.Tuple(term.MustAtom("beta"), term.MustAtom("soft_purge"), term.MustAtom("soft_purge")))),
	}
	for index, encoded := range cases { match ParseScript(encoded) { case result.Err(_): case result.Ok(_): t.Fatalf("invalid script %d was accepted", index) } }
}

func TestReleaseScriptParserNeverPanics(t *testing.T) {
	law := func(raw []byte) bool { if len(raw) > 4096 { raw = raw[:4096] }; ParseScript(term.Binary(raw)); return true }
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2000})) { case result.Err(cause): t.Fatal(cause); case result.Ok(_): }
}
