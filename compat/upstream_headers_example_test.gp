package compat

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
)

// assayxport:unit gotp.compat.otp-public-header-laws
func TestPinnedPublicHeaderInventoryAndCoverage(t *testing.T) {
	match ParseOTPHeaderInventory(readInventoryFixture(t, "otp-29.0.4-headers.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		if inventory.SourceDigest != PinnedHeaderSourceDigest { t.Fatal("header source digest differs") }
		counts := map[string]int{}
		for _, declaration := range inventory.Declarations { counts[declaration.Kind]++ }
		want := map[string]int{"macro-object": 10973, "macro-function": 110, "record": 636, "type": 61}
		for kind, count := range want {
			if counts[kind] != count { t.Fatalf("%s count = %d, want %d", kind, counts[kind], count) }
		}
		if len(counts) != len(want) { t.Fatalf("unexpected header kinds: %v", counts) }
		match Parse(readInventoryFixture(t, "otp-29.0.4.json")) {
		case result.Err(failure): t.Fatal(failure)
		case result.Ok(ledger):
			missing := MissingHeaderCoverage(inventory, ledger)
			if len(missing) != 0 { t.Fatalf("missing header coverage starts with %v", missing[:min(len(missing), 10)]) }
		}
	}
}

func TestHeaderInventoryRejectsWrongDigestAndOrder(t *testing.T) {
	match ParseOTPHeaderInventory(readInventoryFixture(t, "otp-29.0.4-headers.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		inventory.SourceDigest = "wrong"
		match ValidateOTPHeaderInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("wrong header source digest was accepted")
		}
		inventory.SourceDigest = PinnedHeaderSourceDigest
		inventory.Declarations[0], inventory.Declarations[1] = inventory.Declarations[1], inventory.Declarations[0]
		match ValidateOTPHeaderInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("unsorted header declarations were accepted")
		}
	}
}

func TestHeaderLexerAndSemanticDeduplication(t *testing.T) {
	source := OTPHeaderSource{Application: "sample", SourcePath: "lib/sample/include/sample.hrl", Content: "-record(state, {value = \"text\"}).\n-define(VALUE, 1).\n-define(VALUE, 2).\n-define(APPLY(A, B), {A, B}).\n-type item(T) :: {item, T}.\n-doc \"\"\"-define(NOT_CODE, true).\"\"\".\n% -record(commented, {}).\n"}
	match headerDeclarationsFromSource(source) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(found):
		if len(found) != 5 { t.Fatalf("raw declaration count = %d, want 5", len(found)) }
		identities := map[string]bool{}
		for _, declaration := range found { identities[InventoryHeaderDeclarationID(declaration)] = true }
		if len(identities) != 4 { t.Fatalf("semantic identity count = %d, want 4", len(identities)) }
	}
}

func TestHeaderParserNeverPanics(t *testing.T) {
	law := func(raw []byte) bool {
		if len(raw) > 4096 { raw = raw[:4096] }
		headerDeclarationsFromSource(OTPHeaderSource{Application: "fuzz", SourcePath: "fuzz.hrl", Content: string(raw)})
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2000})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}
