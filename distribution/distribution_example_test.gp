package distribution

import (
	"bytes"
	"crypto/md5"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

func mustCookie(t *testing.T, text string) Cookie {
	match NewCookie(text) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(cookie):
		return cookie
	}
	panic("unreachable")
}

func mustNodes(t *testing.T) *etf.StaticNodeTable {
	match etf.NewStaticNodeTable(map[uint32]string{1: "a@local", 2: "b@local"}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(nodes):
		return nodes
	}
	panic("unreachable")
}

// assayxport:unit gotp.distribution.handshake-laws
func TestHandshakeAuthenticatesBothDirectionsAndNegotiatesFlags(t *testing.T) {
	client := Node{Name: "a@local", Flags: 0b1011, Creation: 1}
	server := Node{Name: "b@local", Flags: 0b0111, Creation: 2}
	clientToServer := mustCookie(t, "client-secret")
	serverToClient := mustCookie(t, "server-secret")
	match BeginServer(server, client, func() uint32 { return 17 }) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(started):
		match AnswerChallenge(client, server, clientToServer, func() uint32 { return 29 }, started.Challenge) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(response):
			match AcceptReply(started.Pending, clientToServer, serverToClient, response.Reply) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(accepted):
				if accepted.Connection.NegotiatedFlags != 0b0011 {
					t.Fatalf("flags = %b", accepted.Connection.NegotiatedFlags)
				}
				match AcceptAcknowledgement(response.Pending, serverToClient, accepted.Acknowledgement) {
				case result.Err(failure):
					t.Fatal(failure.Error())
				case result.Ok(connection):
					if connection.Remote != server {
						t.Fatalf("remote = %#v", connection.Remote)
					}
				}
			}
		}
	}
}

func TestDigestUsesOTPTextOrder(t *testing.T) {
	cookie := mustCookie(t, "cookie")
	want := md5.Sum([]byte("cookie42"))
	if digest(cookie, 42) != want {
		t.Fatalf("digest = %x, want %x", digest(cookie, 42), want)
	}
}

func TestHandshakeRejectsTamperingAndWrongCookie(t *testing.T) {
	client := Node{Name: "a@local"}
	server := Node{Name: "b@local"}
	cookie := mustCookie(t, "right")
	wrong := mustCookie(t, "wrong")
	match BeginServer(server, client, func() uint32 { return 1 }) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(started):
		match AnswerChallenge(client, server, cookie, func() uint32 { return 2 }, started.Challenge) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(response):
			response.Reply.Digest[0] ^= 0xff
			match AcceptReply(started.Pending, wrong, cookie, response.Reply) {
			case result.Err(_):
			case result.Ok(_):
				t.Fatal("tampered reply was accepted")
			}
		}
	}
}

// assayxport:unit gotp.distribution.ordered-channel-laws
func TestOrderedChannelClonesAndRejectsReplay(t *testing.T) {
	codec := etf.CanonicalCodec{Nodes: mustNodes(t)}
	sender := NewChannel(codec)
	receiver := NewChannel(codec)
	raw := []byte("operational")
	envelope := Envelope{
		From: term.PID{Node: 1, Number: 1, Creation: 1},
		To: term.PID{Node: 2, Number: 2, Creation: 2},
		Message: term.Binary(raw),
	}
	match sender.Send(envelope) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(frame):
		raw[0] = 'X'
		preserved := bytes.Clone(frame.Payload)
		match receiver.Receive(frame) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(received):
			if !received.Message.Equal(term.Binary([]byte("operational"))) {
				t.Fatalf("message = %#v", received.Message)
			}
		}
		if !bytes.Equal(frame.Payload, preserved) {
			t.Fatal("receive mutated frame payload")
		}
		match receiver.Receive(frame) {
		case result.Err(_):
		case result.Ok(_):
			t.Fatal("replayed frame was accepted")
		}
	}
}

func TestCorruptionDoesNotAdvanceReceiveSequence(t *testing.T) {
	codec := etf.CanonicalCodec{Nodes: mustNodes(t)}
	sender := NewChannel(codec)
	receiver := NewChannel(codec)
	envelope := Envelope{
		From: term.PID{Node: 1, Number: 1}, To: term.PID{Node: 2, Number: 2},
		Message: term.Integer(7),
	}
	match sender.Send(envelope) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(frame):
		corrupt := Frame{Sequence: frame.Sequence, Payload: []byte{0}}
		match receiver.Receive(corrupt) {
		case result.Err(_):
		case result.Ok(_):
			t.Fatal("corrupt frame was accepted")
		}
		match receiver.Receive(frame) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(_):
		}
	}
}

func TestCanonicalEnvelopeEncodingLaw(t *testing.T) {
	codec := etf.CanonicalCodec{Nodes: mustNodes(t)}
	law := func(value int64, raw []byte) bool {
		envelope := Envelope{
			From: term.PID{Node: 1, Number: 1}, To: term.PID{Node: 2, Number: 2},
			Message: term.Tuple(term.Integer(value), term.Binary(raw)),
		}
		left := NewChannel(codec)
		right := NewChannel(codec)
		match left.Send(envelope) {
		case result.Err(_):
			return false
		case result.Ok(first):
			match right.Send(envelope) {
			case result.Err(_):
				return false
			case result.Ok(second):
				return bytes.Equal(first.Payload, second.Payload)
			}
		}
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 500})) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}
