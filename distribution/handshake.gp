// Package distribution defines authenticated, transport-independent Erlang
// distribution semantics.
package distribution

import (
	"crypto/md5"
	"crypto/subtle"
	"fmt"
	"strconv"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type Node struct {
	Name     string
	Flags    uint64
	Creation uint32
}

type Cookie struct {
	text string
}

type ChallengeSource func() uint32

type Failure enum {
	InvalidNode(Name string)
	EmptyCookie()
	NilChallengeSource()
	DigestMismatch()
	UnexpectedSequence(Expected uint64, Received uint64)
	ETFRejected(Cause string)
	InvalidEnvelope()
}

func (failure Failure) Error() string {
	match failure {
	case InvalidNode(name):
		return fmt.Sprintf("gotp/distribution: invalid node %q", name)
	case EmptyCookie:
		return "gotp/distribution: cookie is empty"
	case NilChallengeSource:
		return "gotp/distribution: challenge source is nil"
	case DigestMismatch:
		return "gotp/distribution: challenge digest mismatch"
	case UnexpectedSequence(expected, received):
		return fmt.Sprintf("gotp/distribution: expected sequence %d, received %d", expected, received)
	case ETFRejected(cause):
		return fmt.Sprintf("gotp/distribution: ETF rejected: %s", cause)
	case InvalidEnvelope:
		return "gotp/distribution: invalid envelope"
	}
}

type Challenge struct {
	Acceptor Node
	Value    uint32
}

type Reply struct {
	Initiator Node
	Challenge uint32
	Digest    [md5.Size]byte
}

type Acknowledgement struct {
	Digest [md5.Size]byte
}

type ServerAwaitingReply struct {
	local     Node
	remote    Node
	challenge uint32
}

type ClientAwaitingAcknowledgement struct {
	local     Node
	remote    Node
	challenge uint32
}

type Connection struct {
	Local           Node
	Remote          Node
	NegotiatedFlags uint64
}

type ServerAcceptance struct {
	Acknowledgement Acknowledgement
	Connection      Connection
}

type ClientResponse struct {
	Reply   Reply
	Pending ClientAwaitingAcknowledgement
}

func NewCookie(text string) result.Result[Cookie, Failure] {
	if text == "" {
		return result.Err[Cookie, Failure](EmptyCookie())
	}
	return result.Ok[Cookie, Failure](Cookie{text: text})
}

// assayxport:unit gotp.distribution.handshake
func BeginServer(
	local Node,
	remote Node,
	source ChallengeSource,
) result.Result[struct {
	Challenge Challenge
	Pending   ServerAwaitingReply
}, Failure] {
	match validatePair(local, remote) {
	case result.Err(failure):
		return result.Err[struct {
			Challenge Challenge
			Pending   ServerAwaitingReply
		}, Failure](failure)
	case result.Ok(_):
	}
	if source == nil {
		return result.Err[struct {
			Challenge Challenge
			Pending   ServerAwaitingReply
		}, Failure](NilChallengeSource())
	}
	value := source()
	return result.Ok[struct {
		Challenge Challenge
		Pending   ServerAwaitingReply
	}, Failure](struct {
		Challenge Challenge
		Pending   ServerAwaitingReply
	}{
		Challenge: Challenge{Acceptor: local, Value: value},
		Pending: ServerAwaitingReply{local: local, remote: remote, challenge: value},
	})
}

func AnswerChallenge(
	local Node,
	remote Node,
	outCookie Cookie,
	source ChallengeSource,
	challenge Challenge,
) result.Result[ClientResponse, Failure] {
	match validatePair(local, remote) {
	case result.Err(failure):
		return result.Err[ClientResponse, Failure](failure)
	case result.Ok(_):
	}
	if source == nil {
		return result.Err[ClientResponse, Failure](NilChallengeSource())
	}
	if challenge.Acceptor != remote {
		return result.Err[ClientResponse, Failure](InvalidNode(challenge.Acceptor.Name))
	}
	value := source()
	return result.Ok[ClientResponse, Failure](ClientResponse{
		Reply: Reply{
			Initiator: local,
			Challenge: value,
			Digest: digest(outCookie, challenge.Value),
		},
		Pending: ClientAwaitingAcknowledgement{
			local: local, remote: remote, challenge: value,
		},
	})
}

func AcceptReply(
	pending ServerAwaitingReply,
	inCookie Cookie,
	outCookie Cookie,
	reply Reply,
) result.Result[ServerAcceptance, Failure] {
	if reply.Initiator != pending.remote {
		return result.Err[ServerAcceptance, Failure](InvalidNode(reply.Initiator.Name))
	}
	expected := digest(inCookie, pending.challenge)
	if subtle.ConstantTimeCompare(expected[:], reply.Digest[:]) != 1 {
		return result.Err[ServerAcceptance, Failure](DigestMismatch())
	}
	return result.Ok[ServerAcceptance, Failure](ServerAcceptance{
		Acknowledgement: Acknowledgement{Digest: digest(outCookie, reply.Challenge)},
		Connection: connection(pending.local, pending.remote),
	})
}

func AcceptAcknowledgement(
	pending ClientAwaitingAcknowledgement,
	inCookie Cookie,
	acknowledgement Acknowledgement,
) result.Result[Connection, Failure] {
	expected := digest(inCookie, pending.challenge)
	if subtle.ConstantTimeCompare(expected[:], acknowledgement.Digest[:]) != 1 {
		return result.Err[Connection, Failure](DigestMismatch())
	}
	return result.Ok[Connection, Failure](connection(pending.local, pending.remote))
}

func validatePair(local Node, remote Node) result.Result[bool, Failure] {
	for _, node := range []Node{local, remote} {
		match term.Atom(node.Name) {
		case result.Err(_):
			return result.Err[bool, Failure](InvalidNode(node.Name))
		case result.Ok(_):
		}
		if node.Name == "" {
			return result.Err[bool, Failure](InvalidNode(node.Name))
		}
	}
	return result.Ok[bool, Failure](true)
}

func connection(local Node, remote Node) Connection {
	return Connection{
		Local: local, Remote: remote,
		NegotiatedFlags: local.Flags & remote.Flags,
	}
}

// OTP-29.0.4 erts distribution protocol: MD5(cookie text || decimal challenge).
func digest(cookie Cookie, challenge uint32) [md5.Size]byte {
	text := cookie.text + strconv.FormatUint(uint64(challenge), 10)
	return md5.Sum([]byte(text))
}
