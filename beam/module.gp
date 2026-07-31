// Package beam parses the stable IFF container around BEAM modules. Pure
// parsing returns Result; file access requires an explicit capability value.
package beam

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"os"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

const (
	formMagic     = "FOR1"
	beamMagic     = "BEAM"
	maxModuleSize = 1 << 30
)

//goplus:derive off
type Failure enum {
	ReadFailure(Path string, Cause error)
	Truncated(Part string)
	ModuleTooLarge(Actual int, Limit int)
	InvalidMagic()
	SizeMismatch(Declared uint64, Actual int)
	ChunkOutOfBounds(ID string)
	DuplicateChunk(ID string)
	InvalidPadding(ID string)
	MissingChunk(ID string)
	InvalidCount(Table string, Count uint32)
	InvalidAtomLength(Index int)
	TrailingData(Table string)
	TableShape(Table string)
	AtomOutOfRange(Index uint32, Count int)
	InvalidCodeHeader()
	UnsupportedInstructionSet(Found uint32, Supported uint32)
	UnsupportedOpcode(Required uint32, Supported byte)
	UnknownOpcode(Number byte, Offset int)
	MalformedCode(Detail string)
	InstructionOperandFailure(Opcode string, Index int, Offset int, Cause Failure)
	DecodeLimit(Name string, Limit int)
}

func (failure Failure) Error() string {
	match failure {
	case ReadFailure(path, cause):
		return fmt.Sprintf("%s: %v", path, cause)
	case Truncated(part):
		return "beam: truncated " + part
	case ModuleTooLarge(actual, limit):
		return fmt.Sprintf("beam: module is %d bytes; limit is %d", actual, limit)
	case InvalidMagic():
		return "beam: expected FOR1/BEAM header"
	case SizeMismatch(declared, actual):
		return fmt.Sprintf("beam: declared size %d differs from file size %d", declared, actual)
	case ChunkOutOfBounds(id):
		return fmt.Sprintf("beam: chunk %q exceeds module bounds", id)
	case DuplicateChunk(id):
		return fmt.Sprintf("beam: duplicate chunk %q", id)
	case InvalidPadding(id):
		return fmt.Sprintf("beam: invalid padding after chunk %q", id)
	case MissingChunk(id):
		return "beam: missing " + id + " chunk"
	case InvalidCount(table, count):
		return fmt.Sprintf("beam: unreasonable %s count %d", table, count)
	case InvalidAtomLength(index):
		return fmt.Sprintf("beam: invalid compact length for atom %d", index)
	case TrailingData(table):
		return "beam: trailing " + table + " data"
	case TableShape(table):
		return "beam: " + table + " length does not match row count"
	case AtomOutOfRange(index, count):
		return fmt.Sprintf("beam: atom index %d is outside 1..%d", index, count)
	case InvalidCodeHeader():
		return "beam: invalid Code sub-header size"
	case UnsupportedInstructionSet(found, supported):
		return fmt.Sprintf("beam: instruction set %d is not supported format %d", found, supported)
	case UnsupportedOpcode(required, supported):
		return fmt.Sprintf("beam: module requires opcode %d; %s supports through %d", required, OpcodeSourceVersion, supported)
	case UnknownOpcode(number, offset):
		return fmt.Sprintf("beam: unknown opcode %d at byte %d", number, offset)
	case MalformedCode(detail):
		return "beam: " + detail
	case InstructionOperandFailure(opcode, index, offset, cause):
		return fmt.Sprintf("beam: %s operand %d at byte %d: %v", opcode, index, offset, cause)
	case DecodeLimit(name, limit):
		return fmt.Sprintf("beam: %s limit %d exceeded", name, limit)
	}
}

// ReadFileCapability makes filesystem effects explicit at module-load sites.
//goplus:derive off
type ReadFileCapability enum {
	OperatingSystemFiles()
	CustomFileReader(Read func(string) ([]byte, error))
}

type Chunk struct {
	ID     string `json:"id"`
	Offset int    `json:"offset"`
	Size   int    `json:"size"`
	Data   []byte `json:"-"`
}

type CodeHeader struct {
	SubSize        uint32 `json:"sub_size"`
	InstructionSet uint32 `json:"instruction_set"`
	OpcodeMax      uint32 `json:"opcode_max"`
	LabelCount     uint32 `json:"label_count"`
	FunctionCount  uint32 `json:"function_count"`
}

type Import struct {
	Module   string `json:"module"`
	Function string `json:"function"`
	Arity    uint32 `json:"arity"`
}

type Export struct {
	Function string `json:"function"`
	Arity    uint32 `json:"arity"`
	Label    uint32 `json:"label"`
}

type Module struct {
	Path    string     `json:"path,omitempty"`
	Name    string     `json:"name"`
	Size    int        `json:"size"`
	Digest  string     `json:"digest"`
	Chunks  []Chunk    `json:"chunks"`
	Atoms   []string   `json:"atoms"`
	Imports []Import   `json:"imports"`
	Exports []Export   `json:"exports"`
	Code    CodeHeader `json:"code"`
	byID    map[string]int
}

func Load(
	capability ReadFileCapability,
	path string,
) result.Result[*Module, Failure] {
	match readFile(capability, path) {
	case result.Err(failure):
		return result.Err[*Module, Failure](failure)
	case result.Ok(data):
		match Parse(data) {
		case result.Err(failure):
			return result.Err[*Module, Failure](failure)
		case result.Ok(module):
			module.Path = path
			return result.Ok[*Module, Failure](module)
		}
	}
}

func readFile(
	capability ReadFileCapability,
	path string,
) result.Result[[]byte, Failure] {
	var readResult result.Result[[]byte, error]
	match capability {
	case OperatingSystemFiles():
		readResult = result.Of(os.ReadFile(path))
	case CustomFileReader(read):
		if read == nil {
			return result.Err[[]byte, Failure](ReadFailure(path, fmt.Errorf("nil file reader")))
		}
		readResult = result.Of(read(path))
	}
	match readResult {
	case result.Ok(data):
		return result.Ok[[]byte, Failure](data)
	case result.Err(cause):
		return result.Err[[]byte, Failure](ReadFailure(path, cause))
	}
}

func Parse(data []byte) result.Result[*Module, Failure] {
	if len(data) < 12 {
		return result.Err[*Module, Failure](Truncated("IFF header"))
	}
	if len(data) > maxModuleSize {
		return result.Err[*Module, Failure](ModuleTooLarge(len(data), maxModuleSize))
	}
	if string(data[:4]) != formMagic || string(data[8:12]) != beamMagic {
		return result.Err[*Module, Failure](InvalidMagic())
	}
	declared := uint64(binary.BigEndian.Uint32(data[4:8])) + 8
	if declared != uint64(len(data)) {
		return result.Err[*Module, Failure](SizeMismatch(declared, len(data)))
	}
	module := &Module{Size: len(data), byID: map[string]int{}}
	for offset := 12; offset < len(data); {
		if len(data)-offset < 8 {
			return result.Err[*Module, Failure](Truncated("chunk header"))
		}
		id := string(data[offset : offset+4])
		size := int(binary.BigEndian.Uint32(data[offset+4 : offset+8]))
		start := offset + 8
		if size < 0 || start > len(data) || size > len(data)-start {
			return result.Err[*Module, Failure](ChunkOutOfBounds(id))
		}
		_, duplicate := module.byID[id]
		if duplicate {
			return result.Err[*Module, Failure](DuplicateChunk(id))
		}
		body := append([]byte(nil), data[start:start+size]...)
		module.byID[id] = len(module.Chunks)
		module.Chunks = append(module.Chunks, Chunk{
			ID: id, Offset: offset, Size: size, Data: body,
		})
		padded := (size + 3) & ^3
		if padded > len(data)-start {
			return result.Err[*Module, Failure](InvalidPadding(id))
		}
		offset = start + padded
	}
	match module.parseAtoms() {
	case result.Err(failure):
		return result.Err[*Module, Failure](failure)
	case result.Ok(atoms):
		module.Atoms = atoms
		if len(atoms) == 0 || atoms[0] == "" {
			return result.Err[*Module, Failure](MissingChunk("non-empty atom table"))
		}
		module.Name = atoms[0]
	}
	match module.parseCode() {
	case result.Err(failure):
		return result.Err[*Module, Failure](failure)
	case result.Ok(code):
		module.Code = code
	}
	match module.parseImports() {
	case result.Err(failure):
		return result.Err[*Module, Failure](failure)
	case result.Ok(imports):
		module.Imports = imports
	}
	match module.parseExports() {
	case result.Err(failure):
		return result.Err[*Module, Failure](failure)
	case result.Ok(exports):
		module.Exports = exports
	}
	module.Digest = module.semanticDigest()
	return result.Ok[*Module, Failure](module)
}

func (module *Module) Chunk(id string) option.Option[[]byte] {
	index, present := module.byID[id]
	match option.Of(index, present) {
	case option.None:
		return option.None[[]byte]
	case option.Some(found):
		return option.Some(append([]byte(nil), module.Chunks[found].Data...))
	}
}

func (module *Module) parseAtoms() result.Result[[]string, Failure] {
	match module.chunkEither("AtU8", "Atom") {
	case option.None:
		return result.Err[[]string, Failure](MissingChunk("AtU8/Atom"))
	case option.Some(data):
		if len(data) < 4 {
			return result.Err[[]string, Failure](Truncated("atom count"))
		}
		rawCount := int32(binary.BigEndian.Uint32(data[:4]))
		compactLengths := rawCount < 0
		count64 := int64(rawCount)
		if compactLengths {
			count64 = -count64
		}
		if count64 < 0 || count64 > 1<<24 {
			return result.Err[[]string, Failure](
				InvalidCount("atom", binary.BigEndian.Uint32(data[:4])),
			)
		}
		count := int(count64)
		atoms := make([]string, 0, count)
		at := 4
		for index := 0; index < count; index++ {
			if at >= len(data) {
				return result.Err[[]string, Failure](Truncated(fmt.Sprintf("atom %d", index+1)))
			}
			length := 0
			if compactLengths {
				match decodeCompactNumber(data, &at, DefaultCodeDecodeLimits(), 0) {
				case result.Err(_):
					return result.Err[[]string, Failure](InvalidAtomLength(index + 1))
				case result.Ok(compact):
					if compact.tag != 0 || !compact.value.IsUint64() ||
						compact.value.Uint64() > uint64(len(data)) {
						return result.Err[[]string, Failure](InvalidAtomLength(index + 1))
					}
					length = int(compact.value.Uint64())
				}
			} else {
				length = int(data[at])
				at++
			}
			if length > len(data)-at {
				return result.Err[[]string, Failure](Truncated(fmt.Sprintf("atom %d body", index+1)))
			}
			atoms = append(atoms, string(data[at:at+length]))
			at += length
		}
		if at != len(data) {
			return result.Err[[]string, Failure](TrailingData("atom"))
		}
		return result.Ok[[]string, Failure](atoms)
	}
}

func (module *Module) parseCode() result.Result[CodeHeader, Failure] {
	match module.Chunk("Code") {
	case option.None:
		return result.Err[CodeHeader, Failure](MissingChunk("Code"))
	case option.Some(data):
		if len(data) < 20 {
			return result.Err[CodeHeader, Failure](Truncated("Code header"))
		}
		header := CodeHeader{
			SubSize:        binary.BigEndian.Uint32(data[0:4]),
			InstructionSet: binary.BigEndian.Uint32(data[4:8]),
			OpcodeMax:      binary.BigEndian.Uint32(data[8:12]),
			LabelCount:     binary.BigEndian.Uint32(data[12:16]),
			FunctionCount:  binary.BigEndian.Uint32(data[16:20]),
		}
		if header.SubSize < 16 || uint64(header.SubSize)+4 > uint64(len(data)) {
			return result.Err[CodeHeader, Failure](InvalidCodeHeader())
		}
		return result.Ok[CodeHeader, Failure](header)
	}
}

func (module *Module) parseImports() result.Result[[]Import, Failure] {
	match module.Chunk("ImpT") {
	case option.None:
		return result.Ok[[]Import, Failure](nil)
	case option.Some(data):
		match tableRows("imports", data, 3) {
		case result.Err(failure):
			return result.Err[[]Import, Failure](failure)
		case result.Ok(rows):
			out := make([]Import, 0, len(rows))
			for _, row := range rows {
				var moduleName string
				match module.atom(row[0]) {
				case result.Err(failure):
					return result.Err[[]Import, Failure](failure)
				case result.Ok(atom):
					moduleName = atom
				}
				var functionName string
				match module.atom(row[1]) {
				case result.Err(failure):
					return result.Err[[]Import, Failure](failure)
				case result.Ok(atom):
					functionName = atom
				}
				out = append(out, Import{
					Module: moduleName, Function: functionName, Arity: row[2],
				})
			}
			return result.Ok[[]Import, Failure](out)
		}
	}
}

func (module *Module) parseExports() result.Result[[]Export, Failure] {
	match module.Chunk("ExpT") {
	case option.None:
		return result.Ok[[]Export, Failure](nil)
	case option.Some(data):
		match tableRows("exports", data, 3) {
		case result.Err(failure):
			return result.Err[[]Export, Failure](failure)
		case result.Ok(rows):
			out := make([]Export, 0, len(rows))
			for _, row := range rows {
				match module.atom(row[0]) {
				case result.Err(failure):
					return result.Err[[]Export, Failure](failure)
				case result.Ok(function):
					out = append(out, Export{
						Function: function, Arity: row[1], Label: row[2],
					})
				}
			}
			return result.Ok[[]Export, Failure](out)
		}
	}
}

func tableRows(
	table string,
	data []byte,
	width int,
) result.Result[[][]uint32, Failure] {
	if len(data) < 4 {
		return result.Err[[][]uint32, Failure](Truncated(table + " row count"))
	}
	count := binary.BigEndian.Uint32(data[:4])
	required := uint64(4) + uint64(count)*uint64(width)*4
	if required != uint64(len(data)) {
		return result.Err[[][]uint32, Failure](TableShape(table))
	}
	rows := make([][]uint32, int(count))
	at := 4
	for index := range rows {
		rows[index] = make([]uint32, width)
		for column := range rows[index] {
			rows[index][column] = binary.BigEndian.Uint32(data[at : at+4])
			at += 4
		}
	}
	return result.Ok[[][]uint32, Failure](rows)
}

func (module *Module) atom(index uint32) result.Result[string, Failure] {
	if index == 0 || uint64(index) > uint64(len(module.Atoms)) {
		return result.Err[string, Failure](AtomOutOfRange(index, len(module.Atoms)))
	}
	return result.Ok[string, Failure](module.Atoms[index-1])
}

func (module *Module) chunkEither(ids ...string) option.Option[[]byte] {
	for _, id := range ids {
		match module.Chunk(id) {
		case option.Some(data):
			return option.Some(data)
		case option.None:
		}
	}
	return option.None[[]byte]
}

func (module *Module) semanticDigest() string {
	hash := sha256.New()
	var size [4]byte
	for _, chunk := range module.Chunks {
		if chunk.ID == "GpPr" {
			continue
		}
		hash.Write([]byte(chunk.ID))
		binary.BigEndian.PutUint32(size[:], uint32(len(chunk.Data)))
		hash.Write(size[:])
		hash.Write(chunk.Data)
	}
	return hex.EncodeToString(hash.Sum(nil))
}
