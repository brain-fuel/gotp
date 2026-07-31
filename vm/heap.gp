// Package vm contains the first GoTP runtime primitives.
package vm

import (
	"encoding/binary"

	"goforge.dev/goplus/std/memory"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type Word uint64

const (
	wordBytes                 = 8
	tagMask              Word = 0x7
	tagSmallInteger      Word = 0x1
	tagAtom              Word = 0x2
	tagHeap              Word = 0x3
)

func SmallInteger(value int64) result.Result[Word, Failure] {
	if value < -(1<<60) || value >= 1<<60 {
		return result.Err[Word, Failure](ImmediateOutOfRange(value))
	}
	return result.Ok[Word, Failure](Word(uint64(value)<<3) | tagSmallInteger)
}

func (word Word) SmallInteger() option.Option[int64] {
	if word&tagMask != tagSmallInteger {
		return option.None[int64]
	}
	return option.Some[int64](int64(word) >> 3)
}

type HeapRef struct {
	handle memory.Handle
	words  int
}

type HeapMutation enum {
	HeapMutated()
}

type ProcessHeap struct {
	arena *memory.Arena
}

const offHeapBinaryThreshold = 64

type ProcessMemory struct {
	heap       *ProcessHeap
	roots      memory.Buffer[term.Term]
	offHeap    memory.Buffer[term.Term]
}

func NewProcessMemory(capacity int) result.Result[*ProcessMemory, Failure] {
	match NewProcessHeap(capacity) {
	case result.Err(failure):
		return result.Err[*ProcessMemory, Failure](failure)
	case result.Ok(heap):
		return result.Ok[*ProcessMemory, Failure](&ProcessMemory{
			heap: heap,
			roots: memory.NewBuffer[term.Term](64),
			offHeap: memory.NewBuffer[term.Term](8),
		})
	}
}

func (process *ProcessMemory) Ensure(words int) result.Result[HeapMutation, Failure] {
	if words < 0 {
		return result.Err[HeapMutation, Failure](InvalidConfiguration("negative heap reservation"))
	}
	stats := process.heap.Stats()
	if words > (stats.Capacity-stats.Used)/wordBytes {
		return result.Err[HeapMutation, Failure](MemoryFailure(memory.CapacityExhausted()))
	}
	return result.Ok[HeapMutation, Failure](HeapMutated())
}

func (process *ProcessMemory) Track(value term.Term, words int) result.Result[HeapMutation, Failure] {
	match process.heap.Allocate(words) {
	case result.Err(failure):
		return result.Err[HeapMutation, Failure](failure)
	case result.Ok(_):
		owned := term.Clone(value)
		process.roots.Append(owned)
		process.trackOffHeap(owned)
		return result.Ok[HeapMutation, Failure](HeapMutated())
	}
}

func (process *ProcessMemory) Collect(
	live []term.Term,
	requiredWords int,
) result.Result[HeapMutation, Failure] {
	if requiredWords < 0 {
		return result.Err[HeapMutation, Failure](InvalidConfiguration("negative collection reservation"))
	}
	liveWords := 0
	for _, value := range live {
		words := termHeapWords(value)
		if words > maxInt()-liveWords {
			return result.Err[HeapMutation, Failure](MemoryFailure(memory.CapacityExhausted()))
		}
		liveWords += words
	}
	if requiredWords > maxInt()-liveWords || liveWords+requiredWords > maxInt()/wordBytes {
		return result.Err[HeapMutation, Failure](MemoryFailure(memory.CapacityExhausted()))
	}
	requiredBytes := (liveWords + requiredWords) * wordBytes
	capacity := process.heap.Stats().Capacity
	if capacity < wordBytes { capacity = wordBytes }
	for capacity < requiredBytes {
		if capacity > maxInt()/2 { capacity = requiredBytes; break }
		capacity *= 2
	}
	var replacement *ProcessMemory
	match NewProcessMemory(capacity) {
	case result.Err(failure): return result.Err[HeapMutation, Failure](failure)
	case result.Ok(created): replacement = created
	}
	for _, value := range live {
		words := termHeapWords(value)
		if words == 0 { continue }
		match replacement.Track(value, words) {
		case result.Err(failure):
			replacement.heap.Close()
			return result.Err[HeapMutation, Failure](failure)
		case result.Ok(HeapMutated):
		}
	}
	match process.heap.Close() {
	case result.Err(failure):
		process.installReplacement(replacement)
		return result.Err[HeapMutation, Failure](failure)
	case result.Ok(_):
		process.installReplacement(replacement)
		return result.Ok[HeapMutation, Failure](HeapMutated())
	}
}

func (process *ProcessMemory) installReplacement(replacement *ProcessMemory) {
	process.heap = replacement.heap
	process.roots.Release()
	process.offHeap.Release()
	process.roots = replacement.roots
	process.offHeap = replacement.offHeap
}

func termHeapWords(value term.Term) int {
	match value {
	case term.InvalidTerm, term.AtomTerm(_), term.PIDTerm(_), term.ReferenceTerm(_), term.PortTerm(_): return 0
	case term.IntegerTerm(integer):
		if integer.IsInt64() { raw := integer.Int64(); if raw >= -(1<<60) && raw < 1<<60 { return 0 } }
		return 2 + (integer.BitLen()+63)/64
	case term.FloatTerm(_): return 2
	case term.BinaryTerm(raw):
		if len(raw) > offHeapBinaryThreshold { return 6 }
		return 2 + (len(raw)+wordBytes-1)/wordBytes
	case term.TupleTerm(elements): return 1 + len(elements) + termSliceHeapWords(elements)
	case term.ProperListTerm(elements): return 2*len(elements) + termSliceHeapWords(elements)
	case term.ImproperListTerm(elements, tail): return 2*len(elements) + termSliceHeapWords(elements) + termHeapWords(tail)
	case term.MapTerm(entries):
		words := 3 + 2*len(entries)
		for _, entry := range entries { words += termHeapWords(entry.Key) + termHeapWords(entry.Value) }
		return words
	case term.FunTerm(function): return 5 + len(function.Environment) + termSliceHeapWords(function.Environment)
	}
}

func termSliceHeapWords(values []term.Term) int {
	words := 0
	for _, value := range values { words += termHeapWords(value) }
	return words
}

func (process *ProcessMemory) trackOffHeap(value term.Term) {
	match value {
	case term.BinaryTerm(raw):
		if len(raw) > offHeapBinaryThreshold { process.offHeap.Append(value) }
	case term.TupleTerm(elements):
		for _, element := range elements { process.trackOffHeap(element) }
	case term.ProperListTerm(elements):
		for _, element := range elements { process.trackOffHeap(element) }
	case term.ImproperListTerm(elements, tail):
		for _, element := range elements { process.trackOffHeap(element) }
		process.trackOffHeap(tail)
	case term.MapTerm(entries):
		for _, entry := range entries { process.trackOffHeap(entry.Key); process.trackOffHeap(entry.Value) }
	case term.FunTerm(function):
		for _, captured := range function.Environment { process.trackOffHeap(captured) }
	case term.InvalidTerm, term.IntegerTerm(_), term.FloatTerm(_), term.AtomTerm(_), term.PIDTerm(_), term.ReferenceTerm(_), term.PortTerm(_):
	}
}

func (process *ProcessMemory) Reset() result.Result[HeapMutation, Failure] {
	process.roots.Release()
	process.offHeap.Release()
	return process.heap.Reset()
}

func (process *ProcessMemory) Stats() memory.Stats { return process.heap.Stats() }
func (process *ProcessMemory) RootCount() int { return process.roots.Len() }
func (process *ProcessMemory) OffHeapCount() int { return process.offHeap.Len() }

func NewProcessHeap(capacity int) result.Result[*ProcessHeap, Failure] {
	match memory.New(memory.Config{
		Capacity: capacity,
		Zero:     memory.ZeroOnRelease(),
	}) {
	case result.Ok(arena):
		return result.Ok[*ProcessHeap, Failure](&ProcessHeap{arena: arena})
	case result.Err(cause):
		return result.Err[*ProcessHeap, Failure](MemoryFailure(cause))
	}
}

func (heap *ProcessHeap) Allocate(words int) result.Result[HeapRef, Failure] {
	if words <= 0 {
		return result.Err[HeapRef, Failure](InvalidConfiguration("heap allocation must contain words"))
	}
	match heap.arena.Allocate(words*wordBytes, wordBytes) {
	case result.Ok(handle):
		return result.Ok[HeapRef, Failure](HeapRef{handle: handle, words: words})
	case result.Err(cause):
		return result.Err[HeapRef, Failure](MemoryFailure(cause))
	}
}

func (heap *ProcessHeap) Store(
	reference HeapRef,
	index int,
	word Word,
) result.Result[HeapMutation, Failure] {
	if index < 0 || index >= reference.words {
		return result.Err[HeapMutation, Failure](HeapIndexOutOfRange(index, reference.words))
	}
	var raw [wordBytes]byte
	binary.NativeEndian.PutUint64(raw[:], uint64(word))
	return adaptMutation(heap.arena.Write(reference.handle, index*wordBytes, raw[:]))
}

func (heap *ProcessHeap) Load(reference HeapRef, index int) result.Result[Word, Failure] {
	if index < 0 || index >= reference.words {
		return result.Err[Word, Failure](HeapIndexOutOfRange(index, reference.words))
	}
	var raw [wordBytes]byte
	match heap.arena.Read(reference.handle, index*wordBytes, raw[:]) {
	case result.Err(cause):
		return result.Err[Word, Failure](MemoryFailure(cause))
	case result.Ok(_):
		return result.Ok[Word, Failure](Word(binary.NativeEndian.Uint64(raw[:])))
	}
}

func (heap *ProcessHeap) Release(
	reference HeapRef,
) result.Result[HeapMutation, Failure] {
	return adaptMutation(heap.arena.Delete(reference.handle))
}

func (heap *ProcessHeap) Reset() result.Result[HeapMutation, Failure] {
	return adaptMutation(heap.arena.Reset())
}

func (heap *ProcessHeap) Stats() memory.Stats {
	return heap.arena.Stats()
}

func (heap *ProcessHeap) Close() result.Result[HeapMutation, Failure] {
	return adaptMutation(heap.arena.Close())
}

func adaptMutation(
	outcome result.Result[memory.Mutation, memory.Failure],
) result.Result[HeapMutation, Failure] {
	match outcome {
	case result.Ok(_):
		return result.Ok[HeapMutation, Failure](HeapMutated())
	case result.Err(cause):
		return result.Err[HeapMutation, Failure](MemoryFailure(cause))
	}
}
