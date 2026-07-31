// Package term defines GoTP's immutable Erlang term core. Alternatives are a
// sealed Go+ enum; projections return Option and validated construction returns
// Result, so ordinary term handling is exhaustive and does not use sentinel
// fields or comma-ok control flow.
package term

import (
	"bytes"
	"fmt"
	"math"
	"math/big"
	"unicode/utf8"

	"goforge.dev/goplus/std/nonempty"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

type Kind enum {
	InvalidKind()
	IntegerKind()
	FloatKind()
	AtomKind()
	BinaryKind()
	TupleKind()
	ListKind()
	MapKind()
	PIDKind()
	ReferenceKind()
	FunKind()
	PortKind()
}

type PID struct {
	Node     uint32
	Number   uint64
	Serial   uint32
	Creation uint32
}

func (pid PID) Valid() bool {
	return pid.Number != 0
}

func (pid PID) Less(other PID) bool {
	if pid.Node != other.Node {
		return pid.Node < other.Node
	}
	if pid.Number != other.Number {
		return pid.Number < other.Number
	}
	if pid.Serial != other.Serial {
		return pid.Serial < other.Serial
	}
	return pid.Creation < other.Creation
}

type Reference struct {
	Node     uint32
	Creation uint32
	Words    [5]uint32
	Length   uint8
}

func (reference Reference) Valid() bool {
	return reference.Length > 0 && reference.Length <= uint8(len(reference.Words))
}

func (reference Reference) Less(other Reference) bool {
	if reference.Node != other.Node {
		return reference.Node < other.Node
	}
	if reference.Creation != other.Creation {
		return reference.Creation < other.Creation
	}
	if reference.Length != other.Length {
		return reference.Length < other.Length
	}
	for index := 0; index < int(reference.Length); index++ {
		if reference.Words[index] != other.Words[index] {
			return reference.Words[index] < other.Words[index]
		}
	}
	return false
}

type Port struct {
	Node     uint32
	ID       uint64
	Creation uint32
}

type MapEntry struct {
	Key   Term
	Value Term
}

type FunForm enum {
	LocalClosure()
	OldClosure()
	NewClosure(Digest [16]byte, NewIndex uint32, OldIndex uint32)
	ExportedFunction()
}

type Fun struct {
	Form        FunForm
	Module      string
	Function    string
	Arity       uint32
	Label       uint64
	Index       uint32
	Unique      uint32
	Creator     PID
	Environment []Term
}

//goplus:derive off
type Term enum {
	InvalidTerm()
	IntegerTerm(Value *big.Int)
	FloatTerm(Bits uint64)
	AtomTerm(Name string)
	BinaryTerm(Bytes []byte)
	TupleTerm(Elements []Term)
	ProperListTerm(Elements []Term)
	ImproperListTerm(Elements []Term, Tail Term)
	MapTerm(Entries []MapEntry)
	PIDTerm(Value PID)
	ReferenceTerm(Value Reference)
	FunTerm(Value Fun)
	PortTerm(Value Port)
}

type ValidationFailure enum {
	InvalidAtomUTF8()
	AtomTooLong(CodePoints int)
	NilBigInteger()
	DuplicateMapKey(First int, Second int)
	InvalidReferenceLength(Length int)
}

func (failure ValidationFailure) Error() string {
	match failure {
	case InvalidAtomUTF8():
		return "gotp/term: atom is not valid UTF-8"
	case AtomTooLong(codePoints):
		return fmt.Sprintf("gotp/term: atom has %d code points; limit is 255", codePoints)
	case NilBigInteger():
		return "gotp/term: big integer pointer is nil"
	case DuplicateMapKey(first, second):
		return fmt.Sprintf("gotp/term: duplicate exact map key at indexes %d and %d", first, second)
	case InvalidReferenceLength(length):
		return fmt.Sprintf("gotp/term: reference has %d words; range is 1..5", length)
	}
}

func InvalidValue() Term {
	return InvalidTerm()
}

func Integer(value int64) Term {
	return IntegerTerm(big.NewInt(value))
}

func BigInteger(value *big.Int) result.Result[Term, ValidationFailure] {
	if value == nil {
		return result.Err[Term, ValidationFailure](NilBigInteger())
	}
	return result.Ok[Term, ValidationFailure](IntegerTerm(new(big.Int).Set(value)))
}

func MustBigInteger(value *big.Int) Term {
	match BigInteger(value) {
	case result.Ok(integer):
		return integer
	case result.Err(failure):
		panic(failure)
	}
}

func Float(value float64) Term {
	return FloatTerm(math.Float64bits(value))
}

func Atom(name string) result.Result[Term, ValidationFailure] {
	if !utf8.ValidString(name) {
		return result.Err[Term, ValidationFailure](InvalidAtomUTF8())
	}
	codePoints := utf8.RuneCountInString(name)
	if codePoints > 255 {
		return result.Err[Term, ValidationFailure](AtomTooLong(codePoints))
	}
	return result.Ok[Term, ValidationFailure](AtomTerm(name))
}

func MustAtom(name string) Term {
	match Atom(name) {
	case result.Ok(atom):
		return atom
	case result.Err(failure):
		panic(failure)
	}
}

func Binary(value []byte) Term {
	return BinaryTerm(bytes.Clone(value))
}

func Tuple(values ...Term) Term {
	return TupleTerm(cloneTerms(values))
}

func List(values ...Term) Term {
	return ProperListTerm(cloneTerms(values))
}

func ImproperList(values []Term, tail Term) Term {
	return ImproperListTerm(cloneTerms(values), tail.Clone())
}

func Map(entries []MapEntry) result.Result[Term, ValidationFailure] {
	copied := make([]MapEntry, len(entries))
	for index, entry := range entries {
		for prior := 0; prior < index; prior++ {
			if entries[prior].Key.Equal(entry.Key) {
				return result.Err[Term, ValidationFailure](DuplicateMapKey(prior, index))
			}
		}
		copied[index] = MapEntry{Key: entry.Key.Clone(), Value: entry.Value.Clone()}
	}
	return result.Ok[Term, ValidationFailure](MapTerm(copied))
}

func ReferenceOf(
	node uint32,
	creation uint32,
	words nonempty.NonEmpty[uint32],
) result.Result[Reference, ValidationFailure] {
	values := nonempty.Slice(words)
	if len(values) > 5 {
		return result.Err[Reference, ValidationFailure](InvalidReferenceLength(len(values)))
	}
	reference := Reference{
		Node:     node,
		Creation: creation,
		Length:   uint8(len(values)),
	}
	copy(reference.Words[:], values)
	return result.Ok[Reference, ValidationFailure](reference)
}

func PIDValue(pid PID) Term {
	return PIDTerm(pid)
}

func ReferenceValue(reference Reference) Term {
	return ReferenceTerm(reference)
}

// assayxport:unit gotp.term.fun
func Function(value Fun) Term {
	if value.Form == nil {
		value.Form = LocalClosure()
	}
	value.Environment = cloneTerms(value.Environment)
	return FunTerm(value)
}

func PortValue(port Port) Term {
	return PortTerm(port)
}

func (value Term) Kind() Kind {
	if value == nil {
		return InvalidKind()
	}
	match value {
	case InvalidTerm():
		return InvalidKind()
	case IntegerTerm(_):
		return IntegerKind()
	case FloatTerm(_):
		return FloatKind()
	case AtomTerm(_):
		return AtomKind()
	case BinaryTerm(_):
		return BinaryKind()
	case TupleTerm(_):
		return TupleKind()
	case ProperListTerm(_):
		return ListKind()
	case ImproperListTerm(_, _):
		return ListKind()
	case MapTerm(_):
		return MapKind()
	case PIDTerm(_):
		return PIDKind()
	case ReferenceTerm(_):
		return ReferenceKind()
	case FunTerm(_):
		return FunKind()
	case PortTerm(_):
		return PortKind()
	}
}

func (value Term) IntegerValue() option.Option[*big.Int] {
	if value == nil {
		return option.None[*big.Int]
	}
	match value {
	case IntegerTerm(integer):
		return option.Some(new(big.Int).Set(integer))
	case _:
		return option.None[*big.Int]
	}
}

func (value Term) Int64() option.Option[int64] {
	match value.IntegerValue() {
	case option.Some(integer):
		if integer.IsInt64() {
			return option.Some(integer.Int64())
		}
		return option.None[int64]
	case option.None:
		return option.None[int64]
	}
}

func (value Term) FloatValue() option.Option[float64] {
	if value == nil {
		return option.None[float64]
	}
	match value {
	case FloatTerm(bits):
		return option.Some(math.Float64frombits(bits))
	case _:
		return option.None[float64]
	}
}

func (value Term) AtomName() option.Option[string] {
	if value == nil {
		return option.None[string]
	}
	match value {
	case AtomTerm(name):
		return option.Some(name)
	case _:
		return option.None[string]
	}
}

func (value Term) BinaryValue() option.Option[[]byte] {
	if value == nil {
		return option.None[[]byte]
	}
	match value {
	case BinaryTerm(raw):
		return option.Some(bytes.Clone(raw))
	case _:
		return option.None[[]byte]
	}
}

func (value Term) Elements() option.Option[[]Term] {
	if value == nil {
		return option.None[[]Term]
	}
	match value {
	case TupleTerm(elements):
		return option.Some(cloneTerms(elements))
	case ProperListTerm(elements):
		return option.Some(cloneTerms(elements))
	case ImproperListTerm(elements, _):
		return option.Some(cloneTerms(elements))
	case _:
		return option.None[[]Term]
	}
}

func (value Term) ImproperTail() option.Option[Term] {
	if value == nil {
		return option.None[Term]
	}
	match value {
	case ImproperListTerm(_, tail):
		return option.Some(tail.Clone())
	case _:
		return option.None[Term]
	}
}

func (value Term) MapEntries() option.Option[[]MapEntry] {
	if value == nil {
		return option.None[[]MapEntry]
	}
	match value {
	case MapTerm(entries):
		copied := make([]MapEntry, len(entries))
		for index, entry := range entries {
			copied[index] = MapEntry{Key: entry.Key.Clone(), Value: entry.Value.Clone()}
		}
		return option.Some(copied)
	case _:
		return option.None[[]MapEntry]
	}
}

func (value Term) PIDValue() option.Option[PID] {
	if value == nil {
		return option.None[PID]
	}
	match value {
	case PIDTerm(pid):
		return option.Some(pid)
	case _:
		return option.None[PID]
	}
}

func (value Term) ReferenceValue() option.Option[Reference] {
	if value == nil {
		return option.None[Reference]
	}
	match value {
	case ReferenceTerm(reference):
		return option.Some(reference)
	case _:
		return option.None[Reference]
	}
}

func (value Term) PortValue() option.Option[Port] {
	if value == nil {
		return option.None[Port]
	}
	match value {
	case PortTerm(port):
		return option.Some(port)
	case _:
		return option.None[Port]
	}
}

func (value Term) FunValue() option.Option[Fun] {
	if value == nil {
		return option.None[Fun]
	}
	match value {
	case FunTerm(function):
		function.Environment = cloneTerms(function.Environment)
		return option.Some(function)
	case _:
		return option.None[Fun]
	}
}

func (value Term) Clone() Term {
	if value == nil {
		return InvalidTerm()
	}
	match value {
	case InvalidTerm():
		return InvalidTerm()
	case IntegerTerm(integer):
		return IntegerTerm(new(big.Int).Set(integer))
	case FloatTerm(bits):
		return FloatTerm(bits)
	case AtomTerm(name):
		return AtomTerm(name)
	case BinaryTerm(raw):
		return BinaryTerm(bytes.Clone(raw))
	case TupleTerm(elements):
		return TupleTerm(cloneTerms(elements))
	case ProperListTerm(elements):
		return ProperListTerm(cloneTerms(elements))
	case ImproperListTerm(elements, tail):
		return ImproperListTerm(cloneTerms(elements), tail.Clone())
	case MapTerm(entries):
		copied := make([]MapEntry, len(entries))
		for index, entry := range entries {
			copied[index] = MapEntry{Key: entry.Key.Clone(), Value: entry.Value.Clone()}
		}
		return MapTerm(copied)
	case PIDTerm(pid):
		return PIDTerm(pid)
	case ReferenceTerm(reference):
		return ReferenceTerm(reference)
	case FunTerm(function):
		return Function(function)
	case PortTerm(port):
		return PortTerm(port)
	}
}

func (value Term) Equal(other Term) bool {
	if value == nil || other == nil {
		return value == nil && other == nil
	}
	match value {
	case InvalidTerm():
		match other {
		case InvalidTerm():
			return true
		case _:
			return false
		}
	case IntegerTerm(left):
		match other {
		case IntegerTerm(right):
			return left.Cmp(right) == 0
		case _:
			return false
		}
	case FloatTerm(left):
		match other {
		case FloatTerm(right):
			return left == right
		case _:
			return false
		}
	case AtomTerm(left):
		match other {
		case AtomTerm(right):
			return left == right
		case _:
			return false
		}
	case BinaryTerm(left):
		match other {
		case BinaryTerm(right):
			return bytes.Equal(left, right)
		case _:
			return false
		}
	case TupleTerm(left):
		match other {
		case TupleTerm(right):
			return equalTerms(left, right)
		case _:
			return false
		}
	case ProperListTerm(left):
		match other {
		case ProperListTerm(right):
			return equalTerms(left, right)
		case _:
			return false
		}
	case ImproperListTerm(left, leftTail):
		match other {
		case ImproperListTerm(right, rightTail):
			return equalTerms(left, right) && leftTail.Equal(rightTail)
		case _:
			return false
		}
	case MapTerm(left):
		match other {
		case MapTerm(right):
			return equalMaps(left, right)
		case _:
			return false
		}
	case PIDTerm(left):
		match other {
		case PIDTerm(right):
			return left == right
		case _:
			return false
		}
	case ReferenceTerm(left):
		match other {
		case ReferenceTerm(right):
			return left == right
		case _:
			return false
		}
	case FunTerm(left):
		match other {
		case FunTerm(right):
			return FunFormEqual(left.Form, right.Form) &&
				left.Module == right.Module &&
				left.Function == right.Function &&
				left.Arity == right.Arity &&
				left.Label == right.Label &&
				left.Index == right.Index &&
				left.Unique == right.Unique &&
				left.Creator == right.Creator &&
				equalTerms(left.Environment, right.Environment)
		case _:
			return false
		}
	case PortTerm(left):
		match other {
		case PortTerm(right):
			return left == right
		case _:
			return false
		}
	}
}

func cloneTerms(values []Term) []Term {
	if values == nil {
		return nil
	}
	cloned := make([]Term, len(values))
	for index, value := range values {
		cloned[index] = value.Clone()
	}
	return cloned
}

func equalTerms(left []Term, right []Term) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if !left[index].Equal(right[index]) {
			return false
		}
	}
	return true
}

func equalMaps(left []MapEntry, right []MapEntry) bool {
	if len(left) != len(right) {
		return false
	}
	matched := make([]bool, len(right))
	for _, leftEntry := range left {
		found := false
		for index, rightEntry := range right {
			if !matched[index] &&
				leftEntry.Key.Equal(rightEntry.Key) &&
				leftEntry.Value.Equal(rightEntry.Value) {
				matched[index] = true
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}
