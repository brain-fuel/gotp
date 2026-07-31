package distribution

import (
	"sync"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type OutboundMessage struct {
	Destination term.PID
	Control     Control
	Payload     option.Option[term.Term]
}

type OutboundPriority enum {
	OrdinaryOutput()
	RequiredReplyOutput()
}

type OutboundQueue struct {
	mu       sync.Mutex
	priority []OutboundMessage
	ordinary []OutboundMessage
}

func NewOutboundQueue() *OutboundQueue { return &OutboundQueue{} }

// assayxport:unit gotp.distribution.outbound-controls
func (queue *OutboundQueue) Enqueue(
	priority OutboundPriority,
	destination term.PID,
	control Control,
	payload option.Option[term.Term],
) result.Result[bool, Failure] {
	if !destination.Valid() {
		return result.Err[bool, Failure](InvalidControl("outbound destination pid is invalid"))
	}
	match ValidatePayload(control, payload) {
	case result.Err(failure): return result.Err[bool, Failure](failure)
	case result.Ok(_):
	}
	cloned := cloneControl(control)
		message := OutboundMessage{
			Destination: destination,
			Control: cloned,
			Payload: cloneOptionalTerm(payload),
		}
		queue.mu.Lock()
		defer queue.mu.Unlock()
		match priority {
		case OrdinaryOutput: queue.ordinary = append(queue.ordinary, message)
		case RequiredReplyOutput: queue.priority = append(queue.priority, message)
		}
		return result.Ok[bool, Failure](true)
}

func (queue *OutboundQueue) Next() option.Option[OutboundMessage] {
	queue.mu.Lock()
	defer queue.mu.Unlock()
	if len(queue.priority) > 0 {
		message := queue.priority[0]
		queue.priority = queue.priority[1:]
		return option.Some[OutboundMessage](cloneOutbound(message))
	}
	if len(queue.ordinary) > 0 {
		message := queue.ordinary[0]
		queue.ordinary = queue.ordinary[1:]
		return option.Some[OutboundMessage](cloneOutbound(message))
	}
	return option.None[OutboundMessage]
}

func (queue *OutboundQueue) EncodeNext(
	codec NegotiatedCodec,
) result.Result[option.Option[[]byte], Failure] {
	match queue.Next() {
	case option.None:
		return result.Ok[option.Option[[]byte], Failure](option.None[[]byte])
	case option.Some(message):
		match codec.Encode(message.Control, message.Payload) {
		case result.Err(failure): return result.Err[option.Option[[]byte], Failure](failure)
		case result.Ok(packet):
			return result.Ok[option.Option[[]byte], Failure](option.Some[[]byte](packet))
		}
	}
}

func cloneControl(control Control) Control {
	return Control{code: control.code, fields: control.Fields()}
}

func cloneOptionalTerm(value option.Option[term.Term]) option.Option[term.Term] {
	match value {
	case option.None: return option.None[term.Term]
	case option.Some(found): return option.Some[term.Term](found.Clone())
	}
}

func cloneOutbound(message OutboundMessage) OutboundMessage {
	return OutboundMessage{
		Destination: message.Destination,
		Control: cloneControl(message.Control),
		Payload: cloneOptionalTerm(message.Payload),
	}
}
