package beam

import (
	"encoding/binary"
	"fmt"
	"math/big"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

type Opcode struct {
	Number byte
	Name   string
	Arity  int
}

func LookupOpcode(number byte) option.Option[Opcode] {
	if number == 0 || int(number) >= len(generatedOpcodeTable) {
		return option.None[Opcode]
	}
	spec := generatedOpcodeTable[number]
	if spec.name == "" {
		return option.None[Opcode]
	}
	return option.Some(Opcode{
		Number: number,
		Name:   spec.name,
		Arity:  int(spec.arity),
	})
}

type OperandKind enum {
	UnsignedKind()
	IntegerKind()
	AtomKind()
	XRegisterKind()
	YRegisterKind()
	LabelKind()
	CharacterKind()
	ListKind()
	FloatRegisterKind()
	AllocationListKind()
	LiteralKind()
	TypedRegisterKind()
}

type Allocation struct {
	Kind  uint64
	Count uint64
}

//goplus:derive off
type Operand enum {
	UnsignedOperand(Value *big.Int)
	IntegerOperand(Value *big.Int)
	AtomOperand(Index *big.Int)
	XRegisterOperand(Index *big.Int)
	YRegisterOperand(Index *big.Int)
	LabelOperand(Index *big.Int)
	CharacterOperand(Value *big.Int)
	ListOperand(Items []Operand)
	FloatRegisterOperand(Index *big.Int)
	AllocationListOperand(Allocations []Allocation)
	LiteralOperand(Index *big.Int)
	TypedRegisterOperand(Register Operand, TypeIndex uint64)
}

func (operand Operand) Kind() OperandKind {
	match operand {
	case UnsignedOperand(_):
		return UnsignedKind()
	case IntegerOperand(_):
		return IntegerKind()
	case AtomOperand(_):
		return AtomKind()
	case XRegisterOperand(_):
		return XRegisterKind()
	case YRegisterOperand(_):
		return YRegisterKind()
	case LabelOperand(_):
		return LabelKind()
	case CharacterOperand(_):
		return CharacterKind()
	case ListOperand(_):
		return ListKind()
	case FloatRegisterOperand(_):
		return FloatRegisterKind()
	case AllocationListOperand(_):
		return AllocationListKind()
	case LiteralOperand(_):
		return LiteralKind()
	case TypedRegisterOperand(_, _):
		return TypedRegisterKind()
	}
}

func (operand Operand) BigInteger() option.Option[*big.Int] {
	match operand {
	case UnsignedOperand(value):
		return option.Some(new(big.Int).Set(value))
	case IntegerOperand(value):
		return option.Some(new(big.Int).Set(value))
	case AtomOperand(value):
		return option.Some(new(big.Int).Set(value))
	case XRegisterOperand(value):
		return option.Some(new(big.Int).Set(value))
	case YRegisterOperand(value):
		return option.Some(new(big.Int).Set(value))
	case LabelOperand(value):
		return option.Some(new(big.Int).Set(value))
	case CharacterOperand(value):
		return option.Some(new(big.Int).Set(value))
	case FloatRegisterOperand(value):
		return option.Some(new(big.Int).Set(value))
	case LiteralOperand(value):
		return option.Some(new(big.Int).Set(value))
	case _:
		return option.None[*big.Int]
	}
}

func (operand Operand) Uint64() option.Option[uint64] {
	match operand.BigInteger() {
	case option.None:
		return option.None[uint64]
	case option.Some(value):
		if value.IsUint64() {
			return option.Some(value.Uint64())
		}
		return option.None[uint64]
	}
}

func (operand Operand) Int64() option.Option[int64] {
	match operand.BigInteger() {
	case option.None:
		return option.None[int64]
	case option.Some(value):
		if value.IsInt64() {
			return option.Some(value.Int64())
		}
		return option.None[int64]
	}
}

type Instruction struct {
	Offset   int
	Opcode   Opcode
	Operands []Operand
}

type CodeInfo struct {
	HeaderSize     uint32
	InstructionSet uint32
	OpcodeMax      uint32
	LabelCount     uint32
	FunctionCount  uint32
}

type DecodedCode struct {
	Info         CodeInfo
	Instructions []Instruction
}

type CodeDecodeLimits struct {
	MaxInstructions int
	MaxOperandDepth int
	MaxListItems    int
	MaxIntegerBytes int
}

func DefaultCodeDecodeLimits() CodeDecodeLimits {
	return CodeDecodeLimits{
		MaxInstructions: 1_000_000,
		MaxOperandDepth: 64,
		MaxListItems:    1_000_000,
		MaxIntegerBytes: 256,
	}
}

func (limits CodeDecodeLimits) normalized() CodeDecodeLimits {
	defaults := DefaultCodeDecodeLimits()
	if limits.MaxInstructions <= 0 {
		limits.MaxInstructions = defaults.MaxInstructions
	}
	if limits.MaxOperandDepth <= 0 {
		limits.MaxOperandDepth = defaults.MaxOperandDepth
	}
	if limits.MaxListItems <= 0 {
		limits.MaxListItems = defaults.MaxListItems
	}
	if limits.MaxIntegerBytes <= 0 {
		limits.MaxIntegerBytes = defaults.MaxIntegerBytes
	}
	return limits
}

func DecodeCodeChunk(
	chunk []byte,
	limits CodeDecodeLimits,
) result.Result[DecodedCode, Failure] {
	if len(chunk) < 20 {
		return result.Err[DecodedCode, Failure](Truncated("Code chunk"))
	}
	info := CodeInfo{
		HeaderSize:     binary.BigEndian.Uint32(chunk[0:4]),
		InstructionSet: binary.BigEndian.Uint32(chunk[4:8]),
		OpcodeMax:      binary.BigEndian.Uint32(chunk[8:12]),
		LabelCount:     binary.BigEndian.Uint32(chunk[12:16]),
		FunctionCount:  binary.BigEndian.Uint32(chunk[16:20]),
	}
	if info.HeaderSize < 16 {
		return result.Err[DecodedCode, Failure](InvalidCodeHeader())
	}
	codeOffset64 := uint64(info.HeaderSize) + 4
	if codeOffset64 > uint64(len(chunk)) {
		return result.Err[DecodedCode, Failure](InvalidCodeHeader())
	}
	if info.InstructionSet != OpcodeFormatNumber {
		return result.Err[DecodedCode, Failure](
			UnsupportedInstructionSet(info.InstructionSet, OpcodeFormatNumber),
		)
	}
	if info.OpcodeMax > uint32(generatedMaxOpcode) {
		return result.Err[DecodedCode, Failure](
			UnsupportedOpcode(info.OpcodeMax, generatedMaxOpcode),
		)
	}
	match DecodeInstructions(chunk[int(codeOffset64):], limits) {
	case result.Err(failure):
		return result.Err[DecodedCode, Failure](failure)
	case result.Ok(instructions):
		return result.Ok[DecodedCode, Failure](DecodedCode{
			Info: info, Instructions: instructions,
		})
	}
}

func DecodeInstructions(
	code []byte,
	limits CodeDecodeLimits,
) result.Result[[]Instruction, Failure] {
	limits = limits.normalized()
	instructions := make([]Instruction, 0)
	position := 0
	for position < len(code) {
		if len(instructions) >= limits.MaxInstructions {
			return result.Err[[]Instruction, Failure](
				DecodeLimit("instruction", limits.MaxInstructions),
			)
		}
		offset := position
		number := code[position]
		position++
		var opcode Opcode
		match LookupOpcode(number) {
		case option.None:
			return result.Err[[]Instruction, Failure](UnknownOpcode(number, offset))
		case option.Some(found):
			opcode = found
		}
		operands := make([]Operand, opcode.Arity)
		for index := range operands {
			match decodeOperand(code, &position, limits, 0) {
			case result.Err(failure):
				return result.Err[[]Instruction, Failure](
					InstructionOperandFailure(opcode.Name, index, position, failure),
				)
			case result.Ok(operand):
				operands[index] = operand
			}
		}
		instructions = append(instructions, Instruction{
			Offset: offset, Opcode: opcode, Operands: operands,
		})
	}
	return result.Ok[[]Instruction, Failure](instructions)
}

type compactNumber struct {
	tag   byte
	value *big.Int
}

func decodeOperand(
	data []byte,
	position *int,
	limits CodeDecodeLimits,
	depth int,
) result.Result[Operand, Failure] {
	if depth >= limits.MaxOperandDepth {
		return result.Err[Operand, Failure](
			DecodeLimit("operand depth", limits.MaxOperandDepth),
		)
	}
	match decodeCompactNumber(data, position, limits, depth) {
	case result.Err(failure):
		return result.Err[Operand, Failure](failure)
	case result.Ok(compact):
		switch compact.tag {
		case 0:
			return result.Ok[Operand, Failure](UnsignedOperand(compact.value))
		case 1:
			return result.Ok[Operand, Failure](IntegerOperand(compact.value))
		case 2:
			return result.Ok[Operand, Failure](AtomOperand(compact.value))
		case 3:
			return result.Ok[Operand, Failure](XRegisterOperand(compact.value))
		case 4:
			return result.Ok[Operand, Failure](YRegisterOperand(compact.value))
		case 5:
			return result.Ok[Operand, Failure](LabelOperand(compact.value))
		case 6:
			return result.Ok[Operand, Failure](CharacterOperand(compact.value))
		case 7:
			return decodeExtendedOperand(data, position, limits, depth+1, compact.value)
		default:
			return result.Err[Operand, Failure](MalformedCode("invalid compact tag"))
		}
	}
}

func decodeExtendedOperand(
	data []byte,
	position *int,
	limits CodeDecodeLimits,
	depth int,
	extension *big.Int,
) result.Result[Operand, Failure] {
	if extension == nil || !extension.IsUint64() {
		return result.Err[Operand, Failure](
			MalformedCode("extended operand tag is not unsigned"),
		)
	}
	switch extension.Uint64() {
	case 1:
		match decodeUnsigned(data, position, limits, depth) {
		case result.Err(failure):
			return result.Err[Operand, Failure](failure)
		case result.Ok(count):
			if count > uint64(limits.MaxListItems) {
				return result.Err[Operand, Failure](
					DecodeLimit("list item", limits.MaxListItems),
				)
			}
			items := make([]Operand, int(count))
			for index := range items {
				match decodeOperand(data, position, limits, depth) {
				case result.Err(failure):
					return result.Err[Operand, Failure](failure)
				case result.Ok(item):
					items[index] = item
				}
			}
			return result.Ok[Operand, Failure](ListOperand(items))
		}
	case 2:
		match decodeUnsigned(data, position, limits, depth) {
		case result.Err(failure):
			return result.Err[Operand, Failure](failure)
		case result.Ok(index):
			return result.Ok[Operand, Failure](
				FloatRegisterOperand(new(big.Int).SetUint64(index)),
			)
		}
	case 3:
		match decodeUnsigned(data, position, limits, depth) {
		case result.Err(failure):
			return result.Err[Operand, Failure](failure)
		case result.Ok(count):
			if count > uint64(limits.MaxListItems) {
				return result.Err[Operand, Failure](
					DecodeLimit("allocation", limits.MaxListItems),
				)
			}
			allocations := make([]Allocation, int(count))
			for index := range allocations {
				var kind uint64
				match decodeUnsigned(data, position, limits, depth) {
				case result.Err(failure):
					return result.Err[Operand, Failure](failure)
				case result.Ok(value):
					kind = value
				}
				var count uint64
				match decodeUnsigned(data, position, limits, depth) {
				case result.Err(failure):
					return result.Err[Operand, Failure](failure)
				case result.Ok(value):
					count = value
				}
				if kind > 2 {
					return result.Err[Operand, Failure](
						MalformedCode(fmt.Sprintf("unknown allocation kind %d", kind)),
					)
				}
				allocations[index] = Allocation{Kind: kind, Count: count}
			}
			return result.Ok[Operand, Failure](AllocationListOperand(allocations))
		}
	case 4:
		match decodeUnsigned(data, position, limits, depth) {
		case result.Err(failure):
			return result.Err[Operand, Failure](failure)
		case result.Ok(index):
			return result.Ok[Operand, Failure](
				LiteralOperand(new(big.Int).SetUint64(index)),
			)
		}
	case 5:
		var register Operand
		match decodeOperand(data, position, limits, depth) {
		case result.Err(failure):
			return result.Err[Operand, Failure](failure)
		case result.Ok(found):
			register = found
		}
		match register {
		case XRegisterOperand(_):
		case YRegisterOperand(_):
		case _:
			return result.Err[Operand, Failure](
				MalformedCode("typed operand does not contain a register"),
			)
		}
		match decodeUnsigned(data, position, limits, depth) {
		case result.Err(failure):
			return result.Err[Operand, Failure](failure)
		case result.Ok(typeIndex):
			return result.Ok[Operand, Failure](
				TypedRegisterOperand(register, typeIndex),
			)
		}
	default:
		return result.Err[Operand, Failure](
			MalformedCode("unknown extended operand tag " + extension.String()),
		)
	}
}

func decodeUnsigned(
	data []byte,
	position *int,
	limits CodeDecodeLimits,
	depth int,
) result.Result[uint64, Failure] {
	match decodeCompactNumber(data, position, limits, depth) {
	case result.Err(failure):
		return result.Err[uint64, Failure](failure)
	case result.Ok(compact):
		if compact.tag != 0 || compact.value == nil || !compact.value.IsUint64() {
			return result.Err[uint64, Failure](
				MalformedCode("expected unsigned compact value"),
			)
		}
		return result.Ok[uint64, Failure](compact.value.Uint64())
	}
}

func decodeCompactNumber(
	data []byte,
	position *int,
	limits CodeDecodeLimits,
	depth int,
) result.Result[compactNumber, Failure] {
	if *position >= len(data) {
		return result.Err[compactNumber, Failure](Truncated("compact value"))
	}
	first := data[*position]
	*position++
	tag := first & 0x07
	if first&0x08 == 0 {
		return result.Ok[compactNumber, Failure](compactNumber{
			tag: tag, value: new(big.Int).SetUint64(uint64(first >> 4)),
		})
	}
	if first&0x10 == 0 {
		if *position >= len(data) {
			return result.Err[compactNumber, Failure](Truncated("two-byte compact value"))
		}
		value := uint64(first&0xe0)<<3 | uint64(data[*position])
		*position++
		return result.Ok[compactNumber, Failure](compactNumber{
			tag: tag, value: new(big.Int).SetUint64(value),
		})
	}
	lengthCode := int(first >> 5)
	length := lengthCode + 2
	if lengthCode == 7 {
		if depth >= limits.MaxOperandDepth {
			return result.Err[compactNumber, Failure](
				DecodeLimit("compact length depth", limits.MaxOperandDepth),
			)
		}
		match decodeUnsigned(data, position, limits, depth+1) {
		case result.Err(failure):
			return result.Err[compactNumber, Failure](failure)
		case result.Ok(extra):
			if extra > uint64(limits.MaxIntegerBytes) {
				return result.Err[compactNumber, Failure](
					DecodeLimit("compact integer byte", limits.MaxIntegerBytes),
				)
			}
			length = int(extra) + 9
		}
	}
	if length > limits.MaxIntegerBytes {
		return result.Err[compactNumber, Failure](
			DecodeLimit("compact integer byte", limits.MaxIntegerBytes),
		)
	}
	if length > len(data)-*position {
		return result.Err[compactNumber, Failure](Truncated("compact integer"))
	}
	raw := data[*position : *position+length]
	*position += length
	value := new(big.Int).SetBytes(raw)
	if tag == 1 && raw[0]&0x80 != 0 {
		modulus := new(big.Int).Lsh(big.NewInt(1), uint(length*8))
		value.Sub(value, modulus)
	}
	return result.Ok[compactNumber, Failure](compactNumber{tag: tag, value: value})
}
