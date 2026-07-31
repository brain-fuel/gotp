package beam

import (
	"testing"

	"goforge.dev/goplus/std/result"
)

// assayxport:law gotp.beam.function-table-laws
func TestPinnedOTPFunctionTable(t *testing.T) {
	var read ReadFileCapability = OperatingSystemFiles{}
	match Load(read, "testdata/otp-29.0.4/lists.beam") {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(module):
		match DecodeModuleFunctions(module, FunctionDecodeLimits{}) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(functions):
			function, present := functions[0]
			if !present {
				t.Fatal("FunT function 0 is missing")
			}
			if function.Function != "thing_to_list" || function.Arity != 1 || function.Label != 220 || function.Free != 0 {
				t.Fatalf("FunT function 0 = %#v", function)
			}
		}
	}
}
