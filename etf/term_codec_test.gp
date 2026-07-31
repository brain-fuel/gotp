package etf

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"math/big"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func TestCanonicalCodecKnownTupleEncoding(t *testing.T) {
	codec := CanonicalCodec{}
	value := term.Tuple(term.MustAtom("ok"), term.Integer(42))
	match codec.Encode(value) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(encoded):
		want := []byte{131, 104, 2, 119, 2, 'o', 'k', 97, 42}
		if !bytes.Equal(encoded, want) {
			t.Fatalf("encoded = %v, want %v", encoded, want)
		}
		match codec.Decode(encoded) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(decoded):
			if !decoded.Equal(value) {
				t.Fatalf("decoded = %#v", decoded)
			}
		}
	}
}

func TestCanonicalRoundTripLaw(t *testing.T) {
	codec := CanonicalCodec{}
	law := func(integer int64, raw []byte) bool {
		value := term.Tuple(
			term.MustAtom("value"),
			term.Integer(integer),
			term.Binary(raw),
			term.List(term.Integer(1), term.Integer(2)),
		)
		match codec.Encode(value) {
		case result.Err(_):
			return false
		case result.Ok(encoded):
			match codec.Decode(encoded) {
			case result.Ok(decoded):
				return decoded.Equal(value)
			case result.Err(_):
				return false
			}
		}
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 1_000})) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}

func TestCanonicalMapEncodingIgnoresInsertionOrder(t *testing.T) {
	leftResult := term.Map([]term.MapEntry{
		{Key: term.MustAtom("a"), Value: term.Integer(1)},
		{Key: term.MustAtom("b"), Value: term.Integer(2)},
	})
	rightResult := term.Map([]term.MapEntry{
		{Key: term.MustAtom("b"), Value: term.Integer(2)},
		{Key: term.MustAtom("a"), Value: term.Integer(1)},
	})
	match leftResult {
	case result.Err(cause):
		t.Fatal(cause.Error())
	case result.Ok(left):
		match rightResult {
		case result.Err(cause):
			t.Fatal(cause.Error())
		case result.Ok(right):
			codec := CanonicalCodec{}
			match codec.Encode(left) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(leftEncoded):
				match codec.Encode(right) {
				case result.Err(failure):
					t.Fatal(failure.Error())
				case result.Ok(rightEncoded):
					if !bytes.Equal(leftEncoded, rightEncoded) {
						t.Fatalf("map encodings differ:\n%x\n%x", leftEncoded, rightEncoded)
					}
				}
			}
		}
	}
}

func TestModernIdentifierRoundTrip(t *testing.T) {
	match NewStaticNodeTable(map[uint32]string{1: "gotp@localhost"}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(nodes):
		codec := CanonicalCodec{Nodes: nodes}
		reference := term.Reference{
			Node: 1, Creation: 7, Words: [5]uint32{1, 2, 3, 4, 5}, Length: 5,
		}
		value := term.Tuple(
			term.PIDTerm(term.PID{Node: 1, Number: 9, Serial: 2, Creation: 7}),
			term.ReferenceTerm(reference),
			term.PortTerm(term.Port{Node: 1, ID: 1 << 40, Creation: 7}),
		)
		match codec.Encode(value) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(encoded):
			if !bytes.Contains(encoded, []byte{canonicalNewPID}) ||
				!bytes.Contains(encoded, []byte{canonicalNewerReference}) ||
				!bytes.Contains(encoded, []byte{canonicalV4Port}) {
				t.Fatalf("modern tags missing from %x", encoded)
			}
			match codec.Decode(encoded) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(decoded):
				if !decoded.Equal(value) {
					t.Fatalf("decoded = %#v", decoded)
				}
			}
		}
	}
}

func TestBigIntegerRoundTrip(t *testing.T) {
	integer := new(big.Int).Lsh(big.NewInt(1), 4_096)
	integer.Neg(integer)
	match term.BigInteger(integer) {
	case result.Err(cause):
		t.Fatal(cause.Error())
	case result.Ok(value):
		codec := CanonicalCodec{}
		match codec.Encode(value) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(encoded):
			match codec.Decode(encoded) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(decoded):
				match decoded {
				case term.IntegerTerm(got):
					if got.Cmp(integer) != 0 {
						t.Fatalf("decoded integer = %v", got)
					}
				case _:
					t.Fatal("decoded value is not an integer")
				}
			}
		}
	}
}

func TestDecodeCompressedTerm(t *testing.T) {
	body := []byte{
		canonicalSmallTuple, 2,
		canonicalSmallAtomUTF8, 2, 'o', 'k',
		canonicalSmallInteger, 7,
	}
	var compressed bytes.Buffer
	compressed.WriteByte(canonicalVersion)
	compressed.WriteByte(canonicalCompressed)
	var size [4]byte
	binary.BigEndian.PutUint32(size[:], uint32(len(body)))
	compressed.Write(size[:])
	writer := zlib.NewWriter(&compressed)
	_, writeError := writer.Write(body)
	match result.Of(true, writeError) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
	match result.Of(true, writer.Close()) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
	codec := CanonicalCodec{}
	match codec.Decode(compressed.Bytes()) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(value):
		want := term.Tuple(term.MustAtom("ok"), term.Integer(7))
		if !value.Equal(want) {
			t.Fatalf("value = %#v", value)
		}
	}
}

func TestCanonicalDecodeNeverPanics(t *testing.T) {
	codec := CanonicalCodec{Limits: TermLimits{
		MaxDepth: 16, MaxContainer: 64, MaxBinaryBytes: 256,
		MaxBigIntBytes: 256, MaxTotalBytes: 1_024,
	}}
	law := func(data []byte) bool {
		if len(data) > 1_024 {
			data = data[:1_024]
		}
		codec.Decode(data)
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2_000})) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}

func TestDecodeRejectsDuplicateMapKeys(t *testing.T) {
	encoded := []byte{
		canonicalVersion,
		canonicalMap, 0, 0, 0, 2,
		canonicalSmallInteger, 1, canonicalSmallAtomUTF8, 1, 'a',
		canonicalSmallInteger, 1, canonicalSmallAtomUTF8, 1, 'b',
	}
	codec := CanonicalCodec{}
	match codec.Decode(encoded) {
	case result.Err(_):
	case result.Ok(_):
		t.Fatal("duplicate map keys were accepted")
	}
}
