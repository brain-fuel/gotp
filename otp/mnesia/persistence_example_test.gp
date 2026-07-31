package mnesia

import (
	"os"
	"path/filepath"
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

func mustSaveFile(t *testing.T, database *Database, path string) {
	match SaveFile(database, etf.CanonicalCodec{}, path, 0o600) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
}

// assayxport:law gotp.otp.mnesia-persistence-laws
func TestAtomicFileRoundTripPreservesDatabase(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mnesia.etf")
	source := snapshotDatabase(t, seedSnapshotForward)
	mustSaveFile(t, source, path)
	restored := NewDatabase()
	match LoadFile(restored, etf.CanonicalCodec{}, path) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	match mustDirtyRead(t, restored, "beta", term.MustAtom("key")) {
	case option.None:
		t.Fatal("loaded value is missing")
	case option.Some(value):
		if !term.Equal(value, term.Binary([]byte("value"))) {
			t.Fatalf("loaded value = %v", value)
		}
	}
}

func TestAtomicSaveReplacesPriorSnapshot(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mnesia.etf")
	mustSaveFile(t, snapshotDatabase(t, seedSnapshotForward), path)
	replacement := NewDatabase()
	mustCreateTable(t, replacement, "replacement")
	mustSaveFile(t, replacement, path)
	loaded := NewDatabase()
	match LoadFile(loaded, etf.CanonicalCodec{}, path) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	match loaded.DirtyRead("alpha", term.List(term.Integer(1))) {
	case result.Ok(_):
		t.Fatal("old snapshot survived replacement")
	case result.Err(_):
	}
	match loaded.DirtyRead("replacement", term.MustAtom("missing")) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
}

func TestCorruptFileLoadLeavesDatabaseUnchanged(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mnesia.etf")
	match result.Of(true, os.WriteFile(path, []byte{131, 104}, 0o600)) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
	database := snapshotDatabase(t, seedSnapshotForward)
	before := mustSnapshot(t, database)
	match LoadFile(database, etf.CanonicalCodec{}, path) {
	case result.Ok(_):
		t.Fatal("corrupt file loaded")
	case result.Err(_):
	}
	after := mustSnapshot(t, database)
	if string(before) != string(after) {
		t.Fatal("failed file load changed database")
	}
}

func TestPersistenceReportsMissingParent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing", "mnesia.etf")
	match SaveFile(NewDatabase(), etf.CanonicalCodec{}, path, 0o600) {
	case result.Ok(_):
		t.Fatal("save with missing parent succeeded")
	case result.Err(_):
	}
}
