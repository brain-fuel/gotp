package vm

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

func TestSmallIntegerRoundTripLaw(t *testing.T) {
	law := func(raw int64) bool {
		value := raw >> 3
		match SmallInteger(value) {
		case result.Err(_):
			return false
		case result.Ok(word):
			match word.SmallInteger() {
			case option.Some(decoded):
				return decoded == value
			case option.None:
				return false
			}
		}
	}
	match result.Of(true, quick.Check(law, nil)) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}

func TestProcessHeapStoresImmediateWord(t *testing.T) {
	match NewProcessHeap(4096) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(heap):
		defer heap.Close()
		match heap.Allocate(2) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(reference):
			match SmallInteger(-42) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(word):
				match heap.Store(reference, 1, word) {
				case result.Err(failure):
					t.Fatal(failure.Error())
				case result.Ok(HeapMutated):
				}
				match heap.Load(reference, 1) {
				case result.Err(failure):
					t.Fatal(failure.Error())
				case result.Ok(loaded):
					match loaded.SmallInteger() {
					case option.Some(value):
						if value != -42 {
							t.Fatalf("loaded = %d", value)
						}
					case option.None:
						t.Fatal("loaded word is not a small integer")
					}
				}
				match heap.Reset() {
				case result.Err(failure):
					t.Fatal(failure.Error())
				case result.Ok(HeapMutated):
				}
				match heap.Load(reference, 1) {
				case result.Err(_):
				case result.Ok(_):
					t.Fatal("expired heap reference remained readable")
				}
			}
		}
	}
}
