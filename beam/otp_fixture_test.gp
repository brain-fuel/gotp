package beam

import (
	"os"
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

func TestDecodePinnedOTPListsModule(t *testing.T) {
	var raw []byte
	match result.Of(os.ReadFile("testdata/otp-29.0.4/lists.beam")) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(data):
		raw = data
	}
	var module *Module
	match Parse(raw) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(parsed):
		module = parsed
	}
	var code []byte
	match module.Chunk("Code") {
	case option.None:
		t.Fatal("fixture has no Code chunk")
	case option.Some(data):
		code = data
	}
	match DecodeCodeChunk(code, CodeDecodeLimits{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(decoded):
		if decoded.Info.InstructionSet != OpcodeFormatNumber {
			t.Fatalf("instruction set = %d", decoded.Info.InstructionSet)
		}
		if len(decoded.Instructions) < 100 {
			t.Fatalf("decoded only %d instructions", len(decoded.Instructions))
		}
		if decoded.Instructions[len(decoded.Instructions)-1].Opcode.Name != "int_code_end" {
			t.Fatalf("last instruction = %s", decoded.Instructions[len(decoded.Instructions)-1].Opcode.Name)
		}
	}
}
