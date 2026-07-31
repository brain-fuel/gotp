package etf

import (
	"encoding/binary"
	"fmt"
	"math/big"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

const (
	canonicalNewFun = byte(112)
	canonicalExport = byte(113)
	canonicalOldFun = byte(117)
)

// assayxport:unit gotp.etf.fun-codec
func (encoder canonicalEncoder) function(value term.Fun, depth int) result.Result[[]byte, Failure] {
	if value.Form == nil {
		return result.Err[[]byte, Failure](Invalid("fun", "function form is missing"))
	}
	match value.Form {
	case term.LocalClosure:
		return result.Err[[]byte, Failure](Invalid("fun", "local closure has no ETF creator/code identity"))
	case term.ExportedFunction:
		return encoder.exportedFunction(value, depth)
	case term.OldClosure:
		return encoder.oldFunction(value, depth)
	case term.NewClosure(digest, newIndex, oldIndex):
		return encoder.newFunction(value, digest, newIndex, oldIndex, depth)
	}
}

func (encoder canonicalEncoder) exportedFunction(value term.Fun, depth int) result.Result[[]byte, Failure] {
	if value.Arity > 255 {
		return result.Err[[]byte, Failure](Invalid("export fun", "arity exceeds SMALL_INTEGER_EXT"))
	}
	var module []byte
	match encodeUTF8Atom(value.Module) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(encoded): module = encoded }
	var function []byte
	match encodeUTF8Atom(value.Function) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(encoded): function = encoded }
	return result.Ok[[]byte, Failure](append(append([]byte{canonicalExport}, module...), append(function, canonicalSmallInteger, byte(value.Arity))...))
}

func (encoder canonicalEncoder) oldFunction(value term.Fun, depth int) result.Result[[]byte, Failure] {
	if !value.Creator.Valid() {
		return result.Err[[]byte, Failure](Invalid("old fun", "creator PID is invalid"))
	}
	if len(value.Environment) > encoder.limits.MaxContainer || uint64(len(value.Environment)) > uint64(^uint32(0)) {
		return result.Err[[]byte, Failure](LimitExceeded("fun free values", len(value.Environment), encoder.limits.MaxContainer))
	}
	encoded := make([]byte, 5)
	encoded[0] = canonicalOldFun
	binary.BigEndian.PutUint32(encoded[1:5], uint32(len(value.Environment)))
	match encoder.pid(value.Creator) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(field): encoded = append(encoded, field...) }
	match encodeUTF8Atom(value.Module) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(field): encoded = append(encoded, field...) }
	match encoder.integer(new(big.Int).SetUint64(uint64(value.Index))) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(field): encoded = append(encoded, field...) }
	match encoder.integer(new(big.Int).SetUint64(uint64(value.Unique))) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(field): encoded = append(encoded, field...) }
	for _, captured := range value.Environment {
		match encoder.encodeTerm(captured, depth + 1) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(field): encoded = append(encoded, field...) }
	}
	return result.Ok[[]byte, Failure](encoded)
}

func (encoder canonicalEncoder) newFunction(
	value term.Fun,
	digest [16]byte,
	newIndex uint32,
	oldIndex uint32,
	depth int,
) result.Result[[]byte, Failure] {
	if value.Arity > 255 {
		return result.Err[[]byte, Failure](Invalid("new fun", "arity exceeds one byte"))
	}
	if !value.Creator.Valid() {
		return result.Err[[]byte, Failure](Invalid("new fun", "creator PID is invalid"))
	}
	if len(value.Environment) > encoder.limits.MaxContainer || uint64(len(value.Environment)) > uint64(^uint32(0)) {
		return result.Err[[]byte, Failure](LimitExceeded("fun free values", len(value.Environment), encoder.limits.MaxContainer))
	}
	payload := []byte{byte(value.Arity)}
	payload = append(payload, digest[:]...)
	word := make([]byte, 4)
	binary.BigEndian.PutUint32(word, newIndex)
	payload = append(payload, word...)
	binary.BigEndian.PutUint32(word, uint32(len(value.Environment)))
	payload = append(payload, word...)
	match encodeUTF8Atom(value.Module) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(field): payload = append(payload, field...) }
	match encoder.integer(new(big.Int).SetUint64(uint64(oldIndex))) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(field): payload = append(payload, field...) }
	match encoder.integer(new(big.Int).SetUint64(uint64(value.Unique))) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(field): payload = append(payload, field...) }
	match encoder.pid(value.Creator) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(field): payload = append(payload, field...) }
	for _, captured := range value.Environment {
		match encoder.encodeTerm(captured, depth + 1) { case result.Err(failure): return result.Err[[]byte, Failure](failure); case result.Ok(field): payload = append(payload, field...) }
	}
	if uint64(len(payload)) + 4 > uint64(^uint32(0)) {
		return result.Err[[]byte, Failure](LimitExceeded("new fun bytes", len(payload) + 4, int(^uint32(0))))
	}
	encoded := make([]byte, 5)
	encoded[0] = canonicalNewFun
	binary.BigEndian.PutUint32(encoded[1:5], uint32(len(payload) + 4))
	return result.Ok[[]byte, Failure](append(encoded, payload...))
}

func (decoder *canonicalDecoder) functionAtom(depth int, field string) result.Result[string, Failure] {
	match decoder.decodeTerm(depth + 1) {
	case result.Err(failure):
		return result.Err[string, Failure](failure)
	case result.Ok(value):
		match term.AtomName(value) {
		case option.None:
			return result.Err[string, Failure](Invalid("fun", field + " is not an atom"))
		case option.Some(name):
			return result.Ok[string, Failure](name)
		}
	}
}

func (decoder *canonicalDecoder) functionUint32(depth int, field string) result.Result[uint32, Failure] {
	match decoder.decodeTerm(depth + 1) {
	case result.Err(failure):
		return result.Err[uint32, Failure](failure)
	case result.Ok(value):
		match term.IntegerValue(value) {
		case option.None:
			return result.Err[uint32, Failure](Invalid("fun", field + " is not an integer"))
		case option.Some(integer):
			if integer.Sign() < 0 || !integer.IsUint64() || integer.Uint64() > uint64(^uint32(0)) {
				return result.Err[uint32, Failure](Invalid("fun", field + " is out of uint32 range"))
			}
			return result.Ok[uint32, Failure](uint32(integer.Uint64()))
		}
	}
}

func (decoder *canonicalDecoder) functionPID(depth int) result.Result[term.PID, Failure] {
	match decoder.decodeTerm(depth + 1) {
	case result.Err(failure):
		return result.Err[term.PID, Failure](failure)
	case result.Ok(value):
		match term.TermPIDValue(value) {
		case option.None:
			return result.Err[term.PID, Failure](Invalid("fun", "creator is not a PID"))
		case option.Some(pid):
			return result.Ok[term.PID, Failure](pid)
		}
	}
}

func (decoder *canonicalDecoder) functionEnvironment(count uint32, depth int) result.Result[[]term.Term, Failure] {
	if uint64(count) > uint64(decoder.limits.MaxContainer) {
		return result.Err[[]term.Term, Failure](LimitExceeded("fun free values", int(count), decoder.limits.MaxContainer))
	}
	environment := make([]term.Term, int(count))
	for index := range environment {
		match decoder.decodeTerm(depth + 1) {
		case result.Err(failure):
			return result.Err[[]term.Term, Failure](failure)
		case result.Ok(value):
			environment[index] = value
		}
	}
	return result.Ok[[]term.Term, Failure](environment)
}

func (decoder *canonicalDecoder) oldFunction(depth int) result.Result[term.Term, Failure] {
	var count uint32
	match decoder.uint32() { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): count = value }
	var creator term.PID
	match decoder.functionPID(depth) { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): creator = value }
	var module string
	match decoder.functionAtom(depth, "module") { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): module = value }
	var index uint32
	match decoder.functionUint32(depth, "index") { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): index = value }
	var unique uint32
	match decoder.functionUint32(depth, "unique") { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): unique = value }
	match decoder.functionEnvironment(count, depth) {
	case result.Err(failure):
		return result.Err[term.Term, Failure](failure)
	case result.Ok(environment):
		return result.Ok[term.Term, Failure](term.Function(term.Fun{Form: term.OldClosure(), Module: module, Index: index, Unique: unique, Creator: creator, Environment: environment}))
	}
}

func (decoder *canonicalDecoder) newFunction(depth int) result.Result[term.Term, Failure] {
	var size uint32
	match decoder.uint32() { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): size = value }
	if size < 4 || uint64(size - 4) > uint64(len(decoder.data) - decoder.position) {
		return result.Err[term.Term, Failure](Invalid("new fun", "size exceeds input"))
	}
	end := decoder.position + int(size - 4)
	var arity byte
	match decoder.byte() { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): arity = value }
	var digest [16]byte
	match decoder.take(16) { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): copy(digest[:], value) }
	var newIndex uint32
	match decoder.uint32() { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): newIndex = value }
	var count uint32
	match decoder.uint32() { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): count = value }
	var module string
	match decoder.functionAtom(depth, "module") { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): module = value }
	var oldIndex uint32
	match decoder.functionUint32(depth, "old index") { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): oldIndex = value }
	var unique uint32
	match decoder.functionUint32(depth, "old unique") { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): unique = value }
	var creator term.PID
	match decoder.functionPID(depth) { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): creator = value }
	var environment []term.Term
	match decoder.functionEnvironment(count, depth) { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): environment = value }
	if decoder.position != end {
		return result.Err[term.Term, Failure](Invalid("new fun", fmt.Sprintf("size ends at %d, decoded at %d", end, decoder.position)))
	}
	return result.Ok[term.Term, Failure](term.Function(term.Fun{Form: term.NewClosure(digest, newIndex, oldIndex), Module: module, Arity: uint32(arity), Unique: unique, Creator: creator, Environment: environment}))
}

func (decoder *canonicalDecoder) exportedFunction(depth int) result.Result[term.Term, Failure] {
	var module string
	match decoder.functionAtom(depth, "module") { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): module = value }
	var function string
	match decoder.functionAtom(depth, "function") { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): function = value }
	var arity uint32
	match decoder.functionUint32(depth, "arity") { case result.Err(failure): return result.Err[term.Term, Failure](failure); case result.Ok(value): arity = value }
	if arity > 255 {
		return result.Err[term.Term, Failure](Invalid("export fun", "arity exceeds SMALL_INTEGER_EXT"))
	}
	return result.Ok[term.Term, Failure](term.Function(term.Fun{Form: term.ExportedFunction(), Module: module, Function: function, Arity: arity}))
}
