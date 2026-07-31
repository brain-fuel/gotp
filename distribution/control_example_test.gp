package distribution

import (
	"math/big"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

func controlFixtureTerms() (term.Term, term.Term, term.Term, term.Term, term.Term) {
	from := term.PIDValue(term.PID{Node: 1, Number: 1, Creation: 1})
	to := term.PIDValue(term.PID{Node: 2, Number: 2, Creation: 2})
	reference := term.ReferenceValue(term.Reference{Node: 1, Creation: 1, Words: [5]uint32{7}, Length: 1})
	token := term.Tuple(term.MustAtom("trace"), term.Integer(1))
	reason := term.MustAtom("normal")
	return from, to, reference, token, reason
}

// assayxport:unit gotp.distribution.control-message-laws
func TestAllDocumentedControlOpcodesRoundTrip(t *testing.T) {
	from, to, reference, token, reason := controlFixtureTerms()
	unused := term.List()
	name := term.MustAtom("server")
	mfa := term.Tuple(term.MustAtom("mod"), term.MustAtom("start"), term.Integer(0))
	options := term.List()
	maxID := term.MustBigInteger(new(big.Int).SetUint64(^uint64(0)))
	values := []term.Term{
		term.Tuple(term.Integer(1), from, to),
		term.Tuple(term.Integer(2), unused, to),
		term.Tuple(term.Integer(3), from, to, reason),
		term.Tuple(term.Integer(5)),
		term.Tuple(term.Integer(6), from, unused, name),
		term.Tuple(term.Integer(7), from, to),
		term.Tuple(term.Integer(8), from, to, reason),
		term.Tuple(term.Integer(12), unused, to, token),
		term.Tuple(term.Integer(13), from, to, token, reason),
		term.Tuple(term.Integer(16), from, unused, name, token),
		term.Tuple(term.Integer(18), from, to, token, reason),
		term.Tuple(term.Integer(19), from, to, reference),
		term.Tuple(term.Integer(20), from, name, reference),
		term.Tuple(term.Integer(21), name, to, reference, reason),
		term.Tuple(term.Integer(22), from, to),
		term.Tuple(term.Integer(23), from, to, token),
		term.Tuple(term.Integer(24), from, to),
		term.Tuple(term.Integer(25), from, to, token),
		term.Tuple(term.Integer(26), from, to),
		term.Tuple(term.Integer(27), from, to, token),
		term.Tuple(term.Integer(28), name, to, reference),
		term.Tuple(term.Integer(29), reference, from, to, mfa, options),
		term.Tuple(term.Integer(30), reference, from, to, mfa, options, token),
		term.Tuple(term.Integer(31), reference, to, term.Integer(3), from),
		term.Tuple(term.Integer(32), reference, to, term.Integer(0), name, token),
		term.Tuple(term.Integer(33), from, reference),
		term.Tuple(term.Integer(34), from, reference, token),
		term.Tuple(term.Integer(35), maxID, from, to),
		term.Tuple(term.Integer(36), term.Integer(1), from, to),
	}
	for _, value := range values {
		match DecodeControl(value) {
		case result.Err(failure): t.Fatalf("%#v: %s", value, failure.Error())
		case result.Ok(control):
			match EncodeControl(control) {
			case result.Err(failure): t.Fatal(failure.Error())
			case result.Ok(encoded):
				if !encoded.Equal(value) { t.Fatalf("encoded = %#v, want %#v", encoded, value) }
			}
		}
	}
}

func TestControlPayloadRulesAndTypedCodec(t *testing.T) {
	from, to, _, _, _ := controlFixtureTerms()
	match NewControl(SendSenderCode(), from, to) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(control):
		match ValidatePayload(control, option.None[term.Term]) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("missing send payload was accepted")
		}
		codec := NewConnectedCodec(nil, etf.CanonicalCodec{Nodes: mustNodes(t)})
		payload := option.Some[term.Term](term.MustAtom("hello"))
		match codec.EncodeTyped(control, payload) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(packet):
			match codec.DecodeTyped(packet) {
			case result.Err(failure): t.Fatal(failure.Error())
			case result.Ok(frame):
				match frame {
				case TypedTick: t.Fatal("signal decoded as tick")
				case TypedSignal(decoded, decodedPayload):
					if controlNumber(decoded.Code()) != 22 || !equalOptionalTerm(decodedPayload, payload) {
						t.Fatalf("frame = %#v", frame)
					}
				}
			}
		}
	}
}

func TestControlRejectsObsoleteUnknownAndMalformedOperations(t *testing.T) {
	from, to, _, _, _ := controlFixtureTerms()
	invalid := []term.Term{
		term.Tuple(term.Integer(4), from, to),
		term.Tuple(term.Integer(22), from),
		term.Tuple(term.Integer(35), term.Integer(0), from, to),
		term.Tuple(term.Integer(31), term.MustAtom("not_ref"), to, term.Integer(0), from),
	}
	for _, value := range invalid {
		match DecodeControl(value) {
		case result.Err(_):
		case result.Ok(_): t.Fatalf("invalid control was accepted: %#v", value)
		}
	}
}

func TestControlDecoderNeverPanicsOnTerms(t *testing.T) {
	law := func(opcode uint8, arity uint8) bool {
		count := int(arity % 10)
		fields := make([]term.Term, count)
		for index := range fields { fields[index] = term.Integer(int64(index)) }
		DecodeControl(term.Tuple(append([]term.Term{term.Integer(int64(opcode))}, fields...)...))
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2_000})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}
