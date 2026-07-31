package distribution

import (
	"encoding/binary"
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

// assayxport:unit gotp.distribution.connected-term-laws
func TestConnectedCodecDecodesHeaderAtomReferences(t *testing.T) {
	body := []byte{
		131, 68, 1, 8,
		7, 2, 'o', 'k',
		82, 0,
		97, 42,
	}
	packet := make([]byte, 4+len(body))
	binary.BigEndian.PutUint32(packet, uint32(len(body)))
	copy(packet[4:], body)
	codec := NewConnectedCodec(NewAtomCache(), etf.CanonicalCodec{})
	match codec.Decode(packet) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(frame):
		match frame {
		case ConnectedTerms(control, payload):
			if !control.Equal(term.MustAtom("ok")) { t.Fatalf("control = %#v", control) }
			match payload {
			case option.None: t.Fatal("payload is absent")
			case option.Some(value):
				if !value.Equal(term.Integer(42)) { t.Fatalf("payload = %#v", value) }
			}
		case Tick: t.Fatal("data packet decoded as tick")
		}
	}
}

func TestConnectedCodecRoundTripsOptionalPayload(t *testing.T) {
	codec := NewConnectedCodec(nil, etf.CanonicalCodec{})
	control := term.Tuple(term.Integer(5))
	for _, payload := range []option.Option[term.Term]{
		option.None[term.Term], option.Some[term.Term](term.Binary([]byte("message"))),
	} {
		match codec.Encode(control, payload) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(packet):
			match codec.Decode(packet) {
			case result.Err(failure): t.Fatal(failure.Error())
			case result.Ok(frame):
				match frame {
				case Tick: t.Fatal("encoded terms decoded as tick")
				case ConnectedTerms(decodedControl, decodedPayload):
					if !decodedControl.Equal(control) || !equalOptionalTerm(decodedPayload, payload) {
						t.Fatalf("frame = %#v", frame)
					}
				}
			}
		}
	}
}

func equalOptionalTerm(left option.Option[term.Term], right option.Option[term.Term]) bool {
	match left {
	case option.None:
		match right {
		case option.None: return true
		case option.Some(_): return false
		}
	case option.Some(leftValue):
		match right {
		case option.None: return false
		case option.Some(rightValue): return leftValue.Equal(rightValue)
		}
	}
}

func TestConnectedCodecRejectsThirdTerm(t *testing.T) {
	codec := NewConnectedCodec(nil, etf.CanonicalCodec{})
	match codec.Encode(term.Integer(1), option.Some[term.Term](term.Integer(2))) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(packet):
		packet = append(packet, 97, 3)
		binary.BigEndian.PutUint32(packet, binary.BigEndian.Uint32(packet)+2)
		match codec.Decode(packet) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("third term was accepted")
		}
	}
}
