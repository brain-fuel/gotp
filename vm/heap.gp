// Package vm contains the first GoTP runtime primitives.
package vm

import (
	"encoding/binary"

	"goforge.dev/goplus/std/memory"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
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
