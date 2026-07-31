// Package etf decodes bounded Erlang External Term Format values.
package etf

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"fmt"
	"io"
	"math"
	"math/big"

	"goforge.dev/goplus/std/result"
)

const Version = 131

// RawTerm preserves every ETF shape, including values that are not yet part of
// GoTP's immutable runtime term algebra.
type RawTerm enum {
	RawInteger(Value *big.Int)
	RawFloat(Value float64)
	RawAtom(Name string)
	RawTuple(Elements []RawTerm)
	RawNil()
	RawString(Text string)
	RawList(Elements []RawTerm, Tail RawTerm)
	RawBinary(Bytes []byte)
	RawBitBinary(Bytes []byte, Bits uint8)
	RawMap(Pairs []RawPair)
	RawPID(Identity NodeIdentity)
	RawPort(Identity NodeIdentity)
	RawReference(Identity NodeIdentity)
	RawExport(Module string, Function string, Arity uint32)
	RawOpaque(Tag byte, Bytes []byte)
}

type RawPair struct {
	Key   RawTerm
	Value RawTerm
}

type NodeIdentity struct {
	Node     string
	ID       []uint32
	Serial   uint32
	Creation uint32
}

type Limits struct {
	MaxDepth int
	MaxTerms int
	MaxBytes int
}

func DefaultLimits() Limits {
	return Limits{MaxDepth: 256, MaxTerms: 1_000_000, MaxBytes: 256 << 20}
}

type rawDecoder struct {
	data   []byte
	at     int
	limits Limits
	terms  int
}

func Decode(data []byte, limits Limits) result.Result[RawTerm, Failure] {
	if limits.MaxDepth <= 0 || limits.MaxTerms <= 0 || limits.MaxBytes <= 0 {
		return result.Err[RawTerm, Failure](Invalid("limits", "all limits must be positive"))
	}
	if len(data) > limits.MaxBytes {
		return result.Err[RawTerm, Failure](LimitExceeded("input bytes", len(data), limits.MaxBytes))
	}
	if len(data) == 0 || data[0] != Version {
		return result.Err[RawTerm, Failure](MissingVersion())
	}
	decoder := &rawDecoder{data: data, at: 1, limits: limits}
	match decoder.decodeTerm(0) {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(value):
		if decoder.at != len(data) {
			return result.Err[RawTerm, Failure](TrailingBytes(len(data) - decoder.at))
		}
		return result.Ok[RawTerm, Failure](value)
	}
}

func (decoder *rawDecoder) decodeTerm(depth int) result.Result[RawTerm, Failure] {
	if depth > decoder.limits.MaxDepth {
		return result.Err[RawTerm, Failure](LimitExceeded("nesting depth", depth, decoder.limits.MaxDepth))
	}
	decoder.terms++
	if decoder.terms > decoder.limits.MaxTerms {
		return result.Err[RawTerm, Failure](LimitExceeded("term count", decoder.terms, decoder.limits.MaxTerms))
	}
	match decoder.byte() {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(tag):
		return decoder.decodeTagged(tag, depth)
	}
}

func (decoder *rawDecoder) decodeTagged(tag byte, depth int) result.Result[RawTerm, Failure] {
	switch tag {
	case 97:
		match decoder.byte() {
		case result.Ok(value):
			return result.Ok[RawTerm, Failure](RawInteger(big.NewInt(int64(value))))
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		}
	case 98:
		match decoder.u32() {
		case result.Ok(value):
			return result.Ok[RawTerm, Failure](RawInteger(big.NewInt(int64(int32(value)))))
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		}
	case 70:
		match decoder.u64() {
		case result.Ok(bits):
			return result.Ok[RawTerm, Failure](RawFloat(math.Float64frombits(bits)))
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		}
	case 99:
		return decoder.oldFloat()
	case 100, 118:
		match decoder.u16() {
		case result.Ok(length):
			return decoder.atom(int(length))
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		}
	case 115, 119:
		match decoder.byte() {
		case result.Ok(length):
			return decoder.atom(int(length))
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		}
	case 104:
		match decoder.byte() {
		case result.Ok(arity):
			return decoder.tuple(int(arity), depth)
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		}
	case 105:
		match decoder.u32() {
		case result.Ok(arity):
			return decoder.tuple(int(arity), depth)
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		}
	case 106:
		return result.Ok[RawTerm, Failure](RawNil())
	case 107:
		match decoder.u16() {
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		case result.Ok(length):
			match decoder.take(int(length)) {
			case result.Ok(raw):
				return result.Ok[RawTerm, Failure](RawString(string(raw)))
			case result.Err(failure):
				return result.Err[RawTerm, Failure](failure)
			}
		}
	case 108:
		return decoder.list(depth)
	case 109:
		return decoder.binary(false)
	case 77:
		return decoder.binary(true)
	case 110:
		match decoder.byte() {
		case result.Ok(length):
			return decoder.bigInteger(int(length))
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		}
	case 111:
		match decoder.u32() {
		case result.Ok(length):
			return decoder.bigInteger(int(length))
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		}
	case 116:
		return decoder.mapValue(depth)
	case 103:
		return decoder.pid(depth, false)
	case 88:
		return decoder.pid(depth, true)
	case 102, 89, 120:
		return decoder.port(depth, tag)
	case 101, 114, 90:
		return decoder.reference(depth, tag)
	case 113:
		return decoder.exportValue(depth)
	case 80:
		return decoder.compressed(depth)
	case 112:
		match decoder.u32() {
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		case result.Ok(size):
			match decoder.take(int(size)) {
			case result.Ok(raw):
				return result.Ok[RawTerm, Failure](RawOpaque(tag, bytes.Clone(raw)))
			case result.Err(failure):
				return result.Err[RawTerm, Failure](failure)
			}
		}
	default:
		return result.Err[RawTerm, Failure](UnsupportedTag(tag, decoder.at-1))
	}
}

func (decoder *rawDecoder) oldFloat() result.Result[RawTerm, Failure] {
	match decoder.take(31) {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(raw):
		var value float64
		_, scanError := fmt.Sscanf(string(bytes.TrimRight(raw, "\x00")), "%g", &value)
		match result.Of(value, scanError) {
		case result.Ok(parsed):
			return result.Ok[RawTerm, Failure](RawFloat(parsed))
		case result.Err(cause):
			return result.Err[RawTerm, Failure](Foreign("decode old float", cause))
		}
	}
}

func (decoder *rawDecoder) atom(length int) result.Result[RawTerm, Failure] {
	if length > 1020 {
		return result.Err[RawTerm, Failure](LimitExceeded("atom bytes", length, 1020))
	}
	match decoder.take(length) {
	case result.Ok(raw):
		return result.Ok[RawTerm, Failure](RawAtom(string(raw)))
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	}
}

func (decoder *rawDecoder) sequence(length int, depth int) result.Result[[]RawTerm, Failure] {
	if length < 0 || length > decoder.limits.MaxTerms {
		return result.Err[[]RawTerm, Failure](LimitExceeded("sequence terms", length, decoder.limits.MaxTerms))
	}
	elements := make([]RawTerm, length)
	for index := range elements {
		match decoder.decodeTerm(depth+1) {
		case result.Ok(value):
			elements[index] = value
		case result.Err(failure):
			return result.Err[[]RawTerm, Failure](failure)
		}
	}
	return result.Ok[[]RawTerm, Failure](elements)
}

func (decoder *rawDecoder) tuple(length int, depth int) result.Result[RawTerm, Failure] {
	match decoder.sequence(length, depth) {
	case result.Ok(elements):
		return result.Ok[RawTerm, Failure](RawTuple(elements))
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	}
}

func (decoder *rawDecoder) list(depth int) result.Result[RawTerm, Failure] {
	match decoder.u32() {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(length):
		match decoder.sequence(int(length), depth) {
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		case result.Ok(elements):
			match decoder.decodeTerm(depth+1) {
			case result.Ok(tail):
				return result.Ok[RawTerm, Failure](RawList(elements, tail))
			case result.Err(failure):
				return result.Err[RawTerm, Failure](failure)
			}
		}
	}
}

func (decoder *rawDecoder) binary(withBits bool) result.Result[RawTerm, Failure] {
	match decoder.u32() {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(length):
		bits := uint8(8)
		if withBits {
			match decoder.byte() {
			case result.Err(failure):
				return result.Err[RawTerm, Failure](failure)
			case result.Ok(width):
				if width == 0 || width > 8 {
					return result.Err[RawTerm, Failure](Invalid("bit-binary", fmt.Sprintf("tail width %d", width)))
				}
				bits = width
			}
		}
		match decoder.take(int(length)) {
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		case result.Ok(raw):
			if withBits {
				return result.Ok[RawTerm, Failure](RawBitBinary(bytes.Clone(raw), bits))
			}
			return result.Ok[RawTerm, Failure](RawBinary(bytes.Clone(raw)))
		}
	}
}

func (decoder *rawDecoder) bigInteger(length int) result.Result[RawTerm, Failure] {
	match decoder.byte() {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(sign):
		if sign > 1 {
			return result.Err[RawTerm, Failure](Invalid("big integer", fmt.Sprintf("sign %d", sign)))
		}
		match decoder.take(length) {
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		case result.Ok(little):
			bigEndian := make([]byte, len(little))
			for index := range little {
				bigEndian[len(little)-1-index] = little[index]
			}
			value := new(big.Int).SetBytes(bigEndian)
			if sign == 1 {
				value.Neg(value)
			}
			return result.Ok[RawTerm, Failure](RawInteger(value))
		}
	}
}

func (decoder *rawDecoder) mapValue(depth int) result.Result[RawTerm, Failure] {
	match decoder.u32() {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(length):
		if uint64(length) > uint64(decoder.limits.MaxTerms) {
			return result.Err[RawTerm, Failure](LimitExceeded("map pairs", int(length), decoder.limits.MaxTerms))
		}
		pairs := make([]RawPair, int(length))
		for index := range pairs {
			match decoder.decodeTerm(depth+1) {
			case result.Err(failure):
				return result.Err[RawTerm, Failure](failure)
			case result.Ok(key):
				match decoder.decodeTerm(depth+1) {
				case result.Err(failure):
					return result.Err[RawTerm, Failure](failure)
				case result.Ok(value):
					pairs[index] = RawPair{Key: key, Value: value}
				}
			}
		}
		return result.Ok[RawTerm, Failure](RawMap(pairs))
	}
}

func (decoder *rawDecoder) node(depth int) result.Result[string, Failure] {
	match decoder.decodeTerm(depth+1) {
	case result.Err(failure):
		return result.Err[string, Failure](failure)
	case result.Ok(value):
		match value {
		case RawAtom(name):
			return result.Ok[string, Failure](name)
		case _:
			return result.Err[string, Failure](Invalid("node identity", "node must be an atom"))
		}
	}
}

func (decoder *rawDecoder) pid(depth int, modern bool) result.Result[RawTerm, Failure] {
	match decoder.node(depth) {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(node):
		match decoder.u32() {
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		case result.Ok(id):
			match decoder.u32() {
			case result.Err(failure):
				return result.Err[RawTerm, Failure](failure)
			case result.Ok(serial):
				match decoder.creation(modern) {
				case result.Ok(creation):
					return result.Ok[RawTerm, Failure](RawPID(NodeIdentity{
						Node: node, ID: []uint32{id}, Serial: serial, Creation: creation,
					}))
				case result.Err(failure):
					return result.Err[RawTerm, Failure](failure)
				}
			}
		}
	}
}

func (decoder *rawDecoder) port(depth int, tag byte) result.Result[RawTerm, Failure] {
	match decoder.node(depth) {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(node):
		var idResult result.Result[uint64, Failure]
		if tag == 120 {
			idResult = decoder.u64()
		} else {
			match decoder.u32() {
			case result.Ok(id):
				idResult = result.Ok[uint64, Failure](uint64(id))
			case result.Err(failure):
				idResult = result.Err[uint64, Failure](failure)
			}
		}
		match idResult {
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		case result.Ok(id):
			match decoder.creation(tag != 102) {
			case result.Ok(creation):
				return result.Ok[RawTerm, Failure](RawPort(NodeIdentity{
					Node: node, ID: []uint32{uint32(id), uint32(id >> 32)}, Creation: creation,
				}))
			case result.Err(failure):
				return result.Err[RawTerm, Failure](failure)
			}
		}
	}
}

func (decoder *rawDecoder) reference(depth int, tag byte) result.Result[RawTerm, Failure] {
	if tag == 101 {
		match decoder.node(depth) {
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		case result.Ok(node):
			match decoder.u32() {
			case result.Err(failure):
				return result.Err[RawTerm, Failure](failure)
			case result.Ok(id):
				match decoder.creation(false) {
				case result.Ok(creation):
					return result.Ok[RawTerm, Failure](RawReference(NodeIdentity{
						Node: node, ID: []uint32{id}, Creation: creation,
					}))
				case result.Err(failure):
					return result.Err[RawTerm, Failure](failure)
				}
			}
		}
	}
	match decoder.u16() {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(length):
		match decoder.node(depth) {
		case result.Err(failure):
			return result.Err[RawTerm, Failure](failure)
		case result.Ok(node):
			match decoder.creation(tag == 90) {
			case result.Err(failure):
				return result.Err[RawTerm, Failure](failure)
			case result.Ok(creation):
				ids := make([]uint32, int(length))
				for index := range ids {
					match decoder.u32() {
					case result.Ok(id):
						ids[index] = id
					case result.Err(failure):
						return result.Err[RawTerm, Failure](failure)
					}
				}
				return result.Ok[RawTerm, Failure](RawReference(NodeIdentity{
					Node: node, ID: ids, Creation: creation,
				}))
			}
		}
	}
}

func (decoder *rawDecoder) exportValue(depth int) result.Result[RawTerm, Failure] {
	match decoder.decodeTerm(depth+1) {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(moduleTerm):
		match moduleTerm {
		case RawAtom(module):
			match decoder.decodeTerm(depth+1) {
			case result.Err(failure):
				return result.Err[RawTerm, Failure](failure)
			case result.Ok(functionTerm):
				match functionTerm {
				case RawAtom(function):
					match decoder.decodeTerm(depth+1) {
					case result.Err(failure):
						return result.Err[RawTerm, Failure](failure)
					case result.Ok(arityTerm):
						match arityTerm {
						case RawInteger(arity):
							if arity.Sign() < 0 || !arity.IsUint64() || arity.Uint64() > uint64(^uint32(0)) {
								return result.Err[RawTerm, Failure](Invalid("export", "arity is not uint32"))
							}
							return result.Ok[RawTerm, Failure](RawExport(module, function, uint32(arity.Uint64())))
						case _:
							return result.Err[RawTerm, Failure](Invalid("export", "arity is not an integer"))
						}
					}
				case _:
					return result.Err[RawTerm, Failure](Invalid("export", "function is not an atom"))
				}
			}
		case _:
			return result.Err[RawTerm, Failure](Invalid("export", "module is not an atom"))
		}
	}
}

func (decoder *rawDecoder) compressed(depth int) result.Result[RawTerm, Failure] {
	match decoder.u32() {
	case result.Err(failure):
		return result.Err[RawTerm, Failure](failure)
	case result.Ok(expected):
		if expected > uint32(decoder.limits.MaxBytes) {
			return result.Err[RawTerm, Failure](LimitExceeded("compressed bytes", int(expected), decoder.limits.MaxBytes))
		}
		readerValue, readerError := zlib.NewReader(bytes.NewReader(decoder.data[decoder.at:]))
		match result.Of(readerValue, readerError) {
		case result.Err(cause):
			return result.Err[RawTerm, Failure](Foreign("open compressed stream", cause))
		case result.Ok(reader):
			defer reader.Close()
			rawValue, rawError := io.ReadAll(io.LimitReader(reader, int64(decoder.limits.MaxBytes)+1))
			match result.Of(rawValue, rawError) {
			case result.Err(cause):
				return result.Err[RawTerm, Failure](Foreign("read compressed stream", cause))
			case result.Ok(raw):
				if len(raw) != int(expected) {
					return result.Err[RawTerm, Failure](Invalid(
						"compressed size",
						fmt.Sprintf("header says %d, decoded %d", expected, len(raw)),
					))
				}
				decoder.at = len(decoder.data)
				nested := &rawDecoder{data: raw, limits: decoder.limits, terms: decoder.terms}
				match nested.decodeTerm(depth+1) {
				case result.Err(failure):
					return result.Err[RawTerm, Failure](failure)
				case result.Ok(value):
					if nested.at != len(raw) {
						return result.Err[RawTerm, Failure](TrailingBytes(len(raw) - nested.at))
					}
					decoder.terms = nested.terms
					return result.Ok[RawTerm, Failure](value)
				}
			}
		}
	}
}

func (decoder *rawDecoder) creation(modern bool) result.Result[uint32, Failure] {
	if modern {
		return decoder.u32()
	}
	match decoder.byte() {
	case result.Ok(value):
		return result.Ok[uint32, Failure](uint32(value))
	case result.Err(failure):
		return result.Err[uint32, Failure](failure)
	}
}

func (decoder *rawDecoder) byte() result.Result[byte, Failure] {
	match decoder.take(1) {
	case result.Ok(raw):
		return result.Ok[byte, Failure](raw[0])
	case result.Err(failure):
		return result.Err[byte, Failure](failure)
	}
}

func (decoder *rawDecoder) take(length int) result.Result[[]byte, Failure] {
	if length < 0 || decoder.at > len(decoder.data) || length > len(decoder.data)-decoder.at {
		return result.Err[[]byte, Failure](Truncated(decoder.at, length))
	}
	value := decoder.data[decoder.at:decoder.at+length]
	decoder.at += length
	return result.Ok[[]byte, Failure](value)
}

func (decoder *rawDecoder) u16() result.Result[uint16, Failure] {
	match decoder.take(2) {
	case result.Ok(raw):
		return result.Ok[uint16, Failure](binary.BigEndian.Uint16(raw))
	case result.Err(failure):
		return result.Err[uint16, Failure](failure)
	}
}

func (decoder *rawDecoder) u32() result.Result[uint32, Failure] {
	match decoder.take(4) {
	case result.Ok(raw):
		return result.Ok[uint32, Failure](binary.BigEndian.Uint32(raw))
	case result.Err(failure):
		return result.Err[uint32, Failure](failure)
	}
}

func (decoder *rawDecoder) u64() result.Result[uint64, Failure] {
	match decoder.take(8) {
	case result.Ok(raw):
		return result.Ok[uint64, Failure](binary.BigEndian.Uint64(raw))
	case result.Err(failure):
		return result.Err[uint64, Failure](failure)
	}
}
