package compat

import (
	"strings"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
)

func TestPinnedNativeMacroMatrixAndLedgerCoverage(t *testing.T) {
	fixtures := []string{
		"otp-29.0.4-native-macros-darwin-arm64.json",
		"otp-29.0.4-native-macros-linux-amd64.json",
		"otp-29.0.4-native-macros-linux-arm64.json",
		"otp-29.0.4-native-macros-windows-amd64.json",
	}
	match Parse(readInventoryFixture(t, "otp-29.0.4.json")) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(ledger):
		total := 0
		for _, fixture := range fixtures {
			match ParseOTPNativeMacroInventory(readInventoryFixture(t, fixture)) {
			case result.Err(failure): t.Fatal(failure.Error())
			case result.Ok(inventory):
				total += len(inventory.Macros)
				missing := MissingNativeMacroCoverage(inventory, ledger)
				if len(missing) != 0 { t.Fatalf("%s coverage starts with %s", inventory.Profile, strings.Join(missing[:min(len(missing), 5)], ", ")) }
			}
		}
		if total != 1047 { t.Fatalf("profile-qualified macro count = %d, want 1047", total) }
	}
}

// assayxport:unit gotp.compat.otp-native-macro-laws
func TestNativeMacroInventoryIntersectsOwnershipAndActivation(t *testing.T) {
	headers := []OTPNativeHeader{
		{Surface: "nif", SourcePath: "erts/emulator/beam/erl_nif.h", Content: "#define ERL_NIF_MAJOR_VERSION 2\n#define enif_make_tuple1(env, e1) enif_make_tuple(env, 1, e1)\n#if WINDOWS\n#define ERL_NIF_WINDOWS 1\n#endif\n"},
	}
	active := "#define ERL_NIF_MAJOR_VERSION 2\n#define enif_make_tuple1(env,e1) enif_make_tuple(env,1,e1)\n#define FOREIGN_MACRO secret\n"
	match BuildOTPNativeMacroInventory("linux-amd64-lp64", headers, active) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		if len(inventory.Macros) != 2 { t.Fatalf("macro count = %d, want 2", len(inventory.Macros)) }
		forms := map[string]int{}
		for _, macro := range inventory.Macros { forms[macro.Form]++ }
		if forms["object"] != 1 || forms["function"] != 1 { t.Fatalf("forms = %v", forms) }
		if inventory.Macros[0].Name == "FOREIGN_MACRO" || inventory.Macros[1].Name == "FOREIGN_MACRO" { t.Fatal("foreign macro was inventoried") }
	}
}

func TestNativeMacroParserPreservesVariadicsAndContinuations(t *testing.T) {
	content := "# define CALL(first, ...) first \\\n __VA_ARGS__\n#define EMPTY\n"
	match parseNativeMacroDirectives("fixture.h", content) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(directives):
		if len(directives) != 2 { t.Fatalf("directive count = %d", len(directives)) }
		if directives[0].Name != "CALL" || directives[0].Arity != 2 || !directives[0].Variadic || directives[0].Replacement != "first __VA_ARGS__" { t.Fatalf("variadic directive = %v", directives[0]) }
	}
}

func TestNativeMacroParserNeverPanics(t *testing.T) {
	law := func(raw []byte) bool {
		if len(raw) > 8192 { raw = raw[:8192] }
		parseNativeMacroDirectives("fuzz.h", string(raw))
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2000})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}
