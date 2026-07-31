package ets

import (
	"fmt"
	"math/big"
	"sort"
	"sync"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type TableKind enum {
	Set()
	OrderedSet()
	Bag()
	DuplicateBag()
}

type Access enum {
	Public()
	Protected()
	Private()
}

type TableID struct {
	value uint64
}

func (id TableID) Number() uint64 {
	return id.value
}

type Config struct {
	Name string
	Named bool
	Kind TableKind
	Access Access
	KeyPosition int
}

type Mutation enum {
	Changed()
	Unchanged()
}

type Traversal enum {
	EndOfTable()
	TraversalKey(Value term.Term)
}

type CounterOperation enum {
	AddCounter(Position int, Increment term.Term)
	ThresholdCounter(Position int, Increment term.Term, Threshold term.Term, SetValue term.Term)
}

type Failure enum {
	InvalidName(Name string)
	DuplicateName(Name string)
	InvalidKeyPosition(Position int)
	InvalidObject(Found term.Kind)
	MissingKey(Position int, Arity int)
	MissingTable(ID TableID)
	MissingTraversalKey(Key term.Term)
	MissingCounterKey(Key term.Term)
	InvalidCounterPosition(Position int, Arity int)
	CounterKeyPosition(Position int)
	ExpectedCounterInteger(Position int, Found term.Kind)
	UnsupportedCounterTable(Kind TableKind)
	AccessDenied(Operation string, Caller term.PID)
	NotOwner(Caller term.PID)
	OrderFailure(Cause term.OrderFailure)
}

func (failure Failure) Error() string {
	match failure {
	case InvalidName(name):
		return fmt.Sprintf("gotp/ets: invalid table name %q", name)
	case DuplicateName(name):
		return fmt.Sprintf("gotp/ets: table name %q already exists", name)
	case InvalidKeyPosition(position):
		return fmt.Sprintf("gotp/ets: key position must be positive, got %d", position)
	case InvalidObject(found):
		return fmt.Sprintf("gotp/ets: object must be a tuple, got %v", found)
	case MissingKey(position, arity):
		return fmt.Sprintf("gotp/ets: tuple arity %d has no key position %d", arity, position)
	case MissingTable(id):
		return fmt.Sprintf("gotp/ets: table %d does not exist", id.Number())
	case MissingTraversalKey(key):
		return fmt.Sprintf("gotp/ets: traversal key %v does not exist", key)
	case MissingCounterKey(key):
		return fmt.Sprintf("gotp/ets: counter key %v does not exist", key)
	case InvalidCounterPosition(position, arity):
		return fmt.Sprintf("gotp/ets: counter position %d is outside tuple arity %d", position, arity)
	case CounterKeyPosition(position):
		return fmt.Sprintf("gotp/ets: counter position %d is the table key", position)
	case ExpectedCounterInteger(position, found):
		return fmt.Sprintf("gotp/ets: counter position %d must be integer, got %v", position, found)
	case UnsupportedCounterTable(kind):
		return fmt.Sprintf("gotp/ets: counters unsupported for table kind %T", kind)
	case AccessDenied(operation, caller):
		return fmt.Sprintf("gotp/ets: process %v cannot %s table", caller, operation)
	case NotOwner(caller):
		return fmt.Sprintf("gotp/ets: process %v is not table owner", caller)
	case OrderFailure(cause):
		return fmt.Sprintf("gotp/ets: term order failure: %v", cause)
	}
}

type table struct {
	mu sync.RWMutex
	id TableID
	name string
	owner term.PID
	kind TableKind
	access Access
	keyPosition int
	rows []term.Term
	alive bool
}

type Registry struct {
	mu sync.RWMutex
	next uint64
	tables map[TableID]*table
	names map[string]TableID
}

type keyedObject struct {
	values []term.Term
	key term.Term
}

func NewRegistry() *Registry {
	return &Registry{tables: make(map[TableID]*table), names: make(map[string]TableID)}
}

// assayxport:unit gotp.otp.ets-core
func (registry *Registry) New(
	owner term.PID,
	config Config,
) result.Result[TableID, Failure] {
	if config.Kind == nil {
		config.Kind = Set()
	}
	if config.Access == nil {
		config.Access = Protected()
	}
	if config.KeyPosition == 0 {
		config.KeyPosition = 1
	}
	if config.KeyPosition < 1 {
		return result.Err[TableID, Failure](InvalidKeyPosition(config.KeyPosition))
	}
	if config.Named && config.Name == "" {
		return result.Err[TableID, Failure](InvalidName(config.Name))
	}
	registry.mu.Lock()
	defer registry.mu.Unlock()
	if config.Named {
		if _, duplicate := registry.names[config.Name]; duplicate {
			return result.Err[TableID, Failure](DuplicateName(config.Name))
		}
	}
	registry.next++
	id := TableID{value: registry.next}
	created := &table{
		id: id, name: config.Name, owner: owner, kind: config.Kind,
		access: config.Access, keyPosition: config.KeyPosition, alive: true,
	}
	registry.tables[id] = created
	if config.Named {
		registry.names[config.Name] = id
	}
	return result.Ok[TableID, Failure](id)
}

func (registry *Registry) Whereis(name string) option.Option[TableID] {
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	id, present := registry.names[name]
	return option.Of(id, present)
}

func (registry *Registry) All() []TableID {
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	ids := make([]TableID, 0, len(registry.tables))
	for id := range registry.tables {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(left, right int) bool { return ids[left].value < ids[right].value })
	return ids
}

func (registry *Registry) Insert(
	caller term.PID,
	id TableID,
	object term.Term,
) result.Result[Mutation, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[Mutation, Failure](MissingTable(id))
	case option.Some(found):
		return found.insert(caller, object)
	}
}

func (registry *Registry) InsertNew(
	caller term.PID,
	id TableID,
	object term.Term,
) result.Result[bool, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[bool, Failure](MissingTable(id))
	case option.Some(found):
		return found.insertNew(caller, object)
	}
}

func (registry *Registry) Lookup(
	caller term.PID,
	id TableID,
	key term.Term,
) result.Result[[]term.Term, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[[]term.Term, Failure](MissingTable(id))
	case option.Some(found):
		return found.lookup(caller, key)
	}
}

func (registry *Registry) Member(
	caller term.PID,
	id TableID,
	key term.Term,
) result.Result[bool, Failure] {
	match registry.Lookup(caller, id, key) {
	case result.Err(failure):
		return result.Err[bool, Failure](failure)
	case result.Ok(objects):
		return result.Ok[bool, Failure](len(objects) > 0)
	}
}

func (registry *Registry) DeleteKey(
	caller term.PID,
	id TableID,
	key term.Term,
) result.Result[Mutation, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[Mutation, Failure](MissingTable(id))
	case option.Some(found):
		return found.deleteKey(caller, key)
	}
}

func (registry *Registry) DeleteObject(
	caller term.PID,
	id TableID,
	object term.Term,
) result.Result[Mutation, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[Mutation, Failure](MissingTable(id))
	case option.Some(found):
		return found.deleteObject(caller, object)
	}
}

func (registry *Registry) Take(
	caller term.PID,
	id TableID,
	key term.Term,
) result.Result[[]term.Term, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[[]term.Term, Failure](MissingTable(id))
	case option.Some(found):
		return found.take(caller, key)
	}
}

func (registry *Registry) UpdateCounter(
	caller term.PID,
	id TableID,
	key term.Term,
	operation CounterOperation,
) result.Result[term.Term, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[term.Term, Failure](MissingTable(id))
	case option.Some(found):
		return found.updateCounter(caller, key, operation)
	}
}

func (registry *Registry) Objects(
	caller term.PID,
	id TableID,
) result.Result[[]term.Term, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[[]term.Term, Failure](MissingTable(id))
	case option.Some(found):
		return found.objects(caller)
	}
}

func (registry *Registry) First(
	caller term.PID,
	id TableID,
) result.Result[Traversal, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[Traversal, Failure](MissingTable(id))
	case option.Some(found):
		return found.edge(caller, true)
	}
}

func (registry *Registry) Last(
	caller term.PID,
	id TableID,
) result.Result[Traversal, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[Traversal, Failure](MissingTable(id))
	case option.Some(found):
		return found.edge(caller, false)
	}
}

func (registry *Registry) Next(
	caller term.PID,
	id TableID,
	key term.Term,
) result.Result[Traversal, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[Traversal, Failure](MissingTable(id))
	case option.Some(found):
		return found.navigate(caller, key, true)
	}
}

func (registry *Registry) Prev(
	caller term.PID,
	id TableID,
	key term.Term,
) result.Result[Traversal, Failure] {
	match registry.table(id) {
	case option.None:
		return result.Err[Traversal, Failure](MissingTable(id))
	case option.Some(found):
		return found.navigate(caller, key, false)
	}
}

func (registry *Registry) DeleteTable(
	caller term.PID,
	id TableID,
) result.Result[Mutation, Failure] {
	registry.mu.Lock()
	defer registry.mu.Unlock()
	found, present := registry.tables[id]
	if !present {
		return result.Err[Mutation, Failure](MissingTable(id))
	}
	found.mu.Lock()
	defer found.mu.Unlock()
	if found.owner != caller {
		return result.Err[Mutation, Failure](NotOwner(caller))
	}
	found.alive = false
	found.rows = nil
	delete(registry.tables, id)
	if found.name != "" {
		delete(registry.names, found.name)
	}
	return result.Ok[Mutation, Failure](Changed())
}

func (registry *Registry) OwnerExit(owner term.PID) int {
	registry.mu.Lock()
	defer registry.mu.Unlock()
	removed := 0
	for id, found := range registry.tables {
		found.mu.Lock()
		if found.owner == owner {
			found.alive = false
			found.rows = nil
			delete(registry.tables, id)
			if found.name != "" {
				delete(registry.names, found.name)
			}
			removed++
		}
		found.mu.Unlock()
	}
	return removed
}

func (registry *Registry) table(id TableID) option.Option[*table] {
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	found, present := registry.tables[id]
	return option.Of(found, present)
}

func (table *table) insert(caller term.PID, object term.Term) result.Result[Mutation, Failure] {
	var checked keyedObject
	match table.objectKey(object) {
	case result.Err(failure):
		return result.Err[Mutation, Failure](failure)
	case result.Ok(value):
		checked = value
	}
	table.mu.Lock()
	defer table.mu.Unlock()
	match table.writeFailure(caller) {
	case option.Some(failure):
		return result.Err[Mutation, Failure](failure)
	case option.None:
	}
	cloned := term.Tuple(checked.values...)
	match table.kind {
	case OrderedSet:
		match term.Compare(checked.key, checked.key) {
		case result.Err(cause):
			return result.Err[Mutation, Failure](OrderFailure(cause))
		case result.Ok(_):
		}
		for index, existing := range table.rows {
			existingKey := tupleKey(existing, table.keyPosition)
			match table.keysEqual(existingKey, checked.key) {
			case result.Err(cause):
				return result.Err[Mutation, Failure](cause)
			case result.Ok(equal):
				if equal {
					table.rows[index] = cloned
					return result.Ok[Mutation, Failure](Changed())
				}
			}
		}
	case Set:
		for index, existing := range table.rows {
			existingKey := tupleKey(existing, table.keyPosition)
			match table.keysEqual(existingKey, checked.key) {
			case result.Err(cause):
				return result.Err[Mutation, Failure](cause)
			case result.Ok(equal):
				if equal {
					table.rows[index] = cloned
					return result.Ok[Mutation, Failure](Changed())
				}
			}
		}
	case Bag:
		for _, existing := range table.rows {
			if term.Equal(existing, cloned) {
				return result.Ok[Mutation, Failure](Unchanged())
			}
		}
	case DuplicateBag:
	}
	table.rows = append(table.rows, cloned)
	match table.kind {
	case OrderedSet:
		match table.sortRows() {
		case result.Err(cause):
			return result.Err[Mutation, Failure](cause)
		case result.Ok(_):
		}
	case Set, Bag, DuplicateBag:
	}
	return result.Ok[Mutation, Failure](Changed())
}

func (table *table) lookup(caller term.PID, key term.Term) result.Result[[]term.Term, Failure] {
	table.mu.RLock()
	defer table.mu.RUnlock()
	match table.readFailure(caller) {
	case option.Some(failure):
		return result.Err[[]term.Term, Failure](failure)
	case option.None:
	}
	objects := []term.Term{}
	for _, object := range table.rows {
		match table.keysEqual(tupleKey(object, table.keyPosition), key) {
		case result.Err(cause):
			return result.Err[[]term.Term, Failure](cause)
		case result.Ok(equal):
			if equal {
				objects = append(objects, object.Clone())
			}
		}
	}
	return result.Ok[[]term.Term, Failure](objects)
}

func (table *table) insertNew(caller term.PID, object term.Term) result.Result[bool, Failure] {
	var checked keyedObject
	match table.objectKey(object) {
	case result.Err(failure):
		return result.Err[bool, Failure](failure)
	case result.Ok(value):
		checked = value
	}
	table.mu.Lock()
	defer table.mu.Unlock()
	match table.writeFailure(caller) {
	case option.Some(failure):
		return result.Err[bool, Failure](failure)
	case option.None:
	}
	match table.kind {
	case OrderedSet:
		match term.Compare(checked.key, checked.key) {
		case result.Err(cause):
			return result.Err[bool, Failure](OrderFailure(cause))
		case result.Ok(_):
		}
	case Set, Bag, DuplicateBag:
	}
	for _, existing := range table.rows {
		match table.keysEqual(tupleKey(existing, table.keyPosition), checked.key) {
		case result.Err(cause):
			return result.Err[bool, Failure](cause)
		case result.Ok(equal):
			if equal {
				return result.Ok[bool, Failure](false)
			}
		}
	}
	table.rows = append(table.rows, term.Tuple(checked.values...))
	match table.kind {
	case OrderedSet:
		match table.sortRows() {
		case result.Err(cause):
			return result.Err[bool, Failure](cause)
		case result.Ok(_):
		}
	case Set, Bag, DuplicateBag:
	}
	return result.Ok[bool, Failure](true)
}

func (table *table) deleteKey(caller term.PID, key term.Term) result.Result[Mutation, Failure] {
	table.mu.Lock()
	defer table.mu.Unlock()
	match table.writeFailure(caller) {
	case option.Some(failure):
		return result.Err[Mutation, Failure](failure)
	case option.None:
	}
	kept := table.rows[:0]
	removed := false
	for _, object := range table.rows {
		match table.keysEqual(tupleKey(object, table.keyPosition), key) {
		case result.Err(cause):
			return result.Err[Mutation, Failure](cause)
		case result.Ok(equal):
			if equal {
				removed = true
			} else {
				kept = append(kept, object)
			}
		}
	}
	table.rows = kept
	if removed {
		return result.Ok[Mutation, Failure](Changed())
	}
	return result.Ok[Mutation, Failure](Unchanged())
}

func (table *table) deleteObject(caller term.PID, object term.Term) result.Result[Mutation, Failure] {
	match table.objectKey(object) {
	case result.Err(failure):
		return result.Err[Mutation, Failure](failure)
	case result.Ok(_):
	}
	table.mu.Lock()
	defer table.mu.Unlock()
	match table.writeFailure(caller) {
	case option.Some(failure):
		return result.Err[Mutation, Failure](failure)
	case option.None:
	}
	kept := table.rows[:0]
	removed := false
	for _, existing := range table.rows {
		if term.Equal(existing, object) {
			removed = true
		} else {
			kept = append(kept, existing)
		}
	}
	table.rows = kept
	if removed {
		return result.Ok[Mutation, Failure](Changed())
	}
	return result.Ok[Mutation, Failure](Unchanged())
}

func (table *table) take(caller term.PID, key term.Term) result.Result[[]term.Term, Failure] {
	table.mu.Lock()
	defer table.mu.Unlock()
	match table.writeFailure(caller) {
	case option.Some(failure):
		return result.Err[[]term.Term, Failure](failure)
	case option.None:
	}
	objects := []term.Term{}
	kept := table.rows[:0]
	for _, object := range table.rows {
		match table.keysEqual(tupleKey(object, table.keyPosition), key) {
		case result.Err(cause):
			return result.Err[[]term.Term, Failure](cause)
		case result.Ok(equal):
			if equal {
				objects = append(objects, object.Clone())
			} else {
				kept = append(kept, object)
			}
		}
	}
	table.rows = kept
	return result.Ok[[]term.Term, Failure](objects)
}

func (table *table) updateCounter(
	caller term.PID,
	key term.Term,
	operation CounterOperation,
) result.Result[term.Term, Failure] {
	table.mu.Lock()
	defer table.mu.Unlock()
	match table.writeFailure(caller) {
	case option.Some(failure):
		return result.Err[term.Term, Failure](failure)
	case option.None:
	}
	match table.kind {
	case Bag, DuplicateBag:
		return result.Err[term.Term, Failure](UnsupportedCounterTable(table.kind))
	case Set, OrderedSet:
	}
	rowIndex := -1
	for index, object := range table.rows {
		match table.keysEqual(tupleKey(object, table.keyPosition), key) {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(equal):
			if equal {
				rowIndex = index
			}
		}
		if rowIndex >= 0 {
			break
		}
	}
	if rowIndex < 0 {
		return result.Err[term.Term, Failure](MissingCounterKey(key.Clone()))
	}
	var values []term.Term
	match table.rows[rowIndex] {
	case term.TupleTerm(found):
		values = found
	case _:
		return result.Err[term.Term, Failure](InvalidObject(table.rows[rowIndex].Kind()))
	}
	position := 0
	var incrementTerm term.Term
	var threshold option.Option[term.Term] = option.None[term.Term]
	var setValue option.Option[term.Term] = option.None[term.Term]
	match operation {
	case AddCounter(foundPosition, increment):
		position = foundPosition
		incrementTerm = increment
	case ThresholdCounter(foundPosition, increment, foundThreshold, foundSetValue):
		position = foundPosition
		incrementTerm = increment
		threshold = option.Some[term.Term](foundThreshold)
		setValue = option.Some[term.Term](foundSetValue)
	}
	if position < 1 || position > len(values) {
		return result.Err[term.Term, Failure](InvalidCounterPosition(position, len(values)))
	}
	if position == table.keyPosition {
		return result.Err[term.Term, Failure](CounterKeyPosition(position))
	}
	var current *big.Int
	match counterInteger(values[position - 1], position) {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(value):
		current = value
	}
	var increment *big.Int
	match counterInteger(incrementTerm, position) {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(value):
		increment = value
	}
	next := new(big.Int).Add(current, increment)
	match threshold {
	case option.None:
	case option.Some(thresholdTerm):
		var boundary *big.Int
		match counterInteger(thresholdTerm, position) {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(value):
			boundary = value
		}
		var reset *big.Int
		match setValue {
		case option.None:
			return result.Err[term.Term, Failure](ExpectedCounterInteger(position, term.InvalidValue().Kind()))
		case option.Some(resetTerm):
			match counterInteger(resetTerm, position) {
			case result.Err(failure):
				return result.Err[term.Term, Failure](failure)
			case result.Ok(value):
				reset = value
			}
		}
		if increment.Sign() >= 0 && next.Cmp(boundary) > 0 || increment.Sign() < 0 && next.Cmp(boundary) < 0 {
			next = reset
		}
	}
	updated := term.MustBigInteger(next)
	values[position - 1] = updated
	table.rows[rowIndex] = term.Tuple(values...)
	return result.Ok[term.Term, Failure](updated.Clone())
}

func counterInteger(value term.Term, position int) result.Result[*big.Int, Failure] {
	match term.IntegerValue(value) {
	case option.None:
		return result.Err[*big.Int, Failure](ExpectedCounterInteger(position, value.Kind()))
	case option.Some(integer):
		return result.Ok[*big.Int, Failure](new(big.Int).Set(integer))
	}
}

func (table *table) objects(caller term.PID) result.Result[[]term.Term, Failure] {
	table.mu.RLock()
	defer table.mu.RUnlock()
	match table.readFailure(caller) {
	case option.Some(failure):
		return result.Err[[]term.Term, Failure](failure)
	case option.None:
	}
	objects := make([]term.Term, len(table.rows))
	for index, object := range table.rows {
		objects[index] = object.Clone()
	}
	return result.Ok[[]term.Term, Failure](objects)
}

func (table *table) edge(caller term.PID, first bool) result.Result[Traversal, Failure] {
	table.mu.RLock()
	defer table.mu.RUnlock()
	match table.readFailure(caller) {
	case option.Some(failure):
		return result.Err[Traversal, Failure](failure)
	case option.None:
	}
	match table.distinctKeys() {
	case result.Err(failure):
		return result.Err[Traversal, Failure](failure)
	case result.Ok(keys):
		if len(keys) == 0 {
			return result.Ok[Traversal, Failure](EndOfTable())
		}
		if first {
			return result.Ok[Traversal, Failure](TraversalKey(keys[0].Clone()))
		}
		return result.Ok[Traversal, Failure](TraversalKey(keys[len(keys)-1].Clone()))
	}
}

func (table *table) navigate(
	caller term.PID,
	probe term.Term,
	forward bool,
) result.Result[Traversal, Failure] {
	table.mu.RLock()
	defer table.mu.RUnlock()
	match table.readFailure(caller) {
	case option.Some(failure):
		return result.Err[Traversal, Failure](failure)
	case option.None:
	}
	var keys []term.Term
	match table.distinctKeys() {
	case result.Err(failure):
		return result.Err[Traversal, Failure](failure)
	case result.Ok(found):
		keys = found
	}
	match table.kind {
	case OrderedSet:
		if forward {
			for _, candidate := range keys {
				match term.Compare(candidate, probe) {
				case result.Err(cause):
					return result.Err[Traversal, Failure](OrderFailure(cause))
				case result.Ok(order):
					match order {
					case term.TermGreater:
						return result.Ok[Traversal, Failure](TraversalKey(candidate.Clone()))
					case term.TermLess, term.TermEqual:
					}
				}
			}
			return result.Ok[Traversal, Failure](EndOfTable())
		}
		for index := len(keys) - 1; index >= 0; index-- {
			match term.Compare(keys[index], probe) {
			case result.Err(cause):
				return result.Err[Traversal, Failure](OrderFailure(cause))
			case result.Ok(order):
				match order {
				case term.TermLess:
					return result.Ok[Traversal, Failure](TraversalKey(keys[index].Clone()))
				case term.TermEqual, term.TermGreater:
				}
			}
		}
		return result.Ok[Traversal, Failure](EndOfTable())
	case Set, Bag, DuplicateBag:
		for index, candidate := range keys {
			if !term.Equal(candidate, probe) {
				continue
			}
			next := index + 1
			if !forward {
				next = index - 1
			}
			if next < 0 || next >= len(keys) {
				return result.Ok[Traversal, Failure](EndOfTable())
			}
			return result.Ok[Traversal, Failure](TraversalKey(keys[next].Clone()))
		}
		return result.Err[Traversal, Failure](MissingTraversalKey(probe.Clone()))
	}
}

func (table *table) distinctKeys() result.Result[[]term.Term, Failure] {
	keys := []term.Term{}
	for _, object := range table.rows {
		candidate := tupleKey(object, table.keyPosition)
		duplicate := false
		for _, existing := range keys {
			match table.keysEqual(existing, candidate) {
			case result.Err(failure):
				return result.Err[[]term.Term, Failure](failure)
			case result.Ok(equal):
				if equal {
					duplicate = true
				}
			}
			if duplicate {
				break
			}
		}
		if !duplicate {
			keys = append(keys, candidate.Clone())
		}
	}
	return result.Ok[[]term.Term, Failure](keys)
}

func (table *table) objectKey(object term.Term) result.Result[keyedObject, Failure] {
	match object {
	case term.TupleTerm(values):
		if len(values) < table.keyPosition {
			return result.Err[keyedObject, Failure](MissingKey(table.keyPosition, len(values)))
		}
		return result.Ok[keyedObject, Failure](keyedObject{
			values: values, key: values[table.keyPosition - 1],
		})
	case _:
		return result.Err[keyedObject, Failure](InvalidObject(object.Kind()))
	}
}

func tupleKey(object term.Term, position int) term.Term {
	match object {
	case term.TupleTerm(values):
		return values[position - 1]
	case _:
		return term.InvalidValue()
	}
}

func (table *table) keysEqual(left term.Term, right term.Term) result.Result[bool, Failure] {
	match table.kind {
	case OrderedSet:
		match term.Compare(left, right) {
		case result.Err(cause):
			return result.Err[bool, Failure](OrderFailure(cause))
		case result.Ok(order):
			match order {
			case term.TermEqual:
				return result.Ok[bool, Failure](true)
			case term.TermLess, term.TermGreater:
				return result.Ok[bool, Failure](false)
			}
		}
	case Set, Bag, DuplicateBag:
		return result.Ok[bool, Failure](term.Equal(left, right))
	}
}

func (table *table) sortRows() result.Result[bool, Failure] {
	var sortFailure option.Option[Failure] = option.None[Failure]
	sort.SliceStable(table.rows, func(left, right int) bool {
		match term.Compare(tupleKey(table.rows[left], table.keyPosition), tupleKey(table.rows[right], table.keyPosition)) {
		case result.Err(cause):
			sortFailure = option.Some[Failure](OrderFailure(cause))
			return false
		case result.Ok(order):
			match order {
			case term.TermLess:
				return true
			case term.TermEqual, term.TermGreater:
				return false
			}
		}
	})
	match sortFailure {
	case option.None:
		return result.Ok[bool, Failure](true)
	case option.Some(cause):
		return result.Err[bool, Failure](cause)
	}
}

func (table *table) readFailure(caller term.PID) option.Option[Failure] {
	if !table.alive {
		return option.Some[Failure](MissingTable(table.id))
	}
	match table.access {
	case Private:
		if caller != table.owner {
			return option.Some[Failure](AccessDenied("read", caller))
		}
	case Public, Protected:
	}
	return option.None[Failure]
}

func (table *table) writeFailure(caller term.PID) option.Option[Failure] {
	if !table.alive {
		return option.Some[Failure](MissingTable(table.id))
	}
	match table.access {
	case Public:
		return option.None[Failure]
	case Protected, Private:
		if caller != table.owner {
			return option.Some[Failure](AccessDenied("write", caller))
		}
	}
	return option.None[Failure]
}
