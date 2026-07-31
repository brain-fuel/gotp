package mnesia

import (
	"fmt"
	"sync"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type TransactionDecision enum {
	DecideCommit(Value term.Term)
	DecideAbort(Reason term.Term)
}

type TransactionOutcome enum {
	Committed(Value term.Term)
	Aborted(Reason term.Term)
}

type Mutation enum {
	Changed()
	Unchanged()
}

type Failure enum {
	InvalidTableName(Name string)
	DuplicateTable(Name string)
	MissingTable(Name string)
	InactiveTransaction()
	NilTransactionEffect()
}

func (failure Failure) Error() string {
	match failure {
	case InvalidTableName(name):
		return fmt.Sprintf("gotp/mnesia: invalid table name %q", name)
	case DuplicateTable(name):
		return fmt.Sprintf("gotp/mnesia: table %q already exists", name)
	case MissingTable(name):
		return fmt.Sprintf("gotp/mnesia: table %q does not exist", name)
	case InactiveTransaction:
		return "gotp/mnesia: transaction is no longer active"
	case NilTransactionEffect:
		return "gotp/mnesia: transaction effect is nil"
	}
}

type row struct {
	key term.Term
	value term.Term
}

type state struct {
	tables map[string][]row
}

type Database struct {
	mu sync.Mutex
	state state
}

type Transaction struct {
	workspace state
	active bool
}

type TransactionEffect func(*Transaction) TransactionDecision

func NewDatabase() *Database {
	return &Database{state: state{tables: make(map[string][]row)}}
}

// assayxport:unit gotp.otp.mnesia-transactions
func (database *Database) CreateTable(name string) result.Result[Mutation, Failure] {
	if name == "" {
		return result.Err[Mutation, Failure](InvalidTableName(name))
	}
	database.mu.Lock()
	defer database.mu.Unlock()
	if _, duplicate := database.state.tables[name]; duplicate {
		return result.Err[Mutation, Failure](DuplicateTable(name))
	}
	database.state.tables[name] = []row{}
	return result.Ok[Mutation, Failure](Changed())
}

func Run(
	database *Database,
	effect TransactionEffect,
) result.Result[TransactionOutcome, Failure] {
	if effect == nil {
		return result.Err[TransactionOutcome, Failure](NilTransactionEffect())
	}
	database.mu.Lock()
	defer database.mu.Unlock()
	transaction := &Transaction{workspace: cloneState(database.state), active: true}
	decision := effect(transaction)
	transaction.active = false
	var checked TransactionDecision = decision
	match checked {
	case DecideCommit(value):
		database.state = transaction.workspace
		return result.Ok[TransactionOutcome, Failure](Committed(value.Clone()))
	case DecideAbort(reason):
		return result.Ok[TransactionOutcome, Failure](Aborted(reason.Clone()))
	}
}

func (transaction *Transaction) Read(
	table string,
	key term.Term,
) result.Result[option.Option[term.Term], Failure] {
	match transaction.rows(table) {
	case result.Err(failure):
		return result.Err[option.Option[term.Term], Failure](failure)
	case result.Ok(rows):
		for _, candidate := range rows {
			if term.Equal(candidate.key, key) {
				return result.Ok[option.Option[term.Term], Failure](
					option.Some[term.Term](candidate.value.Clone()),
				)
			}
		}
		return result.Ok[option.Option[term.Term], Failure](option.None[term.Term])
	}
}

func (transaction *Transaction) Write(
	table string,
	key term.Term,
	value term.Term,
) result.Result[Mutation, Failure] {
	match transaction.rows(table) {
	case result.Err(failure):
		return result.Err[Mutation, Failure](failure)
	case result.Ok(rows):
		for index, candidate := range rows {
			if term.Equal(candidate.key, key) {
				rows[index] = row{key: key.Clone(), value: value.Clone()}
				transaction.workspace.tables[table] = rows
				return result.Ok[Mutation, Failure](Changed())
			}
		}
		transaction.workspace.tables[table] = append(rows, row{
			key: key.Clone(), value: value.Clone(),
		})
		return result.Ok[Mutation, Failure](Changed())
	}
}

func (transaction *Transaction) Delete(
	table string,
	key term.Term,
) result.Result[Mutation, Failure] {
	match transaction.rows(table) {
	case result.Err(failure):
		return result.Err[Mutation, Failure](failure)
	case result.Ok(rows):
		kept := rows[:0]
		removed := false
		for _, candidate := range rows {
			if term.Equal(candidate.key, key) {
				removed = true
			} else {
				kept = append(kept, candidate)
			}
		}
		transaction.workspace.tables[table] = kept
		if removed {
			return result.Ok[Mutation, Failure](Changed())
		}
		return result.Ok[Mutation, Failure](Unchanged())
	}
}

func (transaction *Transaction) rows(table string) result.Result[[]row, Failure] {
	if transaction == nil || !transaction.active {
		return result.Err[[]row, Failure](InactiveTransaction())
	}
	rows, present := transaction.workspace.tables[table]
	match option.Of(rows, present) {
	case option.None:
		return result.Err[[]row, Failure](MissingTable(table))
	case option.Some(found):
		return result.Ok[[]row, Failure](found)
	}
}

func (database *Database) DirtyRead(
	table string,
	key term.Term,
) result.Result[option.Option[term.Term], Failure] {
	database.mu.Lock()
	defer database.mu.Unlock()
	rows, present := database.state.tables[table]
	match option.Of(rows, present) {
	case option.None:
		return result.Err[option.Option[term.Term], Failure](MissingTable(table))
	case option.Some(found):
		for _, candidate := range found {
			if term.Equal(candidate.key, key) {
				return result.Ok[option.Option[term.Term], Failure](option.Some[term.Term](candidate.value.Clone()))
			}
		}
		return result.Ok[option.Option[term.Term], Failure](option.None[term.Term])
	}
}

func cloneState(source state) state {
	tables := make(map[string][]row, len(source.tables))
	for name, rows := range source.tables {
		cloned := make([]row, len(rows))
		for index, candidate := range rows {
			cloned[index] = row{key: candidate.key.Clone(), value: candidate.value.Clone()}
		}
		tables[name] = cloned
	}
	return state{tables: tables}
}
