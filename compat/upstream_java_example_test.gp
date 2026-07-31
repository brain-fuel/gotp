package compat

import (
	"encoding/binary"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
)

// assayxport:unit gotp.compat.otp-java-api-laws
func TestPinnedJavaAPIInventoryAndCoverage(t *testing.T) {
	match ParseOTPJavaAPIInventory(readInventoryFixture(t, "otp-29.0.4-java-api.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		if inventory.SourceDigest != PinnedJavaSourceDigest || inventory.ClassDigest != PinnedJavaClassDigest { t.Fatal("Java provenance digest differs") }
		counts := map[string]int{}
		visibility := map[string]int{}
		for _, symbol := range inventory.Symbols { counts[symbol.Kind]++; visibility[symbol.Visibility]++ }
		want := map[string]int{"class": 54, "interface": 3, "field": 94, "constructor": 126, "method": 453}
		for kind, count := range want { if counts[kind] != count { t.Fatalf("%s count = %d, want %d", kind, counts[kind], count) } }
		if len(counts) != len(want) { t.Fatalf("unexpected Java kinds: %v", counts) }
		if visibility["public"] != 610 || visibility["protected"] != 120 || len(visibility) != 2 { t.Fatalf("visibility partition differs: %v", visibility) }
		match Parse(readInventoryFixture(t, "otp-29.0.4.json")) {
		case result.Err(failure): t.Fatal(failure)
		case result.Ok(ledger):
			missing := MissingJavaCoverage(inventory, ledger)
			if len(missing) != 0 { t.Fatalf("missing Java coverage starts with %v", missing[:min(len(missing), 10)]) }
		}
	}
}

func TestJavaInventoryRejectsCompilerDigestAndOrderDrift(t *testing.T) {
	match ParseOTPJavaAPIInventory(readInventoryFixture(t, "otp-29.0.4-java-api.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		inventory.Compiler = "different"
		match ValidateOTPJavaAPIInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("different compiler was accepted")
		}
		inventory.Compiler = PinnedJavaCompiler
		inventory.ClassDigest = "different"
		match ValidateOTPJavaAPIInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("different class digest was accepted")
		}
		inventory.ClassDigest = PinnedJavaClassDigest
		inventory.Symbols[0], inventory.Symbols[1] = inventory.Symbols[1], inventory.Symbols[0]
		match ValidateOTPJavaAPIInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("unsorted Java symbols were accepted")
		}
	}
}

func TestJVMClassDecoderPreservesBinaryIdentities(t *testing.T) {
	class := minimalPublicClass()
	match ParseJVMClass("Sample.class", class) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(api):
		if api.Class != "Sample" || len(api.Symbols) != 3 { t.Fatalf("decoded API = %s/%d", api.Class, len(api.Symbols)) }
		identities := map[string]bool{}
		for _, symbol := range api.Symbols { identities[symbol.Kind+":"+symbol.Name+":"+symbol.Descriptor] = true }
		for _, identity := range []string{"class:Sample:extends=java/lang/Object;implements=", "field:value:I", "constructor:<init>:()V"} {
			if !identities[identity] { t.Fatalf("missing %s", identity) }
		}
	}
}

func TestJVMClassDecoderNeverPanics(t *testing.T) {
	law := func(raw []byte) bool {
		if len(raw) > 8192 { raw = raw[:8192] }
		ParseJVMClass("fuzz.class", raw)
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2000})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}

func minimalPublicClass() []byte {
	data := []byte{}
	u1 := func(value byte) { data = append(data, value) }
	u2 := func(value uint16) { word := []byte{0, 0}; binary.BigEndian.PutUint16(word, value); data = append(data, word...) }
	u4 := func(value uint32) { word := []byte{0, 0, 0, 0}; binary.BigEndian.PutUint32(word, value); data = append(data, word...) }
	utf8 := func(value string) { u1(1); u2(uint16(len(value))); data = append(data, []byte(value)...) }
	u4(0xCAFEBABE); u2(0); u2(65); u2(10)
	utf8("Sample"); u1(7); u2(1)
	utf8("java/lang/Object"); u1(7); u2(3)
	utf8("<init>"); utf8("()V"); utf8("Code"); utf8("value"); utf8("I")
	u2(0x0021); u2(2); u2(4); u2(0)
	u2(1); u2(0x0011); u2(8); u2(9); u2(0)
	u2(1); u2(0x0001); u2(5); u2(6); u2(1); u2(7); u4(0)
	u2(0)
	return data
}
