package ets

import (
	"sync"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func etsPID(number uint64) term.PID {
	return term.PID{Node: 1, Number: number, Creation: 1}
}

func mustTable(t *testing.T, registry *Registry, owner term.PID, kind TableKind) TableID {
	match registry.New(owner, Config{Kind: kind, Access: Public(), KeyPosition: 1}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(id):
		return id
	}
	panic("unreachable")
}

func mustInsert(t *testing.T, registry *Registry, caller term.PID, id TableID, object term.Term) {
	match registry.Insert(caller, id, object) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
}

func mustLookup(t *testing.T, registry *Registry, caller term.PID, id TableID, key term.Term) []term.Term {
	match registry.Lookup(caller, id, key) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(objects):
		return objects
	}
	panic("unreachable")
}

// assayxport:law gotp.otp.ets-core-laws
func TestSetLastInsertWinsProperty(t *testing.T) {
	property := func(values []int16) bool {
		registry := NewRegistry()
		owner := etsPID(1)
		id := mustTable(t, registry, owner, Set())
		for _, value := range values {
			mustInsert(t, registry, owner, id, term.Tuple(term.MustAtom("key"), term.Integer(int64(value))))
		}
		objects := mustLookup(t, registry, owner, id, term.MustAtom("key"))
		if len(values) == 0 {
			return len(objects) == 0
		}
		return len(objects) == 1 && term.Equal(objects[0], term.Tuple(
			term.MustAtom("key"), term.Integer(int64(values[len(values)-1])),
		))
	}
	if failure := quick.Check(property, nil); failure != nil {
		t.Fatal(failure)
	}
}

func TestBagAndDuplicateBagMultiplicity(t *testing.T) {
	owner := etsPID(1)
	object := term.Tuple(term.Integer(1), term.MustAtom("value"))
	for _, test := range []struct { kind TableKind; want int }{
		{kind: Bag(), want: 1}, {kind: DuplicateBag(), want: 2},
	} {
		registry := NewRegistry()
		id := mustTable(t, registry, owner, test.kind)
		mustInsert(t, registry, owner, id, object)
		mustInsert(t, registry, owner, id, object)
		if got := len(mustLookup(t, registry, owner, id, term.Integer(1))); got != test.want {
			t.Fatalf("multiplicity = %d, want %d", got, test.want)
		}
	}
}

func TestOrderedSetUsesTermOrderAndNumericKeyEquivalence(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	id := mustTable(t, registry, owner, OrderedSet())
	mustInsert(t, registry, owner, id, term.Tuple(term.Integer(3), term.MustAtom("three")))
	mustInsert(t, registry, owner, id, term.Tuple(term.Integer(1), term.MustAtom("one")))
	mustInsert(t, registry, owner, id, term.Tuple(term.Integer(2), term.MustAtom("two")))
	match registry.Objects(owner, id) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(objects):
		for index, object := range objects {
			if !term.Equal(tupleKey(object, 1), term.Integer(int64(index+1))) {
				t.Fatalf("ordered objects = %v", objects)
			}
		}
	}
}

func TestProtectedAccessAndOwnerExit(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	other := etsPID(2)
	var id TableID
	match registry.New(owner, Config{Name: "cache", Named: true, Kind: Set(), Access: Protected()}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(created):
		id = created
	}
	mustInsert(t, registry, owner, id, term.Tuple(term.MustAtom("key"), term.Integer(1)))
	if len(mustLookup(t, registry, other, id, term.MustAtom("key"))) != 1 {
		t.Fatal("protected read failed")
	}
	match registry.Insert(other, id, term.Tuple(term.MustAtom("key"), term.Integer(2))) {
	case result.Ok(_):
		t.Fatal("protected non-owner wrote table")
	case result.Err(_):
	}
	if removed := registry.OwnerExit(owner); removed != 1 {
		t.Fatalf("owner cleanup removed %d tables", removed)
	}
	match registry.Whereis("cache") {
	case option.Some(_):
		t.Fatal("owner exit left named table registered")
	case option.None:
	}
	match registry.Lookup(other, id, term.MustAtom("key")) {
	case result.Ok(_):
		t.Fatal("owner exit left table alive")
	case result.Err(_):
	}
}

func TestZeroConfigUsesSetProtectedDefaults(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	other := etsPID(2)
	var id TableID
	match registry.New(owner, Config{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(created):
		id = created
	}
	mustInsert(t, registry, owner, id, term.Tuple(term.MustAtom("key"), term.Integer(1)))
	mustInsert(t, registry, owner, id, term.Tuple(term.MustAtom("key"), term.Integer(2)))
	if len(mustLookup(t, registry, other, id, term.MustAtom("key"))) != 1 {
		t.Fatal("default set did not replace or allow protected read")
	}
	match registry.Insert(other, id, term.Tuple(term.MustAtom("other"), term.Integer(3))) {
	case result.Ok(_):
		t.Fatal("default protected table allowed non-owner write")
	case result.Err(_):
	}
}

func TestInsertNewIsAtomicAcrossConcurrentWriters(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	id := mustTable(t, registry, owner, Set())
	const writers = 64
	won := make(chan bool, writers)
	var group sync.WaitGroup
	for index := 0; index < writers; index++ {
		group.Add(1)
		go func(value int) {
			defer group.Done()
			match registry.InsertNew(owner, id, term.Tuple(term.MustAtom("lock"), term.Integer(int64(value)))) {
			case result.Err(failure):
				t.Errorf("insert_new: %v", failure)
			case result.Ok(inserted):
				won <- inserted
			}
		}(index)
	}
	group.Wait()
	close(won)
	winners := 0
	for inserted := range won {
		if inserted {
			winners++
		}
	}
	if winners != 1 || len(mustLookup(t, registry, owner, id, term.MustAtom("lock"))) != 1 {
		t.Fatalf("insert_new winners = %d", winners)
	}
}

func TestTakeReturnsAndDeletesWholeKeyAtomically(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	id := mustTable(t, registry, owner, Bag())
	mustInsert(t, registry, owner, id, term.Tuple(term.MustAtom("key"), term.Integer(1)))
	mustInsert(t, registry, owner, id, term.Tuple(term.MustAtom("key"), term.Integer(2)))
	match registry.Take(owner, id, term.MustAtom("key")) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(objects):
		if len(objects) != 2 {
			t.Fatalf("take returned %d objects", len(objects))
		}
	}
	if objects := mustLookup(t, registry, owner, id, term.MustAtom("key")); len(objects) != 0 {
		t.Fatalf("take left %d objects", len(objects))
	}
}

func TestDeleteObjectRemovesExactDuplicatesOnly(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	id := mustTable(t, registry, owner, DuplicateBag())
	target := term.Tuple(term.MustAtom("key"), term.Integer(1))
	other := term.Tuple(term.MustAtom("key"), term.Integer(2))
	mustInsert(t, registry, owner, id, target)
	mustInsert(t, registry, owner, id, target)
	mustInsert(t, registry, owner, id, other)
	match registry.DeleteObject(owner, id, target) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	objects := mustLookup(t, registry, owner, id, term.MustAtom("key"))
	if len(objects) != 1 || !term.Equal(objects[0], other) {
		t.Fatalf("remaining objects = %v", objects)
	}
}

func assertTraversalKey(t *testing.T, traversal Traversal, want term.Term) {
	match traversal {
	case EndOfTable:
		t.Fatalf("traversal ended, want %v", want)
	case TraversalKey(value):
		if !term.Equal(value, want) {
			t.Fatalf("traversal key = %v, want %v", value, want)
		}
	}
}

func TestOrderedSetNavigationUsesAbsentProbeTermOrder(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	id := mustTable(t, registry, owner, OrderedSet())
	for _, key := range []int64{3, 1, 5} {
		mustInsert(t, registry, owner, id, term.Tuple(term.Integer(key), term.MustAtom("value")))
	}
	match registry.First(owner, id) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(value): assertTraversalKey(t, value, term.Integer(1))
	}
	match registry.Last(owner, id) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(value): assertTraversalKey(t, value, term.Integer(5))
	}
	match registry.Next(owner, id, term.Integer(2)) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(value): assertTraversalKey(t, value, term.Integer(3))
	}
	match registry.Prev(owner, id, term.Integer(4)) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(value): assertTraversalKey(t, value, term.Integer(3))
	}
	match registry.Next(owner, id, term.Integer(5)) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(value):
		match value {
		case EndOfTable:
		case TraversalKey(found): t.Fatalf("next after last = %v", found)
		}
	}
}

func TestUnorderedNavigationRejectsAbsentProbe(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	id := mustTable(t, registry, owner, Set())
	mustInsert(t, registry, owner, id, term.Tuple(term.MustAtom("present"), term.Integer(1)))
	match registry.Next(owner, id, term.MustAtom("absent")) {
	case result.Ok(_):
		t.Fatal("unordered traversal accepted absent key")
	case result.Err(failure):
		var checked Failure = failure
		match checked {
		case MissingTraversalKey(_):
		case InvalidName(_), DuplicateName(_), InvalidKeyPosition(_), InvalidObject(_), MissingKey(_, _), MissingTable(_), MissingCounterKey(_), InvalidCounterPosition(_, _), CounterKeyPosition(_), ExpectedCounterInteger(_, _), UnsupportedCounterTable(_), AccessDenied(_, _), NotOwner(_), OrderFailure(_):
			t.Fatalf("unexpected traversal failure = %v", failure)
		}
	}
}

func TestConcurrentCountersLoseNoUpdates(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	id := mustTable(t, registry, owner, Set())
	mustInsert(t, registry, owner, id, term.Tuple(term.MustAtom("count"), term.Integer(0)))
	const writers = 64
	var group sync.WaitGroup
	for index := 0; index < writers; index++ {
		group.Add(1)
		go func() {
			defer group.Done()
			match registry.UpdateCounter(owner, id, term.MustAtom("count"), AddCounter(2, term.Integer(1))) {
			case result.Err(failure):
				t.Errorf("update_counter: %v", failure)
			case result.Ok(_):
			}
		}()
	}
	group.Wait()
	objects := mustLookup(t, registry, owner, id, term.MustAtom("count"))
	want := term.Tuple(term.MustAtom("count"), term.Integer(writers))
	if len(objects) != 1 || !term.Equal(objects[0], want) {
		t.Fatalf("counter object = %v", objects)
	}
}

func TestCounterThresholdResetsInIncrementDirection(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	id := mustTable(t, registry, owner, OrderedSet())
	mustInsert(t, registry, owner, id, term.Tuple(term.MustAtom("count"), term.Integer(9)))
	operation := ThresholdCounter(2, term.Integer(2), term.Integer(10), term.Integer(0))
	match registry.UpdateCounter(owner, id, term.MustAtom("count"), operation) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(value):
		if !term.Equal(value, term.Integer(0)) {
			t.Fatalf("threshold result = %v", value)
		}
	}
	objects := mustLookup(t, registry, owner, id, term.MustAtom("count"))
	if len(objects) != 1 || !term.Equal(objects[0], term.Tuple(term.MustAtom("count"), term.Integer(0))) {
		t.Fatalf("threshold object = %v", objects)
	}
}

func TestCounterRejectsBagAndKeyFieldWithoutMutation(t *testing.T) {
	registry := NewRegistry()
	owner := etsPID(1)
	bag := mustTable(t, registry, owner, Bag())
	object := term.Tuple(term.Integer(1), term.Integer(2))
	mustInsert(t, registry, owner, bag, object)
	match registry.UpdateCounter(owner, bag, term.Integer(1), AddCounter(2, term.Integer(1))) {
	case result.Ok(_): t.Fatal("bag counter succeeded")
	case result.Err(_):
	}
	set := mustTable(t, registry, owner, Set())
	mustInsert(t, registry, owner, set, object)
	match registry.UpdateCounter(owner, set, term.Integer(1), AddCounter(1, term.Integer(1))) {
	case result.Ok(_): t.Fatal("key counter succeeded")
	case result.Err(_):
	}
	if objects := mustLookup(t, registry, owner, set, term.Integer(1)); len(objects) != 1 || !term.Equal(objects[0], object) {
		t.Fatalf("failed counter mutated object = %v", objects)
	}
}
