package compat

import (
	"fmt"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
)

// assayxport:unit gotp.compat.otp-public-declaration-laws
func TestPinnedPublicDeclarationInventoryAndCoverage(t *testing.T) {
	match ParseOTPDeclarationInventory(readInventoryFixture(t, "otp-29.0.4-declarations.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		if inventory.SourceDigest != PinnedDeclarationSourceDigest { t.Fatal("source digest differs") }
		counts := map[string]int{}
		for _, declaration := range inventory.Declarations { counts[declaration.Kind]++ }
		want := map[string]int{"function": 38448, "type": 1655, "callback": 335, "optional-callback": 125}
		for kind, count := range want {
			if counts[kind] != count { t.Fatalf("%s count = %d, want %d", kind, counts[kind], count) }
		}
		if len(counts) != len(want) { t.Fatalf("unexpected declaration kinds: %v", counts) }
		match Parse(readInventoryFixture(t, "otp-29.0.4.json")) {
		case result.Err(failure): t.Fatal(failure)
		case result.Ok(ledger):
			missing := MissingDeclarationCoverage(inventory, ledger)
			if len(missing) != 0 { t.Fatalf("missing declaration coverage starts with %v", missing[:min(len(missing), 10)]) }
		}
	}
}

func TestDeclarationInventoryRejectsWrongDigestAndOrder(t *testing.T) {
	match ParseOTPDeclarationInventory(readInventoryFixture(t, "otp-29.0.4-declarations.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		inventory.SourceDigest = "wrong"
		match ValidateOTPDeclarationInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("wrong source digest was accepted")
		}
		inventory.SourceDigest = PinnedDeclarationSourceDigest
		inventory.Declarations[0], inventory.Declarations[1] = inventory.Declarations[1], inventory.Declarations[0]
		match ValidateOTPDeclarationInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("unsorted declarations were accepted")
		}
	}
}

func TestDeclarationLexerDistinguishesCodeFromText(t *testing.T) {
	source := OTPModuleSource{
		Application: "sample", Module: "surface", SourcePath: "lib/sample/src/surface.erl",
		Content: "-export([run/2, '--'/2]).\n-export_type([{state,1}]).\n-callback handle(term(), {term(), term()}) -> ok.\n-optional_callbacks([{'handle',2}]).\n-doc \"\"\"\n-export([not_code/0]).\n\"\"\".\nvalue() -> \"-export([also_not_code/0]).\".\n% -export([commented/0]).\n",
	}
	match declarationsFromSource(source) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(found):
		want := map[string]bool{"function:run/2": true, "function:--/2": true, "type:state/1": true, "callback:handle/2": true, "optional-callback:handle/2": true}
		if len(found) != len(want) { t.Fatalf("found %d declarations, want %d: %v", len(found), len(want), found) }
		for _, declaration := range found {
			key := declaration.Kind + ":" + declaration.Name + "/" + fmt.Sprint(declaration.Arity)
			if !want[key] { t.Fatalf("unexpected declaration %s", key) }
		}
	}
}

func TestDeclarationParserNeverPanics(t *testing.T) {
	law := func(raw []byte) bool {
		if len(raw) > 4096 { raw = raw[:4096] }
		declarationsFromSource(OTPModuleSource{Application: "fuzz", Module: "fuzz", SourcePath: "fuzz.erl", Content: string(raw)})
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2000})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}
