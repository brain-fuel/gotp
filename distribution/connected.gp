package distribution

import (
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

type ConnectedFrame enum {
	Tick()
	ConnectedTerms(Control term.Term, Payload option.Option[term.Term])
}

type ConnectedCodec struct {
	cache *AtomCache
	terms etf.CanonicalCodec
}

func NewConnectedCodec(cache *AtomCache, terms etf.CanonicalCodec) ConnectedCodec {
	if cache == nil { cache = NewAtomCache() }
	return ConnectedCodec{cache: cache, terms: terms}
}

// assayxport:unit gotp.distribution.connected-terms
func (codec ConnectedCodec) Decode(packet []byte) result.Result[ConnectedFrame, Failure] {
	match DecodePacket4(packet) {
	case result.Err(failure):
		return result.Err[ConnectedFrame, Failure](failure)
	case result.Ok(body):
		if len(body) == 0 { return result.Ok[ConnectedFrame, Failure](Tick()) }
		match codec.cache.DecodeHeader(body) {
		case result.Err(failure):
			return result.Err[ConnectedFrame, Failure](failure)
		case result.Ok(header):
			remaining := body[header.BytesConsumed:]
			match codec.terms.DecodeVersionlessPrefix(remaining, header.Atoms) {
			case result.Err(failure):
				return result.Err[ConnectedFrame, Failure](ETFRejected(failure.Error()))
			case result.Ok(control):
				remaining = remaining[control.BytesConsumed:]
				if len(remaining) == 0 {
					return result.Ok[ConnectedFrame, Failure](ConnectedTerms(
						control.Value, option.None[term.Term],
					))
				}
				match codec.terms.DecodeVersionlessPrefix(remaining, header.Atoms) {
				case result.Err(failure):
					return result.Err[ConnectedFrame, Failure](ETFRejected(failure.Error()))
				case result.Ok(payload):
					if payload.BytesConsumed != len(remaining) {
						return result.Err[ConnectedFrame, Failure](MalformedPacket("connected frame contains more than two terms"))
					}
					return result.Ok[ConnectedFrame, Failure](ConnectedTerms(
						control.Value, option.Some[term.Term](payload.Value),
					))
				}
			}
		}
	}
}

func (codec ConnectedCodec) Encode(
	control term.Term,
	payload option.Option[term.Term],
) result.Result[[]byte, Failure] {
	match codec.cache.EncodeHeader([]AtomReference{}) {
	case result.Err(failure):
		return result.Err[[]byte, Failure](failure)
	case result.Ok(header):
		match codec.terms.Encode(control) {
		case result.Err(failure):
			return result.Err[[]byte, Failure](ETFRejected(failure.Error()))
		case result.Ok(encodedControl):
			body := append(header, encodedControl[1:]...)
			match payload {
			case option.None:
			case option.Some(value):
				match codec.terms.Encode(value) {
				case result.Err(failure):
					return result.Err[[]byte, Failure](ETFRejected(failure.Error()))
				case result.Ok(encodedPayload):
					body = append(body, encodedPayload[1:]...)
				}
			}
			return EncodePacket4(body)
		}
	}
}
