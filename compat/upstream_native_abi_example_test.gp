package compat

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
)

// assayxport:unit gotp.compat.otp-native-abi-laws
func TestPinnedNativeABIInventoryAndCoverage(t *testing.T) {
	match ParseOTPNativeABIInventory(readInventoryFixture(t, "otp-29.0.4-native-abi-darwin-arm64.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		bySurface := map[string]int{}
		byKind := map[string]int{}
		names := map[string]bool{}
		for _, symbol := range inventory.Symbols { bySurface[symbol.Surface]++; byKind[symbol.Kind]++; names[symbol.Surface+":"+symbol.Name] = true }
		for surface, count := range map[string]int{"nif": 379, "driver": 216, "ei": 271} { if bySurface[surface] != count { t.Fatalf("%s ABI count = %d, want %d", surface, bySurface[surface], count) } }
		wantKinds := map[string]int{"function": 461, "typedef": 99, "record": 39, "field": 187, "enum": 18, "enum-constant": 60, "variable": 2}
		for kind, count := range wantKinds { if byKind[kind] != count { t.Fatalf("%s ABI count = %d, want %d", kind, byKind[kind], count) } }
		for _, name := range []string{"nif:enif_alloc", "driver:driver_output", "ei:ei_connect"} { if !names[name] { t.Fatalf("missing known ABI symbol %s", name) } }
		for _, name := range []string{"nif:printf", "driver:malloc", "ei:fopen"} { if names[name] { t.Fatalf("system symbol leaked into ABI: %s", name) } }
		match Parse(readInventoryFixture(t, "otp-29.0.4.json")) {
		case result.Err(failure): t.Fatal(failure)
		case result.Ok(ledger):
			missing := MissingNativeABICoverage(inventory, ledger)
			if len(missing) != 0 { t.Fatalf("missing native ABI coverage starts with %v", missing[:min(len(missing), 10)]) }
		}
	}
}

func TestCrossPlatformNativeABIProfilesAndCoverage(t *testing.T) {
	fixtures := map[string]struct{ Path string; Count int; NIF int; Driver int; EI int }{
		PinnedLinuxAMD64ABIProfile: {Path: "otp-29.0.4-native-abi-linux-amd64.json", Count: 855, NIF: 368, Driver: 216, EI: 271},
		PinnedLinuxARM64ABIProfile: {Path: "otp-29.0.4-native-abi-linux-arm64.json", Count: 855, NIF: 368, Driver: 216, EI: 271},
		PinnedWindowsAMD64ABIProfile: {Path: "otp-29.0.4-native-abi-windows-amd64.json", Count: 959, NIF: 370, Driver: 317, EI: 272},
	}
	match Parse(readInventoryFixture(t, "otp-29.0.4.json")) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(ledger):
		for profile, fixture := range fixtures {
			match ParseOTPNativeABIInventory(readInventoryFixture(t, fixture.Path)) {
			case result.Err(failure): t.Fatal(failure.Error())
			case result.Ok(inventory):
				if inventory.Profile != profile || inventory.Compiler != PinnedZigABICompiler || len(inventory.Symbols) != fixture.Count { t.Fatalf("profile pin differs for %s", profile) }
				counts := map[string]int{}
				names := map[string]bool{}
				for _, symbol := range inventory.Symbols { counts[symbol.Surface]++; names[symbol.Surface+":"+symbol.Name] = true }
				if counts["nif"] != fixture.NIF || counts["driver"] != fixture.Driver || counts["ei"] != fixture.EI { t.Fatalf("surface partition differs for %s: %v", profile, counts) }
				if !names["nif:enif_alloc"] || !names["driver:driver_output"] || !names["ei:ei_connect"] { t.Fatalf("known ABI symbol absent for %s", profile) }
				if len(MissingNativeABICoverage(inventory, ledger)) != 0 { t.Fatalf("ledger coverage missing for %s", profile) }
			}
		}
	}
}

func TestNativeABIInventoryRejectsCompilerDigestAndOrderDrift(t *testing.T) {
	match ParseOTPNativeABIInventory(readInventoryFixture(t, "otp-29.0.4-native-abi-darwin-arm64.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		inventory.Compiler = "different"
		match ValidateOTPNativeABIInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("different ABI compiler was accepted")
		}
		inventory.Compiler = PinnedNativeABICompiler
		inventory.SourceDigest = "different"
		match ValidateOTPNativeABIInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("different ABI source digest was accepted")
		}
		inventory.SourceDigest = PinnedNativeABISourceDigest
		inventory.Symbols[0], inventory.Symbols[1] = inventory.Symbols[1], inventory.Symbols[0]
		match ValidateOTPNativeABIInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("unsorted ABI symbols were accepted")
		}
	}
}

func TestClangOwnershipRetainsOTPMacrosAndRejectsSystemIncludes(t *testing.T) {
	unit := ClangASTUnit{Surface: "nif", MainPath: "erts/emulator/beam/erl_nif.h", OwnedPaths: []string{"erts/emulator/beam/erl_nif.h", "erts/emulator/beam/erl_nif_api_funcs.h", "erts/emulator/beam/erl_drv_nif.h"}, JSON: []byte(`{"kind":"TranslationUnitDecl","inner":[{"kind":"FunctionDecl","name":"direct","loc":{"offset":1},"type":{"qualType":"int (void)"}},{"kind":"FunctionDecl","name":"enif_macro","loc":{"spellingLoc":{"offset":1,"includedFrom":{"file":"/otp/erts/emulator/beam/erl_nif.h"}}},"type":{"qualType":"int (int)"}},{"kind":"FunctionDecl","name":"system","loc":{"offset":1,"includedFrom":{"file":"/usr/include/stdio.h"}},"type":{"qualType":"int (void)"}}]}`)}
	match NormalizeClangAST("test-profile", unit) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(symbols):
		if len(symbols) != 2 { t.Fatalf("owned symbols = %d, want 2", len(symbols)) }
		if symbols[0].Name != "direct" || symbols[1].Name != "enif_macro" { t.Fatalf("owned symbols differ: %v", symbols) }
	}
}

func TestClangASTNormalizerNeverPanics(t *testing.T) {
	law := func(raw []byte) bool {
		if len(raw) > 8192 { raw = raw[:8192] }
		NormalizeClangAST("fuzz", ClangASTUnit{Surface: "nif", MainPath: "main.h", OwnedPaths: []string{"main.h"}, JSON: raw})
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2000})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}
