package distribution

import (
	"bytes"
	"strings"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

// assayxport:unit gotp.distribution.atom-cache-header-laws
func TestAtomCacheHeaderMatchesOTPLayout(t *testing.T) {
	cache := NewAtomCache()
	references := []AtomReference{
		{Segment: 4, Internal: 236, NewAtom: option.Some("reg")},
		{Segment: 1, Internal: 9, NewAtom: option.Some("call")},
	}
	match cache.EncodeHeader(references) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(encoded):
		want := []byte{131, 68, 2, 0x9c, 0, 236, 3, 'r', 'e', 'g', 9, 4, 'c', 'a', 'l', 'l'}
		if !bytes.Equal(encoded, want) { t.Fatalf("encoded = %v, want %v", encoded, want) }
	}
}

func TestAtomCachePersistsReferencesAcrossHeaders(t *testing.T) {
	sender := NewAtomCache()
	receiver := NewAtomCache()
	first := []AtomReference{{Segment: 3, Internal: 7, NewAtom: option.Some("worker")}}
	match sender.EncodeHeader(first) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(encoded):
		match receiver.DecodeHeader(append(encoded, 99, 100)) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(header):
			if header.BytesConsumed != len(encoded) || len(header.Atoms) != 1 || header.Atoms[0] != "worker" {
				t.Fatalf("header = %#v", header)
			}
		}
	}
	second := []AtomReference{{Segment: 3, Internal: 7, NewAtom: option.None[string]}}
	match sender.EncodeHeader(second) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(encoded):
		match receiver.DecodeHeader(encoded) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(header): if header.Atoms[0] != "worker" { t.Fatalf("atoms = %v", header.Atoms) }
		}
	}
}

func TestLongAtomFlagAppliesToAllNewEntries(t *testing.T) {
	long := strings.Repeat("\u00e9", 128)
	cache := NewAtomCache()
	match cache.EncodeHeader([]AtomReference{
		{Segment: 0, Internal: 1, NewAtom: option.Some("a")},
		{Segment: 0, Internal: 2, NewAtom: option.Some(long)},
	}) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(encoded):
		if encoded[4]&1 == 0 { t.Fatal("long-atoms flag is unset") }
		match NewAtomCache().DecodeHeader(encoded) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(header):
			if header.Atoms[0] != "a" || header.Atoms[1] != long { t.Fatal("long atoms did not round trip") }
		}
	}
}

func TestMalformedHeaderRollsBackCacheUpdates(t *testing.T) {
	cache := NewAtomCache()
	malformed := []byte{131, 68, 2, 0x88, 0, 1, 1, 'a', 2, 5, 'b'}
	match cache.DecodeHeader(malformed) {
	case result.Err(_):
	case result.Ok(_): t.Fatal("malformed header was accepted")
	}
	match cache.EncodeHeader([]AtomReference{{Segment: 0, Internal: 1, NewAtom: option.None[string]}}) {
	case result.Err(_):
	case result.Ok(_): t.Fatal("failed decode leaked cache update")
	}
}

func TestAtomCacheDecoderNeverPanics(t *testing.T) {
	law := func(raw []byte) bool {
		if len(raw) > 1024 { raw = raw[:1024] }
		NewAtomCache().DecodeHeader(raw)
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2_000})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}
