package etf

import (
	"bytes"
	"encoding/binary"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func funCodec(t *testing.T) CanonicalCodec {
	match NewStaticNodeTable(map[uint32]string{1: "gotp@local"}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(nodes):
		return CanonicalCodec{Nodes: nodes}
	}
	panic("unreachable")
}

func roundTripFun(t *testing.T, codec CanonicalCodec, value term.Term, tag byte) {
	match codec.Encode(value) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(encoded):
		if len(encoded) < 2 || encoded[1] != tag {
			t.Fatalf("fun tag = %v", encoded)
		}
		if tag == canonicalNewFun {
			size := binary.BigEndian.Uint32(encoded[2:6])
			if int(size) != len(encoded) - 2 {
				t.Fatalf("NEW_FUN_EXT size = %d, bytes = %d", size, len(encoded))
			}
		}
		match codec.Decode(encoded) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(decoded):
			if !term.Equal(decoded, value) {
				t.Fatalf("fun round trip = %#v, want %#v", decoded, value)
			}
		}
	}
}

// assayxport:law gotp.etf.fun-codec-laws
func TestETFFunctionFormsRoundTrip(t *testing.T) {
	codec := funCodec(t)
	creator := term.PID{Node: 1, Number: 7, Serial: 2, Creation: 3}
	old := term.Function(term.Fun{
		Form: term.OldClosure(),
		Module: "demo",
		Index: 4,
		Unique: 5,
		Creator: creator,
		Environment: []term.Term{term.Integer(6), term.MustAtom("captured")},
	})
	roundTripFun(t, codec, old, canonicalOldFun)
	digest := [16]byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}
	modern := term.Function(term.Fun{
		Form: term.NewClosure(digest, 9, 4),
		Module: "demo",
		Arity: 2,
		Unique: 5,
		Creator: creator,
		Environment: []term.Term{term.List(term.Integer(8))},
	})
	roundTripFun(t, codec, modern, canonicalNewFun)
	exported := term.Function(term.Fun{
		Form: term.ExportedFunction(),
		Module: "lists",
		Function: "reverse",
		Arity: 1,
	})
	roundTripFun(t, codec, exported, canonicalExport)
}

func TestETFExportFunOfficialLayout(t *testing.T) {
	encoded := []byte{
		canonicalVersion,
		canonicalExport,
		canonicalSmallAtomUTF8, 5, 'l', 'i', 's', 't', 's',
		canonicalSmallAtomUTF8, 7, 'r', 'e', 'v', 'e', 'r', 's', 'e',
		canonicalSmallInteger, 1,
	}
	match funCodec(t).Decode(encoded) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(value):
		want := term.Function(term.Fun{Form: term.ExportedFunction(), Module: "lists", Function: "reverse", Arity: 1})
		if !term.Equal(value, want) {
			t.Fatalf("EXPORT_EXT = %#v", value)
		}
		match funCodec(t).Encode(value) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(roundTrip):
			if !bytes.Equal(roundTrip, encoded) {
				t.Fatalf("EXPORT_EXT bytes = %v", roundTrip)
			}
		}
	}
}

func TestETFNewFunEnvironmentRoundTripProperty(t *testing.T) {
	codec := funCodec(t)
	property := func(values []byte, index uint16, unique uint16) bool {
		environment := make([]term.Term, len(values))
		for position, value := range values {
			environment[position] = term.Integer(int64(value))
		}
		fun := term.Function(term.Fun{
			Form: term.NewClosure([16]byte{1, 2, 3}, uint32(index), uint32(index) + 1),
			Module: "property",
			Arity: 1,
			Unique: uint32(unique),
			Creator: term.PID{Node: 1, Number: 1, Creation: 1},
			Environment: environment,
		})
		encodedResult := codec.Encode(fun)
		var encoded []byte
		match encodedResult { case result.Err(_): return false; case result.Ok(value): encoded = value }
		match codec.Decode(encoded) {
		case result.Err(_):
			return false
		case result.Ok(decoded):
			return term.Equal(decoded, fun)
		}
	}
	match result.Of(struct{}{}, quick.Check(property, nil)) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
}

func TestETFNewFunRejectsMalformedSize(t *testing.T) {
	codec := funCodec(t)
	value := term.Function(term.Fun{
		Form: term.NewClosure([16]byte{1}, 1, 1),
		Module: "demo",
		Arity: 0,
		Unique: 1,
		Creator: term.PID{Node: 1, Number: 1, Creation: 1},
	})
	match codec.Encode(value) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(encoded):
		binary.BigEndian.PutUint32(encoded[2:6], binary.BigEndian.Uint32(encoded[2:6]) + 1)
		match codec.Decode(encoded) {
		case result.Ok(_):
			t.Fatal("malformed NEW_FUN_EXT size was accepted")
		case result.Err(_):
		}
	}
}

func TestETFRejectsVMLocalClosureWithoutWireIdentity(t *testing.T) {
	value := term.Function(term.Fun{Form: term.LocalClosure(), Module: "demo", Function: "f", Arity: 0, Label: 1})
	match funCodec(t).Encode(value) {
	case result.Ok(_):
		t.Fatal("VM-local closure was encoded without creator identity")
	case result.Err(failure):
		var checked Failure = failure
		match checked {
		case Invalid(area, _):
			if area != "fun" { t.Fatalf("local closure area = %q", area) }
		case LimitExceeded(_, _, _), MissingVersion, TrailingBytes(_), UnsupportedTag(_, _), Truncated(_, _), ResolverRequired, UnknownNodeID(_), UnknownNodeName(_), Foreign(_, _), TermRejected(_):
			t.Fatalf("local closure failure = %v", failure)
		}
	}
}
