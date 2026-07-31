package distribution

import (
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type TypedConnectedFrame enum {
	TypedTick()
	TypedSignal(Control Control, Payload option.Option[term.Term])
}

type NegotiatedCodec struct {
	connected ConnectedCodec
	policy    *NegotiatedPolicy
}

func NewNegotiatedCodec(connected ConnectedCodec, flags uint64) NegotiatedCodec {
	return NegotiatedCodec{connected: connected, policy: NewNegotiatedPolicy(flags)}
}

func (codec NegotiatedCodec) Decode(packet []byte) result.Result[TypedConnectedFrame, Failure] {
	match codec.connected.DecodeTyped(packet) {
	case result.Err(failure): return result.Err[TypedConnectedFrame, Failure](failure)
	case result.Ok(frame):
		match frame {
		case TypedTick: return result.Ok[TypedConnectedFrame, Failure](frame)
		case TypedSignal(control, _):
			match codec.policy.Accept(control) {
			case result.Err(failure): return result.Err[TypedConnectedFrame, Failure](failure)
			case result.Ok(_): return result.Ok[TypedConnectedFrame, Failure](frame)
			}
		}
	}
}

func (codec NegotiatedCodec) Encode(
	control Control,
	payload option.Option[term.Term],
) result.Result[[]byte, Failure] {
	match codec.policy.Accept(control) {
	case result.Err(failure): return result.Err[[]byte, Failure](failure)
	case result.Ok(_): return codec.connected.EncodeTyped(control, payload)
	}
}

func (codec ConnectedCodec) DecodeTyped(packet []byte) result.Result[TypedConnectedFrame, Failure] {
	match codec.Decode(packet) {
	case result.Err(failure): return result.Err[TypedConnectedFrame, Failure](failure)
	case result.Ok(frame):
		match frame {
		case Tick: return result.Ok[TypedConnectedFrame, Failure](TypedTick())
		case ConnectedTerms(rawControl, payload):
			match DecodeControl(rawControl) {
			case result.Err(failure): return result.Err[TypedConnectedFrame, Failure](failure)
			case result.Ok(control):
				match ValidatePayload(control, payload) {
				case result.Err(failure): return result.Err[TypedConnectedFrame, Failure](failure)
				case result.Ok(_): return result.Ok[TypedConnectedFrame, Failure](TypedSignal(control, payload))
				}
			}
		}
	}
}

func (codec ConnectedCodec) EncodeTyped(
	control Control,
	payload option.Option[term.Term],
) result.Result[[]byte, Failure] {
	match ValidatePayload(control, payload) {
	case result.Err(failure): return result.Err[[]byte, Failure](failure)
	case result.Ok(_):
		match EncodeControl(control) {
		case result.Err(failure): return result.Err[[]byte, Failure](failure)
		case result.Ok(raw): return codec.Encode(raw, payload)
		}
	}
}
