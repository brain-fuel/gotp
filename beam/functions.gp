package beam

import (
	"encoding/binary"
	"fmt"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

type FunctionTemplate struct {
	Function string
	Arity    uint32
	Label    uint32
	Index    uint32
	Free     uint32
	Unique   uint32
}

type FunctionDecodeLimits struct {
	MaxFunctions int
	MaxFree      uint32
}

type FunctionFailure enum {
	NilFunctionModule()
	MalformedFunctionTable(Detail string)
	FunctionLimitExceeded(Count int, Limit int)
	FunctionFreeLimitExceeded(Index uint32, Count uint32, Limit uint32)
	FunctionAtomMissing(Index uint32, Atom uint32)
}

func ListItems(value Operand) option.Option[[]Operand] {
	match value {
	case ListOperand(items):
		return option.Some(append([]Operand(nil), items...))
	case _:
		return option.None[[]Operand]()
	}
}

func (failure FunctionFailure) Error() string {
	match failure {
	case NilFunctionModule:
		return "gotp/beam: function module is nil"
	case MalformedFunctionTable(detail):
		return "gotp/beam: malformed FunT: " + detail
	case FunctionLimitExceeded(count, limit):
		return fmt.Sprintf("gotp/beam: FunT count %d exceeds limit %d", count, limit)
	case FunctionFreeLimitExceeded(index, count, limit):
		return fmt.Sprintf("gotp/beam: FunT function %d has %d free values; limit is %d", index, count, limit)
	case FunctionAtomMissing(index, atom):
		return fmt.Sprintf("gotp/beam: FunT function %d references atom %d", index, atom)
	}
}

// assayxport:unit gotp.beam.function-table
func DecodeModuleFunctions(module *Module, limits FunctionDecodeLimits) result.Result[map[uint64]FunctionTemplate, FunctionFailure] {
	if module == nil {
		return result.Err[map[uint64]FunctionTemplate, FunctionFailure](NilFunctionModule())
	}
	var raw []byte
	match module.Chunk("FunT") {
	case option.None:
		return result.Ok[map[uint64]FunctionTemplate, FunctionFailure](map[uint64]FunctionTemplate{})
	case option.Some(chunk):
		raw = chunk
	}
	if len(raw) < 4 || (len(raw) - 4) % 24 != 0 {
		return result.Err[map[uint64]FunctionTemplate, FunctionFailure](MalformedFunctionTable("size is not 4 + 24*n"))
	}
	count := int(binary.BigEndian.Uint32(raw[:4]))
	if count != (len(raw) - 4) / 24 {
		return result.Err[map[uint64]FunctionTemplate, FunctionFailure](MalformedFunctionTable("declared count differs from payload"))
	}
	limit := limits.MaxFunctions
	if limit <= 0 { limit = 65536 }
	if count > limit {
		return result.Err[map[uint64]FunctionTemplate, FunctionFailure](FunctionLimitExceeded(count, limit))
	}
	freeLimit := limits.MaxFree
	if freeLimit == 0 { freeLimit = 255 }
	functions := make(map[uint64]FunctionTemplate, count)
	for offset := 0; offset < count; offset++ {
		entry := raw[4 + offset * 24:4 + (offset + 1) * 24]
		atomIndex := binary.BigEndian.Uint32(entry[0:4])
		if atomIndex == 0 || uint64(atomIndex) > uint64(len(module.Atoms)) {
			return result.Err[map[uint64]FunctionTemplate, FunctionFailure](FunctionAtomMissing(uint32(offset), atomIndex))
		}
		free := binary.BigEndian.Uint32(entry[16:20])
		if free > freeLimit {
			return result.Err[map[uint64]FunctionTemplate, FunctionFailure](FunctionFreeLimitExceeded(uint32(offset), free, freeLimit))
		}
		functions[uint64(offset)] = FunctionTemplate{
			Function: module.Atoms[atomIndex - 1],
			Arity: binary.BigEndian.Uint32(entry[4:8]),
			Label: binary.BigEndian.Uint32(entry[8:12]),
			Index: binary.BigEndian.Uint32(entry[12:16]),
			Free: free,
			Unique: binary.BigEndian.Uint32(entry[20:24]),
		}
	}
	return result.Ok[map[uint64]FunctionTemplate, FunctionFailure](functions)
}
