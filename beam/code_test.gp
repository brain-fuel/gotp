package beam

import (
	"encoding/binary"
	"math/big"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

func TestOpcodeSourceIsPinned(t *testing.T) {
	if OpcodeSourceVersion != "OTP-29.0.4" {
		t.Fatalf("source version = %q", OpcodeSourceVersion)
	}
	if OpcodeSourceSHA256 != "79cf0ee1df79f0b50f5055338cbf4ee238115c12db862de89f7fca0c5309b017" {
		t.Fatalf("source digest = %q", OpcodeSourceSHA256)
	}
	match LookupOpcode(191) {
	case option.None:
		t.Fatal("opcode 191 is missing")
	case option.Some(opcode):
		if opcode.Name != "get_record_field" || opcode.Arity != 5 {
			t.Fatalf("opcode 191 = %#v", opcode)
		}
	}
}

func TestDecodeCodeChunk(t *testing.T) {
	code := []byte{
		1, compactSmall(0, 1),
		2, compactSmall(2, 1), compactSmall(2, 2), compactSmall(0, 0),
		64, compactSmall(1, 7), compactSmall(3, 0),
		19,
		3,
	}
	chunk := make([]byte, 20+len(code))
	binary.BigEndian.PutUint32(chunk[0:4], 16)
	binary.BigEndian.PutUint32(chunk[4:8], OpcodeFormatNumber)
	binary.BigEndian.PutUint32(chunk[8:12], 191)
	binary.BigEndian.PutUint32(chunk[12:16], 1)
	binary.BigEndian.PutUint32(chunk[16:20], 1)
	copy(chunk[20:], code)

	match DecodeCodeChunk(chunk, CodeDecodeLimits{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(decoded):
		if decoded.Info.LabelCount != 1 || decoded.Info.FunctionCount != 1 {
			t.Fatalf("info = %#v", decoded.Info)
		}
		want := []string{"label", "func_info", "move", "return", "int_code_end"}
		if len(decoded.Instructions) != len(want) {
			t.Fatalf("decoded %d instructions, want %d", len(decoded.Instructions), len(want))
		}
		for index, name := range want {
			if decoded.Instructions[index].Opcode.Name != name {
				t.Fatalf("instruction %d = %s, want %s", index, decoded.Instructions[index].Opcode.Name, name)
			}
		}
		match decoded.Instructions[2].Operands[0].Int64() {
		case option.None:
			t.Fatal("move source is not int64")
		case option.Some(value):
			if value != 7 {
				t.Fatalf("move source = %d", value)
			}
		}
	}
}

func TestDecodeCompactForms(t *testing.T) {
	limits := DefaultCodeDecodeLimits()
	position := 0
	match decodeOperand([]byte{0x28, 0x23}, &position, limits, 0) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(operand):
		match operand {
		case UnsignedOperand(value):
			if value.Uint64() != 0x123 {
				t.Fatalf("two-byte value = %v", value)
			}
		case _:
			t.Fatal("two-byte value has wrong operand variant")
		}
	}

	position = 0
	match decodeOperand([]byte{0x19, 0xff, 0xff}, &position, limits, 0) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(operand):
		match operand {
		case IntegerOperand(value):
			if value.Cmp(big.NewInt(-1)) != 0 {
				t.Fatalf("signed value = %v", value)
			}
		case _:
			t.Fatal("signed value has wrong operand variant")
		}
	}

	position = 0
	match decodeOperand([]byte{0x47, 0x20}, &position, limits, 0) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(operand):
		match operand {
		case LiteralOperand(value):
			if value.Uint64() != 2 {
				t.Fatalf("literal = %v", value)
			}
		case _:
			t.Fatal("literal has wrong operand variant")
		}
	}
}

func TestDecodeRejectsMalformedOperands(t *testing.T) {
	if DecodeInstructions([]byte{255}, CodeDecodeLimits{}).IsOk() {
		t.Fatal("unknown opcode was accepted")
	}
	if DecodeInstructions([]byte{1, 0x67}, CodeDecodeLimits{}).IsOk() {
		t.Fatal("unknown extended operand was accepted")
	}
	if DecodeInstructions([]byte{1, 0x19, 0xff}, CodeDecodeLimits{}).IsOk() {
		t.Fatal("truncated compact integer was accepted")
	}
}

func TestDecodeInstructionsNeverPanics(t *testing.T) {
	config := &quick.Config{MaxCount: 2_000}
	law := func(data []byte) bool {
		_ = DecodeInstructions(data, CodeDecodeLimits{
			MaxInstructions: 64,
			MaxOperandDepth: 16,
			MaxListItems:    64,
			MaxIntegerBytes: 32,
		})
		return true
	}
	match result.Of(true, quick.Check(law, config)) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}

func compactSmall(tag byte, value byte) byte {
	return value<<4 | tag
}
