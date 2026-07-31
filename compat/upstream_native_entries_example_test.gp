package compat

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
)

// assayxport:unit gotp.compat.otp-native-entry-laws
func TestPinnedNativeEntryInventoryAndCoverage(t *testing.T) {
	match ParseOTPNativeEntryInventory(readInventoryFixture(t, "otp-29.0.4-native-entries.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		counts := map[string]int{}
		for _, entry := range inventory.Entries { counts[entry.Kind]++ }
		want := map[string]int{"nif-module": 15, "nif-function": 279, "driver-module": 2}
		for kind, count := range want { if counts[kind] != count { t.Fatalf("%s count = %d, want %d", kind, counts[kind], count) } }
		if len(counts) != len(want) { t.Fatalf("unexpected native entry kinds: %v", counts) }
		match Parse(readInventoryFixture(t, "otp-29.0.4.json")) {
		case result.Err(failure): t.Fatal(failure)
		case result.Ok(ledger):
			missing := MissingNativeEntryCoverage(inventory, ledger)
			if len(missing) != 0 { t.Fatalf("missing native coverage starts with %v", missing[:min(len(missing), 10)]) }
		}
	}
}

func TestNativeEntryInventoryRejectsDigestAndOrderDrift(t *testing.T) {
	match ParseOTPNativeEntryInventory(readInventoryFixture(t, "otp-29.0.4-native-entries.json")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(inventory):
		inventory.SourceDigest = "different"
		match ValidateOTPNativeEntryInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("different native source digest was accepted")
		}
		inventory.SourceDigest = PinnedNativeEntrySourceDigest
		inventory.Entries[0], inventory.Entries[1] = inventory.Entries[1], inventory.Entries[0]
		match ValidateOTPNativeEntryInventory(inventory) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("unsorted native entries were accepted")
		}
	}
}

func TestNativeEntryLexerPreservesHooksFlagsAndConditionalIdentity(t *testing.T) {
	source := OTPNativeSource{Application: "sample", SourcePath: "lib/sample/c_src/sample.c", Content: "/* ERL_NIF_INIT(commented, ignored, 0, 0, 0, 0) */\nstatic ErlNifFunc funcs[] = {{\"run\", 2, run, ERL_NIF_DIRTY_JOB_CPU_BOUND}};\n#if ENABLED\nERL_NIF_INIT(sample, funcs, load, NULL, upgrade, unload)\n#else\nERL_NIF_INIT(sample, funcs, load, NULL, upgrade, unload)\n#endif\nDRIVER_INIT(sample_drv) { return 0; }\n"}
	match nativeEntriesFromSource(source) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(found):
		if len(found) != 5 { t.Fatalf("raw native entries = %d, want 5", len(found)) }
		identities := map[string]bool{}
		for _, entry := range found { identities[InventoryNativeEntryID(entry)] = true }
		if len(identities) != 3 { t.Fatalf("semantic native identities = %d, want 3", len(identities)) }
		for _, entry := range found {
			if entry.Kind == "nif-function" && entry.Flags != "ERL_NIF_DIRTY_JOB_CPU_BOUND" { t.Fatalf("flags = %s", entry.Flags) }
			if entry.Kind == "nif-module" && (entry.Load != "load" || entry.Upgrade != "upgrade" || entry.Unload != "unload") { t.Fatalf("hooks differ: %v", entry) }
		}
	}
}

func TestNativeEntryInventoryRejectsConflictingDefinitions(t *testing.T) {
	source := OTPNativeSource{Application: "sample", SourcePath: "lib/sample/c_src/sample.c", Content: "#if A\nstatic ErlNifFunc funcs[] = {{\"run\", 1, run, 0}};\n#else\nstatic ErlNifFunc funcs[] = {{\"run\", 1, run, ERL_NIF_DIRTY_JOB_CPU_BOUND}};\n#endif\nERL_NIF_INIT(sample, funcs, NULL, NULL, NULL, NULL)\n"}
	match BuildOTPNativeEntryInventory([]OTPNativeSource{source}) {
	case result.Err(failure):
		match failure {
		case NativeEntryInventoryRejected(_):
		case NativeEntryJSONRejected(_): t.Fatalf("unexpected failure: %s", failure.Error())
		case NativeEntrySourceRejected(_, _): t.Fatalf("unexpected failure: %s", failure.Error())
		}
	case result.Ok(_): t.Fatal("conflicting NIF flags were accepted")
	}
}

func TestNativeEntryParserNeverPanics(t *testing.T) {
	law := func(raw []byte) bool {
		if len(raw) > 8192 { raw = raw[:8192] }
		nativeEntriesFromSource(OTPNativeSource{Application: "fuzz", SourcePath: "fuzz.c", Content: string(raw)})
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2000})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}
