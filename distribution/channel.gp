package distribution

import (
	"bytes"
	"sync"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

type Envelope struct {
	From    term.PID
	To      term.PID
	Message term.Term
}

type Frame struct {
	Sequence uint64
	Payload  []byte
}

type Channel struct {
	mu              sync.Mutex
	codec           etf.CanonicalCodec
	nextSend        uint64
	nextReceive     uint64
}

func NewChannel(codec etf.CanonicalCodec) *Channel {
	return &Channel{codec: codec, nextSend: 1, nextReceive: 1}
}

// assayxport:unit gotp.distribution.ordered-channel
func (channel *Channel) Send(envelope Envelope) result.Result[Frame, Failure] {
	value := term.Tuple(
		term.MustAtom("$gotp_dist"),
		term.PIDValue(envelope.From),
		term.PIDValue(envelope.To),
		envelope.Message.Clone(),
	)
	match channel.codec.Encode(value) {
	case result.Err(failure):
		return result.Err[Frame, Failure](ETFRejected(failure.Error()))
	case result.Ok(encoded):
		channel.mu.Lock()
		defer channel.mu.Unlock()
		frame := Frame{Sequence: channel.nextSend, Payload: bytes.Clone(encoded)}
		channel.nextSend++
		return result.Ok[Frame, Failure](frame)
	}
}

func (channel *Channel) Receive(frame Frame) result.Result[Envelope, Failure] {
	channel.mu.Lock()
	defer channel.mu.Unlock()
	if frame.Sequence != channel.nextReceive {
		return result.Err[Envelope, Failure](UnexpectedSequence(channel.nextReceive, frame.Sequence))
	}
	match channel.codec.Decode(bytes.Clone(frame.Payload)) {
	case result.Err(failure):
		return result.Err[Envelope, Failure](ETFRejected(failure.Error()))
	case result.Ok(value):
		match value {
		case term.TupleTerm(elements):
			if len(elements) != 4 || !elements[0].Equal(term.MustAtom("$gotp_dist")) {
				return result.Err[Envelope, Failure](InvalidEnvelope())
			}
			match elements[1] {
			case term.PIDTerm(from):
				match elements[2] {
				case term.PIDTerm(to):
					channel.nextReceive++
					return result.Ok[Envelope, Failure](Envelope{
						From: from, To: to, Message: elements[3].Clone(),
					})
				case _:
					return result.Err[Envelope, Failure](InvalidEnvelope())
				}
			case _:
				return result.Err[Envelope, Failure](InvalidEnvelope())
			}
		case _:
			return result.Err[Envelope, Failure](InvalidEnvelope())
		}
	}
}
