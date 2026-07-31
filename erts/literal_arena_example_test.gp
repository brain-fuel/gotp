package erts

import (
	"bytes"
	"testing"

	"goforge.dev/goplus/std/memory"
	"goforge.dev/goplus/std/result"
)

// assayxport:law gotp.erts.literal-arena-laws
func TestLiteralArenaResetInvalidatesGenerationAndReusesCapacity(t *testing.T) {
	literals := requireLiteralArena(t); defer literals.Close(); var old memory.Handle
	match literals.Store(7, []byte("literal")) { case result.Err(failure): t.Fatal(failure); case result.Ok(handle): old = handle }
	match literals.Bytes(7) { case result.Err(failure): t.Fatal(failure); case result.Ok(encoded): if !bytes.Equal(encoded, []byte("literal")) { t.Fatalf("literal = %q", encoded) } }
	match literals.Reset() { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
	if literals.Len() != 0 || literals.Stats().Used != 0 { t.Fatalf("reset = %d/%d", literals.Len(), literals.Stats().Used) }
	match literals.Store(8, []byte("next")) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
	match literals.arena.Bytes(old) { case result.Ok(_): t.Fatal("old literal handle survived reset"); case result.Err(failure): match failure { case memory.InvalidHandle: case _: t.Fatal(failure) } }
}

func TestLiteralArenaRejectsDuplicateIdentity(t *testing.T) { literals := requireLiteralArena(t); defer literals.Close(); match literals.Store(1, []byte("first")) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }; match literals.Store(1, []byte("second")) { case result.Err(failure): match failure { case DuplicateLiteral(_): case _: t.Fatal(failure) }; case result.Ok(_): t.Fatal("duplicate literal was accepted") } }

func requireLiteralArena(t *testing.T) *LiteralArena { match NewLiteralArena(4096) { case result.Err(failure): t.Fatal(failure); return nil; case result.Ok(literals): return literals } }
