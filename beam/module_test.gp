package beam

import (
	"encoding/binary"
	"testing"

	"goforge.dev/goplus/std/result"
)

func TestRejectsDeclaredSizeMismatch(t *testing.T) {
	match Parse([]byte("FOR1\x00\x00\x00\x05BEAM")) {
	case result.Ok(_):
		t.Fatal("accepted mismatched module size")
	case result.Err(failure):
		match failure {
		case SizeMismatch(_, _):
		case _:
			t.Fatalf("unexpected failure: %v", failure)
		}
	}
}

func TestParsesMinimalMetadata(t *testing.T) {
	atoms := tableAtoms("demo", "main")
	code := make([]byte, 20)
	binary.BigEndian.PutUint32(code[0:4], 16)
	binary.BigEndian.PutUint32(code[4:8], 0)
	binary.BigEndian.PutUint32(code[8:12], 1)
	binary.BigEndian.PutUint32(code[12:16], 1)
	binary.BigEndian.PutUint32(code[16:20], 1)
	exports := tableWords([]uint32{2, 0, 1})
	imports := tableWords()
	data := moduleBytes(
		chunk("AtU8", atoms),
		chunk("Code", code),
		chunk("ImpT", imports),
		chunk("ExpT", exports),
	)
	match Parse(data) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(module):
		if module.Name != "demo" ||
			len(module.Exports) != 1 ||
			module.Exports[0].Function != "main" {
			t.Fatalf("module = %#v", module)
		}
	}
}

func FuzzParseNeverPanics(f *testing.F) {
	f.Add([]byte("FOR1\x00\x00\x00\x04BEAM"))
	f.Fuzz(func(t *testing.T, data []byte) {
		_ = Parse(data)
	})
}

func chunk(id string, data []byte) []byte {
	out := make([]byte, 8+((len(data)+3)&^3))
	copy(out[:4], id)
	binary.BigEndian.PutUint32(out[4:8], uint32(len(data)))
	copy(out[8:], data)
	return out
}

func moduleBytes(chunks ...[]byte) []byte {
	size := 4
	for _, current := range chunks {
		size += len(current)
	}
	out := make([]byte, 8, 8+size)
	copy(out[:4], "FOR1")
	binary.BigEndian.PutUint32(out[4:8], uint32(size))
	out = append(out, []byte("BEAM")...)
	for _, current := range chunks {
		out = append(out, current...)
	}
	return out
}

func tableAtoms(values ...string) []byte {
	out := make([]byte, 4)
	binary.BigEndian.PutUint32(out, uint32(len(values)))
	for _, value := range values {
		out = append(out, byte(len(value)))
		out = append(out, value...)
	}
	return out
}

func tableWords(rows ...[]uint32) []byte {
	out := make([]byte, 4)
	binary.BigEndian.PutUint32(out, uint32(len(rows)))
	for _, row := range rows {
		for _, value := range row {
			var raw [4]byte
			binary.BigEndian.PutUint32(raw[:], value)
			out = append(out, raw[:]...)
		}
	}
	return out
}
