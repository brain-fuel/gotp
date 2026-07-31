package etf

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"fmt"
	"io"
	"math"
	"math/big"
	"sort"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

const (
	canonicalVersion         = 131
	canonicalCompressed      = 80
	canonicalAtomCacheRef    = 82
	canonicalNewPID          = 88
	canonicalNewPort         = 89
	canonicalNewerReference  = 90
	canonicalSmallInteger    = 97
	canonicalInteger         = 98
	canonicalFloat           = 70
	canonicalAtomLatin1      = 100
	canonicalReference       = 101
	canonicalPort            = 102
	canonicalPID             = 103
	canonicalSmallTuple      = 104
	canonicalLargeTuple      = 105
	canonicalNil             = 106
	canonicalString          = 107
	canonicalList            = 108
	canonicalBinary          = 109
	canonicalSmallBig        = 110
	canonicalLargeBig        = 111
	canonicalNewReference    = 114
	canonicalSmallAtomLatin1 = 115
	canonicalMap             = 116
	canonicalAtomUTF8        = 118
	canonicalSmallAtomUTF8   = 119
	canonicalV4Port          = 120
)

// NodeResolver is an explicit capability. Identifier codecs cannot silently
// consult global distribution state.
type NodeResolver interface {
	Name(uint32) option.Option[string]
	ID(string) option.Option[uint32]
}

type StaticNodeTable struct {
	byID   map[uint32]string
	byName map[string]uint32
}

func NewStaticNodeTable(nodes map[uint32]string) result.Result[*StaticNodeTable, Failure] {
	table := &StaticNodeTable{
		byID:   make(map[uint32]string, len(nodes)),
		byName: make(map[string]uint32, len(nodes)),
	}
	for id, name := range nodes {
		if id == 0 {
			return result.Err[*StaticNodeTable, Failure](Invalid("node table", "node ID zero is reserved"))
		}
		match term.Atom(name) {
		case result.Err(cause):
			return result.Err[*StaticNodeTable, Failure](TermRejected(cause))
		case result.Ok(_):
		}
		prior, duplicate := table.byName[name]
		match option.Of(prior, duplicate) {
		case option.Some(first):
			return result.Err[*StaticNodeTable, Failure](Invalid(
				"node table",
				fmt.Sprintf("node name %q maps to both %d and %d", name, first, id),
			))
		case option.None:
		}
		table.byID[id] = name
		table.byName[name] = id
	}
	return result.Ok[*StaticNodeTable, Failure](table)
}

func (table *StaticNodeTable) Name(id uint32) option.Option[string] {
	name, present := table.byID[id]
	return option.Of(name, present)
}

func (table *StaticNodeTable) ID(name string) option.Option[uint32] {
	id, present := table.byName[name]
	return option.Of(id, present)
}

type TermLimits struct {
	MaxDepth       int
	MaxContainer   int
	MaxBinaryBytes int
	MaxBigIntBytes int
	MaxTotalBytes  int
}

func DefaultTermLimits() TermLimits {
	return TermLimits{
		MaxDepth:       128,
		MaxContainer:   1_000_000,
		MaxBinaryBytes: 64 << 20,
		MaxBigIntBytes: 1 << 20,
		MaxTotalBytes:  128 << 20,
	}
}

func (limits TermLimits) normalized() TermLimits {
	defaults := DefaultTermLimits()
	if limits.MaxDepth <= 0 {
		limits.MaxDepth = defaults.MaxDepth
	}
	if limits.MaxContainer <= 0 {
		limits.MaxContainer = defaults.MaxContainer
	}
	if limits.MaxBinaryBytes <= 0 {
		limits.MaxBinaryBytes = defaults.MaxBinaryBytes
	}
	if limits.MaxBigIntBytes <= 0 {
		limits.MaxBigIntBytes = defaults.MaxBigIntBytes
	}
	if limits.MaxTotalBytes <= 0 {
		limits.MaxTotalBytes = defaults.MaxTotalBytes
	}
	return limits
}

type CanonicalCodec struct {
	Nodes  NodeResolver
	Limits TermLimits
}

type DecodedPrefix struct {
	Value         term.Term
	BytesConsumed int
}

func (codec CanonicalCodec) Encode(value term.Term) result.Result[[]byte, Failure] {
	encoder := canonicalEncoder{nodes: codec.Nodes, limits: codec.Limits.normalized()}
	match encoder.encodeTerm(value, 0) {
	case result.Err(failure):
		return result.Err[[]byte, Failure](failure)
	case result.Ok(body):
		if len(body)+1 > encoder.limits.MaxTotalBytes {
			return result.Err[[]byte, Failure](LimitExceeded(
				"encoded bytes",
				len(body)+1,
				encoder.limits.MaxTotalBytes,
			))
		}
		return result.Ok[[]byte, Failure](append([]byte{canonicalVersion}, body...))
	}
}

func (codec CanonicalCodec) Decode(encoded []byte) result.Result[term.Term, Failure] {
	limits := codec.Limits.normalized()
	if len(encoded) < 2 || encoded[0] != canonicalVersion {
		return result.Err[term.Term, Failure](MissingVersion())
	}
	if len(encoded) > limits.MaxTotalBytes {
		return result.Err[term.Term, Failure](LimitExceeded("input bytes", len(encoded), limits.MaxTotalBytes))
	}
	body := encoded[1:]
	if body[0] == canonicalCompressed {
		match decompressCanonical(body[1:], limits) {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(uncompressed):
			body = uncompressed
		}
	}
	decoder := canonicalDecoder{data: body, nodes: codec.Nodes, limits: limits}
	match decoder.decodeTerm(0) {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(value):
		if decoder.position != len(decoder.data) {
			return result.Err[term.Term, Failure](TrailingBytes(len(decoder.data) - decoder.position))
		}
		return result.Ok[term.Term, Failure](value)
	}
}

// assayxport:unit gotp.etf.versionless-prefix
func (codec CanonicalCodec) DecodeVersionlessPrefix(
	encoded []byte,
	atomReferences []string,
) result.Result[DecodedPrefix, Failure] {
	limits := codec.Limits.normalized()
	if len(encoded) == 0 {
		return result.Err[DecodedPrefix, Failure](MissingVersion())
	}
	if len(encoded) > limits.MaxTotalBytes {
		return result.Err[DecodedPrefix, Failure](LimitExceeded("input bytes", len(encoded), limits.MaxTotalBytes))
	}
	for _, name := range atomReferences {
		match term.Atom(name) {
		case result.Err(cause):
			return result.Err[DecodedPrefix, Failure](TermRejected(cause))
		case result.Ok(_):
		}
	}
	decoder := canonicalDecoder{
		data: encoded, nodes: codec.Nodes, limits: limits,
		atomReferences: append([]string{}, atomReferences...),
	}
	match decoder.decodeTerm(0) {
	case result.Err(failure):
		return result.Err[DecodedPrefix, Failure](failure)
	case result.Ok(value):
		return result.Ok[DecodedPrefix, Failure](DecodedPrefix{
			Value: value, BytesConsumed: decoder.position,
		})
	}
}

type canonicalEncoder struct {
	nodes  NodeResolver
	limits TermLimits
}

func (encoder canonicalEncoder) encodeTerm(value term.Term, depth int) result.Result[[]byte, Failure] {
	if depth >= encoder.limits.MaxDepth {
		return result.Err[[]byte, Failure](LimitExceeded("nesting depth", depth, encoder.limits.MaxDepth))
	}
	match value {
	case term.IntegerTerm(integer):
		return encoder.integer(integer)
	case term.FloatTerm(value):
		encoded := make([]byte, 9)
		encoded[0] = canonicalFloat
		binary.BigEndian.PutUint64(encoded[1:], value)
		return result.Ok[[]byte, Failure](encoded)
	case term.AtomTerm(name):
		return encodeUTF8Atom(name)
	case term.BinaryTerm(value):
		if len(value) > encoder.limits.MaxBinaryBytes || uint64(len(value)) > uint64(^uint32(0)) {
			return result.Err[[]byte, Failure](LimitExceeded(
				"binary bytes",
				len(value),
				encoder.limits.MaxBinaryBytes,
			))
		}
		encoded := make([]byte, 5+len(value))
		encoded[0] = canonicalBinary
		binary.BigEndian.PutUint32(encoded[1:5], uint32(len(value)))
		copy(encoded[5:], value)
		return result.Ok[[]byte, Failure](encoded)
	case term.TupleTerm(values):
		return encoder.tuple(values, depth)
	case term.ProperListTerm(values):
		return encoder.list(values, option.None[term.Term], depth)
	case term.ImproperListTerm(values, tail):
		return encoder.list(values, option.Some(tail), depth)
	case term.MapTerm(entries):
		return encoder.mapValue(entries, depth)
	case term.PIDTerm(pid):
		return encoder.pid(pid)
	case term.ReferenceTerm(reference):
		return encoder.reference(reference)
	case term.FunTerm(function):
		return encoder.function(function, depth)
	case term.PortTerm(port):
		return encoder.port(port)
	case term.InvalidTerm:
		return result.Err[[]byte, Failure](Invalid("term", "invalid terms are not encodable"))
	}
}

func (encoder canonicalEncoder) integer(value *big.Int) result.Result[[]byte, Failure] {
	if value.Sign() >= 0 && value.IsUint64() && value.Uint64() <= 255 {
		return result.Ok[[]byte, Failure]([]byte{canonicalSmallInteger, byte(value.Uint64())})
	}
	if value.IsInt64() {
		integer := value.Int64()
		if integer >= -1<<31 && integer <= 1<<31-1 {
			encoded := make([]byte, 5)
			encoded[0] = canonicalInteger
			binary.BigEndian.PutUint32(encoded[1:], uint32(int32(integer)))
			return result.Ok[[]byte, Failure](encoded)
		}
	}
	absolute := new(big.Int).Abs(value)
	digits := absolute.Bytes()
	if len(digits) > encoder.limits.MaxBigIntBytes || uint64(len(digits)) > uint64(^uint32(0)) {
		return result.Err[[]byte, Failure](LimitExceeded(
			"big integer bytes",
			len(digits),
			encoder.limits.MaxBigIntBytes,
		))
	}
	reverse(digits)
	sign := byte(0)
	if value.Sign() < 0 {
		sign = 1
	}
	if len(digits) <= 255 {
		return result.Ok[[]byte, Failure](append(
			[]byte{canonicalSmallBig, byte(len(digits)), sign},
			digits...,
		))
	}
	encoded := make([]byte, 6, 6+len(digits))
	encoded[0] = canonicalLargeBig
	binary.BigEndian.PutUint32(encoded[1:5], uint32(len(digits)))
	encoded[5] = sign
	return result.Ok[[]byte, Failure](append(encoded, digits...))
}

func (encoder canonicalEncoder) tuple(values []term.Term, depth int) result.Result[[]byte, Failure] {
	if len(values) > encoder.limits.MaxContainer || uint64(len(values)) > uint64(^uint32(0)) {
		return result.Err[[]byte, Failure](LimitExceeded(
			"tuple elements",
			len(values),
			encoder.limits.MaxContainer,
		))
	}
	var encoded []byte
	if len(values) <= 255 {
		encoded = []byte{canonicalSmallTuple, byte(len(values))}
	} else {
		encoded = make([]byte, 5)
		encoded[0] = canonicalLargeTuple
		binary.BigEndian.PutUint32(encoded[1:], uint32(len(values)))
	}
	for _, value := range values {
		match encoder.encodeTerm(value, depth+1) {
		case result.Ok(item):
			encoded = append(encoded, item...)
		case result.Err(failure):
			return result.Err[[]byte, Failure](failure)
		}
	}
	return result.Ok[[]byte, Failure](encoded)
}

func (encoder canonicalEncoder) list(
	values []term.Term,
	tail option.Option[term.Term],
	depth int,
) result.Result[[]byte, Failure] {
	if len(values) > encoder.limits.MaxContainer || uint64(len(values)) > uint64(^uint32(0)) {
		return result.Err[[]byte, Failure](LimitExceeded(
			"list elements",
			len(values),
			encoder.limits.MaxContainer,
		))
	}
	match tail {
	case option.None:
		if len(values) == 0 {
			return result.Ok[[]byte, Failure]([]byte{canonicalNil})
		}
	case option.Some(_):
	}
	encoded := make([]byte, 5)
	encoded[0] = canonicalList
	binary.BigEndian.PutUint32(encoded[1:], uint32(len(values)))
	for _, value := range values {
		match encoder.encodeTerm(value, depth+1) {
		case result.Ok(item):
			encoded = append(encoded, item...)
		case result.Err(failure):
			return result.Err[[]byte, Failure](failure)
		}
	}
	match tail {
	case option.None:
		encoded = append(encoded, canonicalNil)
	case option.Some(value):
		match encoder.encodeTerm(value, depth+1) {
		case result.Ok(encodedTail):
			encoded = append(encoded, encodedTail...)
		case result.Err(failure):
			return result.Err[[]byte, Failure](failure)
		}
	}
	return result.Ok[[]byte, Failure](encoded)
}

type encodedMapEntry struct {
	key   []byte
	value []byte
}

func (encoder canonicalEncoder) mapValue(entries []term.MapEntry, depth int) result.Result[[]byte, Failure] {
	if len(entries) > encoder.limits.MaxContainer || uint64(len(entries)) > uint64(^uint32(0)) {
		return result.Err[[]byte, Failure](LimitExceeded(
			"map entries",
			len(entries),
			encoder.limits.MaxContainer,
		))
	}
	encodedEntries := make([]encodedMapEntry, len(entries))
	for index, entry := range entries {
		match encoder.encodeTerm(entry.Key, depth+1) {
		case result.Err(failure):
			return result.Err[[]byte, Failure](failure)
		case result.Ok(key):
			match encoder.encodeTerm(entry.Value, depth+1) {
			case result.Err(failure):
				return result.Err[[]byte, Failure](failure)
			case result.Ok(value):
				encodedEntries[index] = encodedMapEntry{key: key, value: value}
			}
		}
	}
	sort.Slice(encodedEntries, func(left, right int) bool {
		order := bytes.Compare(encodedEntries[left].key, encodedEntries[right].key)
		if order != 0 {
			return order < 0
		}
		return bytes.Compare(encodedEntries[left].value, encodedEntries[right].value) < 0
	})
	encoded := make([]byte, 5)
	encoded[0] = canonicalMap
	binary.BigEndian.PutUint32(encoded[1:], uint32(len(entries)))
	for _, entry := range encodedEntries {
		encoded = append(encoded, entry.key...)
		encoded = append(encoded, entry.value...)
	}
	return result.Ok[[]byte, Failure](encoded)
}

func (encoder canonicalEncoder) pid(pid term.PID) result.Result[[]byte, Failure] {
	match encoder.node(pid.Node) {
	case result.Err(failure):
		return result.Err[[]byte, Failure](failure)
	case result.Ok(node):
		if pid.Number > uint64(^uint32(0)) {
			return result.Err[[]byte, Failure](Invalid(
				"PID",
				fmt.Sprintf("number %d does not fit NEW_PID_EXT", pid.Number),
			))
		}
		encoded := append([]byte{canonicalNewPID}, node...)
		fields := make([]byte, 12)
		binary.BigEndian.PutUint32(fields[0:4], uint32(pid.Number))
		binary.BigEndian.PutUint32(fields[4:8], pid.Serial)
		binary.BigEndian.PutUint32(fields[8:12], pid.Creation)
		return result.Ok[[]byte, Failure](append(encoded, fields...))
	}
}

func (encoder canonicalEncoder) reference(reference term.Reference) result.Result[[]byte, Failure] {
	if !reference.Valid() {
		return result.Err[[]byte, Failure](Invalid("reference", "reference is not valid"))
	}
	match encoder.node(reference.Node) {
	case result.Err(failure):
		return result.Err[[]byte, Failure](failure)
	case result.Ok(node):
		encoded := []byte{canonicalNewerReference, 0, reference.Length}
		encoded = append(encoded, node...)
		creation := make([]byte, 4)
		binary.BigEndian.PutUint32(creation, reference.Creation)
		encoded = append(encoded, creation...)
		for index := 0; index < int(reference.Length); index++ {
			word := make([]byte, 4)
			binary.BigEndian.PutUint32(word, reference.Words[index])
			encoded = append(encoded, word...)
		}
		return result.Ok[[]byte, Failure](encoded)
	}
}

func (encoder canonicalEncoder) port(port term.Port) result.Result[[]byte, Failure] {
	match encoder.node(port.Node) {
	case result.Err(failure):
		return result.Err[[]byte, Failure](failure)
	case result.Ok(node):
		encoded := append([]byte{canonicalV4Port}, node...)
		fields := make([]byte, 12)
		binary.BigEndian.PutUint64(fields[0:8], port.ID)
		binary.BigEndian.PutUint32(fields[8:12], port.Creation)
		return result.Ok[[]byte, Failure](append(encoded, fields...))
	}
}

func (encoder canonicalEncoder) node(id uint32) result.Result[[]byte, Failure] {
	if encoder.nodes == nil {
		return result.Err[[]byte, Failure](ResolverRequired())
	}
	match encoder.nodes.Name(id) {
	case option.Some(name):
		return encodeUTF8Atom(name)
	case option.None:
		return result.Err[[]byte, Failure](UnknownNodeID(id))
	}
}

type canonicalDecoder struct {
	data     []byte
	position int
	nodes    NodeResolver
	limits   TermLimits
	atomReferences []string
}

func (decoder *canonicalDecoder) decodeTerm(depth int) result.Result[term.Term, Failure] {
	if depth >= decoder.limits.MaxDepth {
		return result.Err[term.Term, Failure](LimitExceeded("nesting depth", depth, decoder.limits.MaxDepth))
	}
	match decoder.byte() {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(tag):
		return decoder.decodeTagged(tag, depth)
	}
}

func (decoder *canonicalDecoder) decodeTagged(tag byte, depth int) result.Result[term.Term, Failure] {
	switch tag {
	case canonicalOldFun:
		return decoder.oldFunction(depth)
	case canonicalNewFun:
		return decoder.newFunction(depth)
	case canonicalExport:
		return decoder.exportedFunction(depth)
	case canonicalSmallInteger:
		match decoder.byte() {
		case result.Ok(value):
			return result.Ok[term.Term, Failure](term.Integer(int64(value)))
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		}
	case canonicalAtomCacheRef:
		match decoder.byte() {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(index):
			if int(index) >= len(decoder.atomReferences) {
				return result.Err[term.Term, Failure](Invalid(
					"atom cache reference",
					fmt.Sprintf("index %d exceeds %d references", index, len(decoder.atomReferences)),
				))
			}
			match term.Atom(decoder.atomReferences[index]) {
			case result.Err(cause):
				return result.Err[term.Term, Failure](TermRejected(cause))
			case result.Ok(atom):
				return result.Ok[term.Term, Failure](atom)
			}
		}
	case canonicalInteger:
		match decoder.uint32() {
		case result.Ok(value):
			return result.Ok[term.Term, Failure](term.Integer(int64(int32(value))))
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		}
	case canonicalFloat:
		match decoder.uint64() {
		case result.Ok(bits):
			return result.Ok[term.Term, Failure](term.Float(math.Float64frombits(bits)))
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		}
	case canonicalAtomUTF8:
		return decoder.atomUTF8(2)
	case canonicalSmallAtomUTF8:
		return decoder.atomUTF8(1)
	case canonicalAtomLatin1:
		return decoder.atomLatin1(2)
	case canonicalSmallAtomLatin1:
		return decoder.atomLatin1(1)
	case canonicalSmallTuple:
		match decoder.byte() {
		case result.Ok(count):
			return decoder.tuple(int(count), depth)
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		}
	case canonicalLargeTuple:
		match decoder.containerLength() {
		case result.Ok(count):
			return decoder.tuple(count, depth)
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		}
	case canonicalNil:
		return result.Ok[term.Term, Failure](term.List())
	case canonicalString:
		return decoder.stringValue()
	case canonicalList:
		return decoder.listValue(depth)
	case canonicalBinary:
		match decoder.binaryLength(decoder.limits.MaxBinaryBytes) {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(length):
			match decoder.take(length) {
			case result.Ok(value):
				return result.Ok[term.Term, Failure](term.Binary(value))
			case result.Err(failure):
				return result.Err[term.Term, Failure](failure)
			}
		}
	case canonicalSmallBig:
		match decoder.byte() {
		case result.Ok(length):
			return decoder.bigInteger(int(length))
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		}
	case canonicalLargeBig:
		match decoder.binaryLength(decoder.limits.MaxBigIntBytes) {
		case result.Ok(length):
			return decoder.bigInteger(length)
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		}
	case canonicalMap:
		return decoder.mapValue(depth)
	case canonicalNewPID:
		return decoder.pid(depth, true)
	case canonicalPID:
		return decoder.pid(depth, false)
	case canonicalNewerReference:
		return decoder.reference(depth, true)
	case canonicalNewReference:
		return decoder.reference(depth, false)
	case canonicalV4Port:
		return decoder.port(depth, 8, 4)
	case canonicalNewPort:
		return decoder.port(depth, 4, 4)
	case canonicalPort:
		return decoder.port(depth, 4, 1)
	case canonicalReference:
		return decoder.oldReference(depth)
	default:
		return result.Err[term.Term, Failure](UnsupportedTag(tag, decoder.position-1))
	}
}

func (decoder *canonicalDecoder) tuple(count int, depth int) result.Result[term.Term, Failure] {
	if count > decoder.limits.MaxContainer {
		return result.Err[term.Term, Failure](LimitExceeded(
			"tuple elements",
			count,
			decoder.limits.MaxContainer,
		))
	}
	values := make([]term.Term, count)
	for index := range values {
		match decoder.decodeTerm(depth+1) {
		case result.Ok(value):
			values[index] = value
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		}
	}
	return result.Ok[term.Term, Failure](term.Tuple(values...))
}

func (decoder *canonicalDecoder) stringValue() result.Result[term.Term, Failure] {
	match decoder.uint16() {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(length):
		match decoder.take(int(length)) {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(raw):
			values := make([]term.Term, len(raw))
			for index, value := range raw {
				values[index] = term.Integer(int64(value))
			}
			return result.Ok[term.Term, Failure](term.List(values...))
		}
	}
}

func (decoder *canonicalDecoder) listValue(depth int) result.Result[term.Term, Failure] {
	match decoder.containerLength() {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(count):
		values := make([]term.Term, count)
		for index := range values {
			match decoder.decodeTerm(depth+1) {
			case result.Ok(value):
				values[index] = value
			case result.Err(failure):
				return result.Err[term.Term, Failure](failure)
			}
		}
		match decoder.decodeTerm(depth+1) {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(tail):
			if isEmptyList(tail) {
				return result.Ok[term.Term, Failure](term.List(values...))
			}
			return result.Ok[term.Term, Failure](term.ImproperList(values, tail))
		}
	}
}

func (decoder *canonicalDecoder) mapValue(depth int) result.Result[term.Term, Failure] {
	match decoder.containerLength() {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(count):
		entries := make([]term.MapEntry, count)
		for index := range entries {
			match decoder.decodeTerm(depth+1) {
			case result.Ok(key):
				entries[index].Key = key
			case result.Err(failure):
				return result.Err[term.Term, Failure](failure)
			}
			match decoder.decodeTerm(depth+1) {
			case result.Ok(value):
				entries[index].Value = value
			case result.Err(failure):
				return result.Err[term.Term, Failure](failure)
			}
		}
		return acceptedTerm(term.Map(entries))
	}
}

func (decoder *canonicalDecoder) atomUTF8(lengthBytes int) result.Result[term.Term, Failure] {
	match decoder.length(lengthBytes) {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(length):
		match decoder.take(length) {
		case result.Ok(raw):
			return acceptedTerm(term.Atom(string(raw)))
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		}
	}
}

func (decoder *canonicalDecoder) atomLatin1(lengthBytes int) result.Result[term.Term, Failure] {
	match decoder.length(lengthBytes) {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(length):
		match decoder.take(length) {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(raw):
			runes := make([]rune, len(raw))
			for index, value := range raw {
				runes[index] = rune(value)
			}
			return acceptedTerm(term.Atom(string(runes)))
		}
	}
}

func (decoder *canonicalDecoder) bigInteger(length int) result.Result[term.Term, Failure] {
	if length > decoder.limits.MaxBigIntBytes {
		return result.Err[term.Term, Failure](LimitExceeded(
			"big integer bytes",
			length,
			decoder.limits.MaxBigIntBytes,
		))
	}
	match decoder.byte() {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(sign):
		if sign > 1 {
			return result.Err[term.Term, Failure](Invalid(
				"big integer",
				fmt.Sprintf("sign %d", sign),
			))
		}
		match decoder.take(length) {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(raw):
			digits := bytes.Clone(raw)
			reverse(digits)
			integer := new(big.Int).SetBytes(digits)
			if sign == 1 {
				integer.Neg(integer)
			}
			return acceptedTerm(term.BigInteger(integer))
		}
	}
}

func (decoder *canonicalDecoder) pid(depth int, modern bool) result.Result[term.Term, Failure] {
	match decoder.node(depth) {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(node):
		match decoder.uint32() {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(id):
			match decoder.uint32() {
			case result.Err(failure):
				return result.Err[term.Term, Failure](failure)
			case result.Ok(serial):
				match decoder.creation(modern) {
				case result.Ok(creation):
					return result.Ok[term.Term, Failure](term.PIDTerm(term.PID{
						Node: node, Number: uint64(id), Serial: serial, Creation: creation,
					}))
				case result.Err(failure):
					return result.Err[term.Term, Failure](failure)
				}
			}
		}
	}
}

func (decoder *canonicalDecoder) reference(depth int, modern bool) result.Result[term.Term, Failure] {
	match decoder.uint16() {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(length):
		if length == 0 || length > 5 {
			return result.Err[term.Term, Failure](Invalid(
				"reference",
				fmt.Sprintf("length %d", length),
			))
		}
		match decoder.node(depth) {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(node):
			match decoder.creation(modern) {
			case result.Err(failure):
				return result.Err[term.Term, Failure](failure)
			case result.Ok(creation):
				reference := term.Reference{Node: node, Creation: creation, Length: uint8(length)}
				for index := 0; index < int(length); index++ {
					match decoder.uint32() {
					case result.Ok(word):
						reference.Words[index] = word
					case result.Err(failure):
						return result.Err[term.Term, Failure](failure)
					}
				}
				if !modern && (creation > 3 || reference.Words[0]>>18 != 0) {
					return result.Err[term.Term, Failure](Invalid("legacy reference", "reserved bits are set"))
				}
				return result.Ok[term.Term, Failure](term.ReferenceTerm(reference))
			}
		}
	}
}

func (decoder *canonicalDecoder) oldReference(depth int) result.Result[term.Term, Failure] {
	match decoder.node(depth) {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(node):
		match decoder.uint32() {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(word):
			match decoder.byte() {
			case result.Err(failure):
				return result.Err[term.Term, Failure](failure)
			case result.Ok(creation):
				if creation > 3 || word>>18 != 0 {
					return result.Err[term.Term, Failure](Invalid("REFERENCE_EXT", "reserved bits are set"))
				}
				return result.Ok[term.Term, Failure](term.ReferenceTerm(term.Reference{
					Node: node, Creation: uint32(creation), Words: [5]uint32{word}, Length: 1,
				}))
			}
		}
	}
}

func (decoder *canonicalDecoder) port(
	depth int,
	idBytes int,
	creationBytes int,
) result.Result[term.Term, Failure] {
	match decoder.node(depth) {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(node):
		var idResult result.Result[uint64, Failure]
		if idBytes == 8 {
			idResult = decoder.uint64()
		} else {
			match decoder.uint32() {
			case result.Ok(id):
				idResult = result.Ok[uint64, Failure](uint64(id))
			case result.Err(failure):
				idResult = result.Err[uint64, Failure](failure)
			}
		}
		match idResult {
		case result.Err(failure):
			return result.Err[term.Term, Failure](failure)
		case result.Ok(id):
			match decoder.creation(creationBytes == 4) {
			case result.Ok(creation):
				return result.Ok[term.Term, Failure](term.PortTerm(term.Port{
					Node: node, ID: id, Creation: creation,
				}))
			case result.Err(failure):
				return result.Err[term.Term, Failure](failure)
			}
		}
	}
}

func (decoder *canonicalDecoder) node(depth int) result.Result[uint32, Failure] {
	match decoder.decodeTerm(depth+1) {
	case result.Err(failure):
		return result.Err[uint32, Failure](failure)
	case result.Ok(node):
		match node {
		case term.AtomTerm(name):
			if decoder.nodes == nil {
				return result.Err[uint32, Failure](ResolverRequired())
			}
			match decoder.nodes.ID(name) {
			case option.Some(id):
				return result.Ok[uint32, Failure](id)
			case option.None:
				return result.Err[uint32, Failure](UnknownNodeName(name))
			}
		case _:
			return result.Err[uint32, Failure](Invalid("identifier node", "node is not an atom"))
		}
	}
}

func (decoder *canonicalDecoder) creation(modern bool) result.Result[uint32, Failure] {
	if modern {
		return decoder.uint32()
	}
	match decoder.byte() {
	case result.Ok(value):
		return result.Ok[uint32, Failure](uint32(value))
	case result.Err(failure):
		return result.Err[uint32, Failure](failure)
	}
}

func (decoder *canonicalDecoder) containerLength() result.Result[int, Failure] {
	return decoder.binaryLength(decoder.limits.MaxContainer)
}

func (decoder *canonicalDecoder) binaryLength(limit int) result.Result[int, Failure] {
	match decoder.uint32() {
	case result.Err(failure):
		return result.Err[int, Failure](failure)
	case result.Ok(value):
		if uint64(value) > uint64(limit) || uint64(value) > uint64(maxInt()) {
			return result.Err[int, Failure](LimitExceeded("container length", int(value), limit))
		}
		return result.Ok[int, Failure](int(value))
	}
}

func (decoder *canonicalDecoder) length(bytes int) result.Result[int, Failure] {
	if bytes == 1 {
		match decoder.byte() {
		case result.Ok(value):
			return result.Ok[int, Failure](int(value))
		case result.Err(failure):
			return result.Err[int, Failure](failure)
		}
	}
	match decoder.uint16() {
	case result.Ok(value):
		return result.Ok[int, Failure](int(value))
	case result.Err(failure):
		return result.Err[int, Failure](failure)
	}
}

func (decoder *canonicalDecoder) byte() result.Result[byte, Failure] {
	match decoder.take(1) {
	case result.Ok(value):
		return result.Ok[byte, Failure](value[0])
	case result.Err(failure):
		return result.Err[byte, Failure](failure)
	}
}

func (decoder *canonicalDecoder) uint16() result.Result[uint16, Failure] {
	match decoder.take(2) {
	case result.Ok(value):
		return result.Ok[uint16, Failure](binary.BigEndian.Uint16(value))
	case result.Err(failure):
		return result.Err[uint16, Failure](failure)
	}
}

func (decoder *canonicalDecoder) uint32() result.Result[uint32, Failure] {
	match decoder.take(4) {
	case result.Ok(value):
		return result.Ok[uint32, Failure](binary.BigEndian.Uint32(value))
	case result.Err(failure):
		return result.Err[uint32, Failure](failure)
	}
}

func (decoder *canonicalDecoder) uint64() result.Result[uint64, Failure] {
	match decoder.take(8) {
	case result.Ok(value):
		return result.Ok[uint64, Failure](binary.BigEndian.Uint64(value))
	case result.Err(failure):
		return result.Err[uint64, Failure](failure)
	}
}

func (decoder *canonicalDecoder) take(length int) result.Result[[]byte, Failure] {
	if length < 0 || length > len(decoder.data)-decoder.position {
		return result.Err[[]byte, Failure](Truncated(decoder.position, length))
	}
	value := decoder.data[decoder.position:decoder.position+length]
	decoder.position += length
	return result.Ok[[]byte, Failure](value)
}

func encodeUTF8Atom(name string) result.Result[[]byte, Failure] {
	match term.Atom(name) {
	case result.Err(cause):
		return result.Err[[]byte, Failure](TermRejected(cause))
	case result.Ok(_):
	}
	raw := []byte(name)
	if len(raw) <= 255 {
		return result.Ok[[]byte, Failure](append(
			[]byte{canonicalSmallAtomUTF8, byte(len(raw))},
			raw...,
		))
	}
	if len(raw) > int(^uint16(0)) {
		return result.Err[[]byte, Failure](LimitExceeded(
			"UTF-8 atom bytes",
			len(raw),
			int(^uint16(0)),
		))
	}
	encoded := make([]byte, 3, 3+len(raw))
	encoded[0] = canonicalAtomUTF8
	binary.BigEndian.PutUint16(encoded[1:], uint16(len(raw)))
	return result.Ok[[]byte, Failure](append(encoded, raw...))
}

func decompressCanonical(encoded []byte, limits TermLimits) result.Result[[]byte, Failure] {
	if len(encoded) < 4 {
		return result.Err[[]byte, Failure](Truncated(0, 4))
	}
	size := binary.BigEndian.Uint32(encoded[:4])
	if uint64(size) > uint64(limits.MaxTotalBytes) || uint64(size) > uint64(maxInt()) {
		return result.Err[[]byte, Failure](LimitExceeded(
			"compressed expansion bytes",
			int(size),
			limits.MaxTotalBytes,
		))
	}
	readerValue, readerError := zlib.NewReader(bytes.NewReader(encoded[4:]))
	match result.Of(readerValue, readerError) {
	case result.Err(cause):
		return result.Err[[]byte, Failure](Foreign("open compressed term", cause))
	case result.Ok(reader):
		defer reader.Close()
		decodedValue, decodedError := io.ReadAll(io.LimitReader(reader, int64(size)+1))
		match result.Of(decodedValue, decodedError) {
		case result.Err(cause):
			return result.Err[[]byte, Failure](Foreign("decompress term", cause))
		case result.Ok(decoded):
			if len(decoded) != int(size) {
				return result.Err[[]byte, Failure](Invalid(
					"compressed size",
					fmt.Sprintf("header says %d, decoded %d", size, len(decoded)),
				))
			}
			return result.Ok[[]byte, Failure](decoded)
		}
	}
}

func acceptedTerm(
	candidate result.Result[term.Term, term.ValidationFailure],
) result.Result[term.Term, Failure] {
	match candidate {
	case result.Ok(value):
		return result.Ok[term.Term, Failure](value)
	case result.Err(cause):
		return result.Err[term.Term, Failure](TermRejected(cause))
	}
}

func isEmptyList(value term.Term) bool {
	match value {
	case term.ProperListTerm(values):
		return len(values) == 0
	case _:
		return false
	}
}

func reverse(value []byte) {
	for left, right := 0, len(value)-1; left < right; left, right = left+1, right-1 {
		value[left], value[right] = value[right], value[left]
	}
}

func maxInt() int {
	return int(^uint(0) >> 1)
}
