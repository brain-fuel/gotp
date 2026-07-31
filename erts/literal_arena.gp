package erts

import (
	"fmt"

	"goforge.dev/goplus/std/memory"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

type LiteralArenaFailure enum {
	LiteralMemoryFailure(Cause memory.Failure)
	DuplicateLiteral(Index uint64)
	MissingLiteral(Index uint64)
}

func (failure LiteralArenaFailure) Error() string {
	match failure {
	case LiteralMemoryFailure(cause): return "gotp/erts: literal arena: " + cause.Error()
	case DuplicateLiteral(index): return fmt.Sprintf("gotp/erts: duplicate arena literal %d", index)
	case MissingLiteral(index): return fmt.Sprintf("gotp/erts: missing arena literal %d", index)
	}
}

type LiteralArena struct {
	arena *memory.Arena
	group *memory.Group
	entries memory.SoA2[uint64, memory.Handle]
	closed bool
}

// assayxport:unit gotp.erts.literal-arena
func NewLiteralArena(capacity int) result.Result[*LiteralArena, LiteralArenaFailure] {
	match memory.New(memory.Config{Capacity: capacity, Zero: memory.ZeroOnRelease()}) {
	case result.Err(failure): return result.Err[*LiteralArena, LiteralArenaFailure](LiteralMemoryFailure(failure))
	case result.Ok(arena):
		match arena.Group() { case result.Err(failure): arena.Close(); return result.Err[*LiteralArena, LiteralArenaFailure](LiteralMemoryFailure(failure)); case result.Ok(group): return result.Ok[*LiteralArena, LiteralArenaFailure](&LiteralArena{arena: arena, group: group, entries: memory.NewSoA2[uint64, memory.Handle](16)}) }
	}
}

func (literals *LiteralArena) Store(index uint64, encoded []byte) result.Result[memory.Handle, LiteralArenaFailure] {
	if _, present := literals.lookup(index); present { return result.Err[memory.Handle, LiteralArenaFailure](DuplicateLiteral(index)) }
	match literals.group.Allocate(len(encoded), 8) {
	case result.Err(failure): return result.Err[memory.Handle, LiteralArenaFailure](LiteralMemoryFailure(failure))
	case result.Ok(handle): match literals.arena.Write(handle, 0, encoded) { case result.Err(failure): return result.Err[memory.Handle, LiteralArenaFailure](LiteralMemoryFailure(failure)); case result.Ok(_): literals.entries.Append(index, handle); return result.Ok[memory.Handle, LiteralArenaFailure](handle) }
	}
}

func (literals *LiteralArena) Bytes(index uint64) result.Result[[]byte, LiteralArenaFailure] {
	handle, present := literals.lookup(index); if !present { return result.Err[[]byte, LiteralArenaFailure](MissingLiteral(index)) }; match literals.arena.Bytes(handle) { case result.Err(failure): return result.Err[[]byte, LiteralArenaFailure](LiteralMemoryFailure(failure)); case result.Ok(encoded): return result.Ok[[]byte, LiteralArenaFailure](encoded) }
}

func (literals *LiteralArena) Reset() result.Result[memory.Mutation, LiteralArenaFailure] { match literals.group.Reset() { case result.Err(failure): return result.Err[memory.Mutation, LiteralArenaFailure](LiteralMemoryFailure(failure)); case result.Ok(applied): literals.entries.Reset(); return result.Ok[memory.Mutation, LiteralArenaFailure](applied) } }

func (literals *LiteralArena) Close() result.Result[memory.Mutation, LiteralArenaFailure] {
	if literals.closed { return result.Ok[memory.Mutation, LiteralArenaFailure](memory.Applied()) }
	match literals.group.Release() { case result.Err(failure): return result.Err[memory.Mutation, LiteralArenaFailure](LiteralMemoryFailure(failure)); case result.Ok(_): match literals.arena.Close() { case result.Err(failure): return result.Err[memory.Mutation, LiteralArenaFailure](LiteralMemoryFailure(failure)); case result.Ok(applied): literals.entries.Release(); literals.closed = true; return result.Ok[memory.Mutation, LiteralArenaFailure](applied) } }
}

func (literals *LiteralArena) Len() int { return literals.entries.Len() }
func (literals *LiteralArena) Stats() memory.Stats { return literals.arena.Stats() }
func (literals *LiteralArena) lookup(index uint64) (memory.Handle, bool) { for position := 0; position < literals.entries.Len(); position++ { match literals.entries.At(position) { case option.Some(row): if row.First == index { return row.Second, true }; case option.None: } }; return memory.Handle{}, false }
