package mnesia

import (
	"bytes"
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

func seedSnapshotForward(transaction *Transaction) TransactionDecision {
	match writeOrAbort(transaction, "alpha", term.List(term.Integer(2)), term.Tuple(term.MustAtom("two"))) { case option.Some(reason): return DecideAbort(reason); case option.None: }
	match writeOrAbort(transaction, "alpha", term.List(term.Integer(1)), term.Tuple(term.MustAtom("one"))) { case option.Some(reason): return DecideAbort(reason); case option.None: }
	match writeOrAbort(transaction, "beta", term.MustAtom("key"), term.Binary([]byte("value"))) { case option.Some(reason): return DecideAbort(reason); case option.None: return DecideCommit(term.MustAtom("ok")) }
}

func seedSnapshotReverse(transaction *Transaction) TransactionDecision {
	match writeOrAbort(transaction, "beta", term.MustAtom("key"), term.Binary([]byte("value"))) { case option.Some(reason): return DecideAbort(reason); case option.None: }
	match writeOrAbort(transaction, "alpha", term.List(term.Integer(1)), term.Tuple(term.MustAtom("one"))) { case option.Some(reason): return DecideAbort(reason); case option.None: }
	match writeOrAbort(transaction, "alpha", term.List(term.Integer(2)), term.Tuple(term.MustAtom("two"))) { case option.Some(reason): return DecideAbort(reason); case option.None: return DecideCommit(term.MustAtom("ok")) }
}

func snapshotDatabase(t *testing.T, seed TransactionEffect) *Database {
	database := NewDatabase(); mustCreateTable(t, database, "alpha"); mustCreateTable(t, database, "beta")
	match Run(database, seed) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
	return database
}

func mustSnapshot(t *testing.T, database *Database) []byte {
	match Snapshot(database, etf.CanonicalCodec{}) { case result.Err(failure): t.Fatal(failure); case result.Ok(payload): return payload }
	panic("unreachable")
}

// assayxport:law gotp.otp.mnesia-snapshot-laws
func TestSnapshotIsDeterministicAcrossInsertionOrder(t *testing.T) {
	left := mustSnapshot(t, snapshotDatabase(t, seedSnapshotForward))
	right := mustSnapshot(t, snapshotDatabase(t, seedSnapshotReverse))
	if !bytes.Equal(left, right) { t.Fatal("snapshot bytes depend on insertion order") }
}

func TestSnapshotRestoreRoundTripArbitraryTerms(t *testing.T) {
	source := snapshotDatabase(t, seedSnapshotForward); payload := mustSnapshot(t, source); restored := NewDatabase()
	match Restore(restored, etf.CanonicalCodec{}, payload) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
	match mustDirtyRead(t, restored, "alpha", term.List(term.Integer(1))) {
	case option.None: t.Fatal("restored key missing")
	case option.Some(value): if !term.Equal(value, term.Tuple(term.MustAtom("one"))) { t.Fatalf("restored value = %v", value) }
	}
	if !bytes.Equal(payload, mustSnapshot(t, restored)) { t.Fatal("restored snapshot is not canonical") }
}

func TestMalformedRestoreLeavesDatabaseUnchanged(t *testing.T) {
	database := snapshotDatabase(t, seedSnapshotForward); before := mustSnapshot(t, database)
	malformed := term.Tuple(term.MustAtom("gotp_mnesia_snapshot"), term.Integer(99), term.List())
	var payload []byte
	codec := etf.CanonicalCodec{}
	match codec.Encode(malformed) { case result.Err(failure): t.Fatal(failure); case result.Ok(encoded): payload = encoded }
	match Restore(database, etf.CanonicalCodec{}, payload) { case result.Ok(_): t.Fatal("malformed snapshot restored"); case result.Err(_): }
	if !bytes.Equal(before, mustSnapshot(t, database)) { t.Fatal("failed restore changed database") }
}

func TestCorruptETFRestoreLeavesDatabaseUnchanged(t *testing.T) {
	database := snapshotDatabase(t, seedSnapshotForward); before := mustSnapshot(t, database)
	match Restore(database, etf.CanonicalCodec{}, []byte{131, 104}) { case result.Ok(_): t.Fatal("corrupt ETF restored"); case result.Err(_): }
	if !bytes.Equal(before, mustSnapshot(t, database)) { t.Fatal("corrupt restore changed database") }
}
