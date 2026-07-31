package beam

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"fmt"
	"io"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

//goplus:derive off
type LiteralFailure enum {
	InvalidLiteralChunk(Detail string)
	LiteralLimit(Resource string, Actual int, Limit int)
	LiteralCompressionFailure(Cause error)
	LiteralETFFailure(Index uint64, Cause etf.Failure)
}

func (failure LiteralFailure) Error() string {
	match failure {
	case InvalidLiteralChunk(detail):
		return "beam: invalid LitT chunk: " + detail
	case LiteralLimit(resource, actual, limit):
		return fmt.Sprintf("beam: LitT %s is %d; limit is %d", resource, actual, limit)
	case LiteralCompressionFailure(cause):
		return "beam: decompress LitT chunk: " + cause.Error()
	case LiteralETFFailure(index, cause):
		return fmt.Sprintf("beam: decode literal %d: %v", index, cause)
	}
}

type LiteralDecodeLimits struct {
	MaxCompressedBytes   int
	MaxUncompressedBytes int
	MaxLiterals          int
	TermLimits           etf.TermLimits
}

func DefaultLiteralDecodeLimits() LiteralDecodeLimits {
	return LiteralDecodeLimits{
		MaxCompressedBytes:   64 << 20,
		MaxUncompressedBytes: 256 << 20,
		MaxLiterals:          1_000_000,
		TermLimits:           etf.DefaultTermLimits(),
	}
}

func (limits LiteralDecodeLimits) normalized() LiteralDecodeLimits {
	defaults := DefaultLiteralDecodeLimits()
	if limits.MaxCompressedBytes <= 0 {
		limits.MaxCompressedBytes = defaults.MaxCompressedBytes
	}
	if limits.MaxUncompressedBytes <= 0 {
		limits.MaxUncompressedBytes = defaults.MaxUncompressedBytes
	}
	if limits.MaxLiterals <= 0 {
		limits.MaxLiterals = defaults.MaxLiterals
	}
	if limits.TermLimits.MaxDepth <= 0 {
		limits.TermLimits = defaults.TermLimits
	}
	return limits
}

// assayxport:unit gotp.beam.literal-table
func DecodeModuleLiterals(
	module *Module,
	limits LiteralDecodeLimits,
) result.Result[map[uint64]term.Term, LiteralFailure] {
	if module == nil {
		return result.Err[map[uint64]term.Term, LiteralFailure](InvalidLiteralChunk("module is nil"))
	}
	match module.Chunk("LitT") {
	case option.None:
		return result.Ok[map[uint64]term.Term, LiteralFailure](map[uint64]term.Term{})
	case option.Some(chunk):
		return DecodeLiteralChunk(chunk, limits)
	}
}

func DecodeLiteralChunk(
	chunk []byte,
	limits LiteralDecodeLimits,
) result.Result[map[uint64]term.Term, LiteralFailure] {
	limits = limits.normalized()
	if len(chunk) < 4 {
		return result.Err[map[uint64]term.Term, LiteralFailure](InvalidLiteralChunk("missing compression word"))
	}
	declared := binary.BigEndian.Uint32(chunk[:4])
	payload := chunk[4:]
	if declared != 0 {
		match expandLiteralPayload(payload, int(declared), limits) {
		case result.Err(failure):
			return result.Err[map[uint64]term.Term, LiteralFailure](failure)
		case result.Ok(expanded):
			payload = expanded
		}
	} else if len(payload) > limits.MaxUncompressedBytes {
		return result.Err[map[uint64]term.Term, LiteralFailure](LiteralLimit(
			"uncompressed bytes",
			len(payload),
			limits.MaxUncompressedBytes,
		))
	}
	if len(payload) < 4 {
		return result.Err[map[uint64]term.Term, LiteralFailure](InvalidLiteralChunk("missing literal count"))
	}
	count := uint64(binary.BigEndian.Uint32(payload[:4]))
	if count > uint64(limits.MaxLiterals) {
		return result.Err[map[uint64]term.Term, LiteralFailure](LiteralLimit(
			"count",
			int(count),
			limits.MaxLiterals,
		))
	}
	position := 4
	literals := make(map[uint64]term.Term, int(count))
	codec := etf.CanonicalCodec{Limits: limits.TermLimits}
	for index := uint64(0); index < count; index++ {
		if len(payload)-position < 4 {
			return result.Err[map[uint64]term.Term, LiteralFailure](InvalidLiteralChunk(
				fmt.Sprintf("literal %d is missing its length", index),
			))
		}
		length := uint64(binary.BigEndian.Uint32(payload[position : position+4]))
		position += 4
		if length > uint64(len(payload)-position) {
			return result.Err[map[uint64]term.Term, LiteralFailure](InvalidLiteralChunk(
				fmt.Sprintf("literal %d exceeds the chunk", index),
			))
		}
		encoded := payload[position : position+int(length)]
		position += int(length)
		match codec.Decode(encoded) {
		case result.Err(failure):
			return result.Err[map[uint64]term.Term, LiteralFailure](LiteralETFFailure(index, failure))
		case result.Ok(value):
			literals[index] = value
		}
	}
	if position != len(payload) {
		return result.Err[map[uint64]term.Term, LiteralFailure](InvalidLiteralChunk(
			fmt.Sprintf("%d trailing bytes", len(payload)-position),
		))
	}
	return result.Ok[map[uint64]term.Term, LiteralFailure](literals)
}

// OTP-29.0.4 beam_asm.erl uses zero for uncompressed LitT and the exact
// expanded size for legacy zlib payloads.
func expandLiteralPayload(
	compressed []byte,
	declared int,
	limits LiteralDecodeLimits,
) result.Result[[]byte, LiteralFailure] {
	if len(compressed) > limits.MaxCompressedBytes {
		return result.Err[[]byte, LiteralFailure](LiteralLimit(
			"compressed bytes",
			len(compressed),
			limits.MaxCompressedBytes,
		))
	}
	if declared > limits.MaxUncompressedBytes {
		return result.Err[[]byte, LiteralFailure](LiteralLimit(
			"uncompressed bytes",
			declared,
			limits.MaxUncompressedBytes,
		))
	}
	match result.Of(zlib.NewReader(bytes.NewReader(compressed))) {
	case result.Err(cause):
		return result.Err[[]byte, LiteralFailure](LiteralCompressionFailure(cause))
	case result.Ok(reader):
		match result.Of(io.ReadAll(io.LimitReader(reader, int64(limits.MaxUncompressedBytes)+1))) {
		case result.Err(cause):
			reader.Close()
			return result.Err[[]byte, LiteralFailure](LiteralCompressionFailure(cause))
		case result.Ok(expanded):
			match result.Of(true, reader.Close()) {
			case result.Err(cause):
				return result.Err[[]byte, LiteralFailure](LiteralCompressionFailure(cause))
			case result.Ok(_):
			}
			if len(expanded) != declared {
				return result.Err[[]byte, LiteralFailure](InvalidLiteralChunk(fmt.Sprintf(
					"expanded size is %d; declared %d",
					len(expanded),
					declared,
				)))
			}
			return result.Ok[[]byte, LiteralFailure](expanded)
		}
	}
}
