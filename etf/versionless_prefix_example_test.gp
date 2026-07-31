package etf

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

// assayxport:unit gotp.etf.versionless-prefix-laws
func TestVersionlessPrefixResolvesNestedAtomCacheReferences(t *testing.T) {
	encoded := []byte{
		canonicalSmallTuple, 2,
		canonicalAtomCacheRef, 0,
		canonicalSmallInteger, 7,
		canonicalSmallInteger, 99,
	}
	codec := CanonicalCodec{}
	match codec.DecodeVersionlessPrefix(encoded, []string{"cached"}) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(prefix):
		want := term.Tuple(term.MustAtom("cached"), term.Integer(7))
		if !prefix.Value.Equal(want) || prefix.BytesConsumed != 6 {
			t.Fatalf("prefix = %#v", prefix)
		}
	}
}

func TestVersionlessPrefixRejectsUndefinedAtomReference(t *testing.T) {
	codec := CanonicalCodec{}
	match codec.DecodeVersionlessPrefix([]byte{canonicalAtomCacheRef, 1}, []string{"only"}) {
	case result.Err(_):
	case result.Ok(_): t.Fatal("undefined atom reference was accepted")
	}
}

func TestVersionlessPrefixNeverPanics(t *testing.T) {
	codec := CanonicalCodec{Limits: TermLimits{
		MaxDepth: 16, MaxContainer: 64, MaxBinaryBytes: 256,
		MaxBigIntBytes: 256, MaxTotalBytes: 1024,
	}}
	law := func(raw []byte) bool {
		if len(raw) > 1024 { raw = raw[:1024] }
		codec.DecodeVersionlessPrefix(raw, []string{"cached"})
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2_000})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}
