package beam

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"fmt"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

func literalPayload(values ...term.Term) []byte {
	payload := make([]byte, 4)
	binary.BigEndian.PutUint32(payload, uint32(len(values)))
	codec := etf.CanonicalCodec{}
	for _, value := range values {
		match codec.Encode(value) {
		case result.Err(failure):
			panic(failure.Error())
		case result.Ok(encoded):
			var length [4]byte
			binary.BigEndian.PutUint32(length[:], uint32(len(encoded)))
			payload = append(payload, length[:]...)
			payload = append(payload, encoded...)
		}
	}
	return payload
}

func uncompressedLiteralChunk(values ...term.Term) []byte {
	return append([]byte{0, 0, 0, 0}, literalPayload(values...)...)
}

func compressedLiteralChunk(values ...term.Term) []byte {
	payload := literalPayload(values...)
	var compressed bytes.Buffer
	writer := zlib.NewWriter(&compressed)
	var written result.Result[int, error] = result.Of(writer.Write(payload))
	match written {
	case result.Err(cause):
		panic(cause)
	case result.Ok(_):
	}
	match result.Of(true, writer.Close()) {
	case result.Err(cause):
		panic(cause)
	case result.Ok(_):
	}
	chunk := make([]byte, 4, 4+compressed.Len())
	binary.BigEndian.PutUint32(chunk, uint32(len(payload)))
	return append(chunk, compressed.Bytes()...)
}

// ExampleDecodeLiteralChunk is the literal-table decoding example.
func ExampleDecodeLiteralChunk() {
	chunk := uncompressedLiteralChunk(
		term.Tuple(term.MustAtom("ok"), term.Integer(42)),
		term.Binary([]byte("beam")),
	)
	match DecodeLiteralChunk(chunk, LiteralDecodeLimits{}) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(literals):
		fmt.Println(len(literals), term.Equal(literals[0], term.Tuple(term.MustAtom("ok"), term.Integer(42))))
	}
	// Output:
	// 2 true
}

// assayxport:law gotp.beam.literal-table-laws
func TestLiteralTableCompressionParity(t *testing.T) {
	values := []term.Term{
		term.Integer(-7),
		term.Tuple(term.MustAtom("literal"), term.Binary([]byte{1, 2, 3})),
		term.List(term.Integer(1), term.Integer(2)),
	}
	var plain map[uint64]term.Term
	match DecodeLiteralChunk(uncompressedLiteralChunk(values...), LiteralDecodeLimits{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(decoded):
		plain = decoded
	}
	match DecodeLiteralChunk(compressedLiteralChunk(values...), LiteralDecodeLimits{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(compressed):
		if len(compressed) != len(plain) {
			t.Fatalf("compressed count = %d, plain = %d", len(compressed), len(plain))
		}
		for index := range plain {
			if !term.Equal(plain[index], compressed[index]) {
				t.Fatalf("literal %d differs", index)
			}
		}
	}
}

func TestLiteralDecoderNeverPanics(t *testing.T) {
	law := func(data []byte) bool {
		_ = DecodeLiteralChunk(data, LiteralDecodeLimits{
			MaxCompressedBytes: 1 << 10,
			MaxUncompressedBytes: 1 << 10,
			MaxLiterals: 32,
			TermLimits: etf.TermLimits{
				MaxDepth: 16,
				MaxContainer: 32,
				MaxBinaryBytes: 1 << 10,
				MaxBigIntBytes: 128,
				MaxTotalBytes: 1 << 10,
			},
		})
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 1_000})) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}
