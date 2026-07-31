package distribution


import (
	"sync"
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

// assayxport:unit gotp.distribution.outbound-control-laws
func TestRequiredReplyPrecedesQueuedOrdinaryOutput(t *testing.T) {
	from, to, _, _, _ := controlFixtureTerms()
	queue := NewOutboundQueue()
	ordinary := mustControl(t, LinkCode(), from, to)
	reply := mustControl(t, UnlinkIDAckCode(), term.Integer(9), from, to)
	match queue.Enqueue(OrdinaryOutput(), term.PID{Node: 2, Number: 2}, ordinary, option.None[term.Term]) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(_):
	}
	match queue.Enqueue(RequiredReplyOutput(), term.PID{Node: 2, Number: 2}, reply, option.None[term.Term]) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(_):
	}
	match queue.Next() {
	case option.None: t.Fatal("queue is empty")
	case option.Some(message): if message.Control.Number() != 36 { t.Fatal("required reply was not first") }
	}
	match queue.Next() {
	case option.None: t.Fatal("ordinary output was lost")
	case option.Some(message): if message.Control.Number() != 1 { t.Fatal("ordinary output changed") }
	}
}

func TestOutboundQueueClonesPayloadAndEncodesNegotiatedPacket(t *testing.T) {
	from, to, _, _, _ := controlFixtureTerms()
	queue := NewOutboundQueue()
	raw := []byte("message")
	control := mustControl(t, SendSenderCode(), from, to)
	payload := option.Some[term.Term](term.Binary(raw))
	match queue.Enqueue(OrdinaryOutput(), term.PID{Node: 2, Number: 2}, control, payload) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(_):
	}
	raw[0] = 'X'
	connected := NewConnectedCodec(nil, etf.CanonicalCodec{Nodes: mustNodes(t)})
	codec := NewNegotiatedCodec(connected, DFlagSendSender)
	match queue.EncodeNext(codec) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(packetOption):
		match packetOption {
		case option.None: t.Fatal("encoded queue is empty")
		case option.Some(packet):
			match connected.DecodeTyped(packet) {
			case result.Err(failure): t.Fatal(failure.Error())
			case result.Ok(frame):
				match frame {
				case TypedTick: t.Fatal("output decoded as tick")
				case TypedSignal(_, decoded):
					match decoded {
					case option.None: t.Fatal("payload is absent")
					case option.Some(value):
						if !value.Equal(term.Binary([]byte("message"))) { t.Fatalf("payload = %#v", value) }
					}
				}
			}
		}
	}
}

func TestOutboundConcurrentEnqueueLosesNoMessages(t *testing.T) {
	from, to, _, _, _ := controlFixtureTerms()
	control := mustControl(t, LinkCode(), from, to)
	queue := NewOutboundQueue()
	var wait sync.WaitGroup
	for index := 0; index < 100; index++ {
		wait.Add(1)
		go func() {
			defer wait.Done()
			queue.Enqueue(OrdinaryOutput(), term.PID{Node: 2, Number: 2}, control, option.None[term.Term])
		}()
	}
	wait.Wait()
	count := 0
	for {
		match queue.Next() {
		case option.None:
			if count != 100 { t.Fatalf("messages = %d", count) }
			return
		case option.Some(_): count++
		}
	}
}
