package etf

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
)

func TestDecodeTupleMapAndInteger(t *testing.T) {
	data := []byte{
		131, 104, 2,
		119, 2, 'o', 'k',
		116, 0, 0, 0, 1,
		119, 1, 'n',
		98, 0, 0, 0, 42,
	}
	match Decode(data, DefaultLimits()) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(value):
		match value {
		case RawTuple(elements):
			if len(elements) != 2 {
				t.Fatalf("tuple length = %d", len(elements))
			}
			match elements[1] {
			case RawMap(pairs):
				if len(pairs) != 1 {
					t.Fatalf("map length = %d", len(pairs))
				}
				match pairs[0].Value {
				case RawInteger(integer):
					if integer.Int64() != 42 {
						t.Fatalf("integer = %s", integer.String())
					}
				case _:
					t.Fatal("map value is not an integer")
				}
			case _:
				t.Fatal("second tuple element is not a map")
			}
		case _:
			t.Fatal("decoded value is not a tuple")
		}
	}
}

func TestSmallIntegerProperty(t *testing.T) {
	property := func(value uint8) bool {
		match Decode([]byte{131, 97, value}, DefaultLimits()) {
		case result.Ok(decoded):
			match decoded {
			case RawInteger(integer):
				return integer.Uint64() == uint64(value)
			case _:
				return false
			}
		case _:
			return false
		}
	}
	match result.Of(true, quick.Check(property, nil)) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}

func FuzzDecodeNeverPanics(f *testing.F) {
	f.Add([]byte{131, 97, 1})
	f.Add([]byte{131, 104, 0})
	f.Fuzz(func(t *testing.T, data []byte) {
		limits := DefaultLimits()
		limits.MaxBytes = 1 << 20
		Decode(data, limits)
	})
}
