package compat

import (
	"os"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
)

func readInventoryFixture(t *testing.T, path string) []byte {
	data, readError := os.ReadFile(path)
	match result.Of(data, readError) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(data): return data
	}
	panic("unreachable")
}

// assayxport:unit gotp.compat.otp-upstream-inventory-laws
func TestPinnedOTPInventoryAndLedgerCoverage(t *testing.T) {
	match ParseOTPInventory(readInventoryFixture(t, "otp-29.0.4-inventory.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		match Parse(readInventoryFixture(t, "otp-29.0.4.json")) {
		case result.Err(failure): t.Fatal(failure)
		case result.Ok(ledger):
			missing := MissingInventoryCoverage(inventory, ledger)
			if len(missing) != 0 { t.Fatalf("missing coverage starts with %v", missing[:min(len(missing), 10)]) }
		}
	}
}

func TestInventoryRejectsWrongPinAndOrder(t *testing.T) {
	match ParseOTPInventory(readInventoryFixture(t, "otp-29.0.4-inventory.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		inventory.UpstreamCommit = "wrong"
		match ValidateOTPInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("wrong pin was accepted")
		}
		inventory.UpstreamCommit = OTPPinnedCommit
		inventory.SourceUnits[0], inventory.SourceUnits[1] = inventory.SourceUnits[1], inventory.SourceUnits[0]
		match ValidateOTPInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("unsorted source units were accepted")
		}
		inventory.SourceUnits[0], inventory.SourceUnits[1] = inventory.SourceUnits[1], inventory.SourceUnits[0]
		inventory.Modules[0], inventory.Modules[1] = inventory.Modules[1], inventory.Modules[0]
		match ValidateOTPInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("unsorted modules were accepted")
		}
	}
}

func TestInventoryBuilderIsDeterministic(t *testing.T) {
	match ParseOTPInventory(readInventoryFixture(t, "otp-29.0.4-inventory.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		paths := []string{}
		for _, application := range inventory.Applications { paths = append(paths, application.Manifest) }
		for _, module := range inventory.Modules { paths = append(paths, module.SourcePath) }
		for _, unit := range inventory.SourceUnits { paths = append(paths, unit.SourcePath) }
		for left, right := 0, len(paths)-1; left < right; left, right = left+1, right-1 {
			paths[left], paths[right] = paths[right], paths[left]
		}
		match BuildOTPInventory(paths) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(rebuilt):
			if len(rebuilt.Applications) != len(inventory.Applications) || len(rebuilt.Modules) != len(inventory.Modules) || len(rebuilt.SourceUnits) != len(inventory.SourceUnits) {
				t.Fatal("rebuilt inventory counts differ")
			}
			for index := range rebuilt.Modules {
				if rebuilt.Modules[index] != inventory.Modules[index] { t.Fatalf("module %d differs", index) }
			}
			for index := range rebuilt.SourceUnits {
				if rebuilt.SourceUnits[index] != inventory.SourceUnits[index] { t.Fatalf("source unit %d differs", index) }
			}
		}
	}
}

func TestPinnedSourceKindPartition(t *testing.T) {
	match ParseOTPInventory(readInventoryFixture(t, "otp-29.0.4-inventory.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		counts := map[string]int{}
		for _, unit := range inventory.SourceUnits { counts[unit.Kind]++ }
		want := map[string]int{"native": 860, "java": 57, "generator": 14, "header": 50}
		for kind, count := range want {
			if counts[kind] != count { t.Fatalf("%s source count = %d, want %d", kind, counts[kind], count) }
		}
		if len(counts) != len(want) { t.Fatalf("unexpected source kinds: %v", counts) }
	}
}

func TestInventoryParserNeverPanics(t *testing.T) {
	law := func(raw []byte) bool {
		if len(raw) > 4096 { raw = raw[:4096] }
		ParseOTPInventory(raw)
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2000})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}
