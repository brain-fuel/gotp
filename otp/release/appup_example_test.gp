package release

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func appupString(value string) term.Term { characters := make([]term.Term, len(value)); for index, character := range []byte(value) { characters[index] = term.Integer(int64(character)) }; return term.List(characters...) }
func appupEntry(selector term.Term, marker string) term.Term { return term.Tuple(selector, term.List(term.MustAtom(marker))) }

// assayxport:law gotp.otp.appup-laws
func TestAppupSelectionPreservesPinnedOrderingAndDirection(t *testing.T) {
	encoded := term.Tuple(
		appupString("3.0.0"),
		term.List(appupEntry(term.Binary([]byte("2\\..*")), "pattern"), appupEntry(appupString("2.1.0"), "exact_later")),
		term.List(appupEntry(appupString("4.0.0"), "down")),
	)
	match ParseAppup(encoded) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(appup):
		match appup.Select(UpgradeScripts(), "2.1.0") { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(script): match script[0] { case term.AtomTerm(name): if name != "pattern" { t.Fatalf("selected %s", name) }; case _: t.Fatal("marker differs") } }
		match appup.Select(DowngradeScripts(), "4.0.0") { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(script): if len(script) != 1 { t.Fatalf("down script length = %d", len(script)) } }
	}
}

func TestAppupRegexMustMatchWholeVersionAndBeValid(t *testing.T) {
	partial := term.Tuple(appupString("2"), term.List(appupEntry(term.Binary([]byte("2\\.1")), "partial")), term.List())
	match ParseAppup(partial) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(appup): match appup.Select(UpgradeScripts(), "12.1.0") { case result.Err(MissingVersionScript): case _: t.Fatal("partial regex match was accepted") } }
	invalid := term.Tuple(appupString("2"), term.List(appupEntry(term.Binary([]byte("[")), "bad")), term.List())
	match ParseAppup(invalid) { case result.Err(InvalidVersionPattern): case _: t.Fatal("invalid regex was accepted") }
}

func TestAppupParserNeverPanics(t *testing.T) {
	law := func(raw []byte) bool { if len(raw) > 4096 { raw = raw[:4096] }; ParseAppup(term.Binary(raw)); return true }
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2000})) { case result.Err(cause): t.Fatal(cause); case result.Ok(_): }
}
