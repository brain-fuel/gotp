package mnesia

import (
	"sync"
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func mustCreateTable(t *testing.T, database *Database, name string) {
	match database.CreateTable(name) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
}

func mustDirtyRead(t *testing.T, database *Database, table string, key term.Term) option.Option[term.Term] {
	match database.DirtyRead(table, key) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(value):
		return value
	}
	panic("unreachable")
}

func writeOrAbort(transaction *Transaction, table string, key term.Term, value term.Term) option.Option[term.Term] {
	match transaction.Write(table, key, value) {
	case result.Err(failure):
		return option.Some[term.Term](term.Binary([]byte(failure.Error())))
	case result.Ok(_):
		return option.None[term.Term]
	}
}

func seedAccount(transaction *Transaction) TransactionDecision {
	match writeOrAbort(transaction, "accounts", term.MustAtom("alice"), term.Integer(10)) {
	case option.Some(reason):
		return DecideAbort(reason)
	case option.None:
		return DecideCommit(term.MustAtom("true"))
	}
}

func rollbackAccount(transaction *Transaction) TransactionDecision {
	match writeOrAbort(transaction, "accounts", term.MustAtom("alice"), term.Integer(99)) {
	case option.Some(reason):
		return DecideAbort(reason)
	case option.None:
	}
	match transaction.Delete("accounts", term.MustAtom("alice")) {
	case result.Err(failure):
		return DecideAbort(term.Binary([]byte(failure.Error())))
	case result.Ok(_):
		return DecideAbort(term.MustAtom("rollback"))
	}
}

func writeAndReadState(transaction *Transaction) TransactionDecision {
	match writeOrAbort(transaction, "state", term.List(term.Integer(1)), term.Tuple(term.MustAtom("value"), term.Integer(7))) {
	case option.Some(reason):
		return DecideAbort(reason)
	case option.None:
	}
	match transaction.Read("state", term.List(term.Integer(1))) {
	case result.Err(failure):
		return DecideAbort(term.Binary([]byte(failure.Error())))
	case result.Ok(found):
		match found {
		case option.None:
			return DecideAbort(term.MustAtom("missing"))
		case option.Some(value):
			return DecideCommit(value)
		}
	}
}

func seedCounter(transaction *Transaction) TransactionDecision {
	match writeOrAbort(transaction, "counters", term.MustAtom("count"), term.Integer(0)) {
	case option.Some(reason):
		return DecideAbort(reason)
	case option.None:
		return DecideCommit(term.MustAtom("true"))
	}
}

var retainedTransaction *Transaction

func retainTransaction(transaction *Transaction) TransactionDecision {
	retainedTransaction = transaction
	return DecideCommit(term.MustAtom("true"))
}

// assayxport:law gotp.otp.mnesia-transaction-laws
func TestAbortRollsBackWritesAndDeletes(t *testing.T) {
	database := NewDatabase()
	mustCreateTable(t, database, "accounts")
	match Run(database, seedAccount) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	match Run(database, rollbackAccount) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	match mustDirtyRead(t, database, "accounts", term.MustAtom("alice")) {
	case option.None:
		t.Fatal("rollback deleted value")
	case option.Some(value):
		if !term.Equal(value, term.Integer(10)) {
			t.Fatalf("rollback value = %v", value)
		}
	}
}

func TestTransactionReadsItsOwnWrites(t *testing.T) {
	database := NewDatabase()
	mustCreateTable(t, database, "state")
	match Run(database, writeAndReadState) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(outcome):
		var checked TransactionOutcome = outcome
		match checked {
		case Aborted(reason):
			t.Fatalf("transaction aborted: %v", reason)
		case Committed(value):
			if !term.Equal(value, term.Tuple(term.MustAtom("value"), term.Integer(7))) {
				t.Fatalf("commit = %v", value)
			}
		}
	}
}

func TestConcurrentTransactionsAreSerializable(t *testing.T) {
	database := NewDatabase()
	mustCreateTable(t, database, "counters")
	match Run(database, seedCounter) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	const writers = 64
	var group sync.WaitGroup
	for index := 0; index < writers; index++ {
		group.Add(1)
		go func() {
			defer group.Done()
			match Run(database, incrementCounter) {
			case result.Err(failure):
				t.Errorf("transaction: %v", failure)
			case result.Ok(_):
			}
		}()
	}
	group.Wait()
	match mustDirtyRead(t, database, "counters", term.MustAtom("count")) {
	case option.None:
		t.Fatal("counter missing")
	case option.Some(value):
		if !term.Equal(value, term.Integer(writers)) {
			t.Fatalf("counter = %v", value)
		}
	}
}

func incrementCounter(transaction *Transaction) TransactionDecision {
	match transaction.Read("counters", term.MustAtom("count")) {
	case result.Err(failure):
		return DecideAbort(term.Binary([]byte(failure.Error())))
	case result.Ok(found):
		match found {
		case option.None:
			return DecideAbort(term.MustAtom("missing"))
		case option.Some(value):
			match term.Int64(value) {
			case option.None:
				return DecideAbort(term.MustAtom("not_integer"))
			case option.Some(current):
				match writeOrAbort(transaction, "counters", term.MustAtom("count"), term.Integer(current + 1)) {
				case option.Some(reason):
					return DecideAbort(reason)
				case option.None:
					return DecideCommit(term.MustAtom("true"))
				}
			}
		}
	}
}

func TestRetainedTransactionHandleBecomesInactive(t *testing.T) {
	database := NewDatabase()
	mustCreateTable(t, database, "state")
	retainedTransaction = nil
	match Run(database, retainTransaction) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	match retainedTransaction.Write("state", term.MustAtom("late"), term.Integer(1)) {
	case result.Ok(_):
		t.Fatal("retained transaction remained active")
	case result.Err(_):
	}
}
