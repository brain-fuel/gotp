package distribution

import (
	"bytes"
	"encoding/binary"
	"math"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

const (
	wireNameTag       byte = 'N'
	wireStatusTag     byte = 's'
	wireComplementTag byte = 'c'
	wireReplyTag      byte = 'r'
	wireAckTag        byte = 'a'
)

type Status enum {
	StatusOK()
	StatusOKSimultaneous()
	StatusNOK()
	StatusNotAllowed()
	StatusAlive()
	StatusContinue(Continue bool)
	StatusNamed(Node Node)
}

type Complement struct {
	FlagsHigh uint32
	Creation  uint32
}

func EncodePacket2(payload []byte) result.Result[[]byte, Failure] {
	if len(payload) > math.MaxUint16 {
		return result.Err[[]byte, Failure](PacketTooLarge(uint64(len(payload))))
	}
	packet := make([]byte, 2+len(payload))
	binary.BigEndian.PutUint16(packet, uint16(len(payload)))
	copy(packet[2:], payload)
	return result.Ok[[]byte, Failure](packet)
}

func DecodePacket2(packet []byte) result.Result[[]byte, Failure] {
	if len(packet) < 2 {
		return result.Err[[]byte, Failure](MalformedPacket("packet-2 header is truncated"))
	}
	length := int(binary.BigEndian.Uint16(packet))
	if len(packet) != length+2 {
		return result.Err[[]byte, Failure](MalformedPacket("packet-2 length mismatch"))
	}
	return result.Ok[[]byte, Failure](bytes.Clone(packet[2:]))
}

func EncodePacket4(payload []byte) result.Result[[]byte, Failure] {
	if uint64(len(payload)) > math.MaxUint32 {
		return result.Err[[]byte, Failure](PacketTooLarge(uint64(len(payload))))
	}
	packet := make([]byte, 4+len(payload))
	binary.BigEndian.PutUint32(packet, uint32(len(payload)))
	copy(packet[4:], payload)
	return result.Ok[[]byte, Failure](packet)
}

func DecodePacket4(packet []byte) result.Result[[]byte, Failure] {
	if len(packet) < 4 {
		return result.Err[[]byte, Failure](MalformedPacket("packet-4 header is truncated"))
	}
	length := uint64(binary.BigEndian.Uint32(packet))
	if uint64(len(packet)-4) != length {
		return result.Err[[]byte, Failure](MalformedPacket("packet-4 length mismatch"))
	}
	return result.Ok[[]byte, Failure](bytes.Clone(packet[4:]))
}

// assayxport:unit gotp.distribution.handshake-wire
func EncodeSendName(node Node) result.Result[[]byte, Failure] {
	match encodeNodeTail(node) {
	case result.Err(failure):
		return result.Err[[]byte, Failure](failure)
	case result.Ok(tail):
		body := make([]byte, 1+len(tail))
		body[0] = wireNameTag
		copy(body[1:], tail)
		return EncodePacket2(body)
	}
}

func DecodeSendName(packet []byte) result.Result[Node, Failure] {
	match DecodePacket2(packet) {
	case result.Err(failure):
		return result.Err[Node, Failure](failure)
	case result.Ok(body):
		if len(body) < 15 || body[0] != wireNameTag {
			return result.Err[Node, Failure](MalformedPacket("invalid send_name"))
		}
		return decodeNodeTail(body[1:])
	}
}

func EncodeChallenge(node Node, challenge uint32) result.Result[[]byte, Failure] {
	match encodeNodeTail(node) {
	case result.Err(failure):
		return result.Err[[]byte, Failure](failure)
	case result.Ok(tail):
		body := make([]byte, 1+8+4+len(tail[8:]))
		body[0] = wireNameTag
		copy(body[1:9], tail[:8])
		binary.BigEndian.PutUint32(body[9:13], challenge)
		copy(body[13:], tail[8:])
		return EncodePacket2(body)
	}
}

func DecodeChallenge(packet []byte) result.Result[struct {
	Node      Node
	Challenge uint32
}, Failure] {
	match DecodePacket2(packet) {
	case result.Err(failure):
		return result.Err[struct {
			Node Node
			Challenge uint32
		}, Failure](failure)
	case result.Ok(body):
		if len(body) < 19 || body[0] != wireNameTag {
			return result.Err[struct {
				Node Node
				Challenge uint32
			}, Failure](MalformedPacket("invalid challenge"))
		}
		challenge := binary.BigEndian.Uint32(body[9:13])
		tail := append(bytes.Clone(body[1:9]), body[13:]...)
		match decodeNodeTail(tail) {
		case result.Err(failure):
			return result.Err[struct {
				Node Node
				Challenge uint32
			}, Failure](failure)
		case result.Ok(node):
			return result.Ok[struct {
				Node Node
				Challenge uint32
			}, Failure](struct {
				Node Node
				Challenge uint32
			}{Node: node, Challenge: challenge})
		}
	}
}

func EncodeStatus(status Status) result.Result[[]byte, Failure] {
	var payload []byte
	match status {
	case StatusOK:
		payload = []byte("ok")
	case StatusOKSimultaneous:
		payload = []byte("ok_simultaneous")
	case StatusNOK:
		payload = []byte("nok")
	case StatusNotAllowed:
		payload = []byte("not_allowed")
	case StatusAlive:
		payload = []byte("alive")
	case StatusContinue(continued):
		if continued {
			payload = []byte("true")
		} else {
			payload = []byte("false")
		}
	case StatusNamed(node):
		match validateWireNode(node) {
		case result.Err(failure):
			return result.Err[[]byte, Failure](failure)
		case result.Ok(_):
		}
		name := []byte(node.Name)
		payload = make([]byte, 6+2+len(name)+4)
		copy(payload, []byte("named:"))
		binary.BigEndian.PutUint16(payload[6:8], uint16(len(name)))
		copy(payload[8:], name)
		binary.BigEndian.PutUint32(payload[8+len(name):], node.Creation)
	}
	return EncodePacket2(append([]byte{wireStatusTag}, payload...))
}

func DecodeStatus(packet []byte) result.Result[Status, Failure] {
	match DecodePacket2(packet) {
	case result.Err(failure):
		return result.Err[Status, Failure](failure)
	case result.Ok(body):
		if len(body) < 2 || body[0] != wireStatusTag {
			return result.Err[Status, Failure](MalformedPacket("invalid status"))
		}
		text := string(body[1:])
		switch text {
		case "ok": return result.Ok[Status, Failure](StatusOK())
		case "ok_simultaneous": return result.Ok[Status, Failure](StatusOKSimultaneous())
		case "nok": return result.Ok[Status, Failure](StatusNOK())
		case "not_allowed": return result.Ok[Status, Failure](StatusNotAllowed())
		case "alive": return result.Ok[Status, Failure](StatusAlive())
		case "true": return result.Ok[Status, Failure](StatusContinue(true))
		case "false": return result.Ok[Status, Failure](StatusContinue(false))
		}
		if len(body) >= 1+6+2+4 && string(body[1:7]) == "named:" {
			length := int(binary.BigEndian.Uint16(body[7:9]))
			if length > len(body)-13 {
				return result.Err[Status, Failure](MalformedPacket("named status is truncated"))
			}
			node := Node{
				Name: string(body[9:9+length]),
				Creation: binary.BigEndian.Uint32(body[9+length:13+length]),
			}
			match validateWireNode(node) {
			case result.Err(failure): return result.Err[Status, Failure](failure)
			case result.Ok(_): return result.Ok[Status, Failure](StatusNamed(node))
			}
		}
		return result.Err[Status, Failure](MalformedPacket("unknown status"))
	}
}

func EncodeComplement(complement Complement) result.Result[[]byte, Failure] {
	body := make([]byte, 9)
	body[0] = wireComplementTag
	binary.BigEndian.PutUint32(body[1:5], complement.FlagsHigh)
	binary.BigEndian.PutUint32(body[5:9], complement.Creation)
	return EncodePacket2(body)
}

func DecodeComplement(packet []byte) result.Result[Complement, Failure] {
	match DecodePacket2(packet) {
	case result.Err(failure): return result.Err[Complement, Failure](failure)
	case result.Ok(body):
		if len(body) != 9 || body[0] != wireComplementTag {
			return result.Err[Complement, Failure](MalformedPacket("invalid complement"))
		}
		return result.Ok[Complement, Failure](Complement{
			FlagsHigh: binary.BigEndian.Uint32(body[1:5]),
			Creation: binary.BigEndian.Uint32(body[5:9]),
		})
	}
}

func EncodeReply(reply Reply) result.Result[[]byte, Failure] {
	body := make([]byte, 21)
	body[0] = wireReplyTag
	binary.BigEndian.PutUint32(body[1:5], reply.Challenge)
	copy(body[5:], reply.Digest[:])
	return EncodePacket2(body)
}

func DecodeReply(packet []byte) result.Result[struct {
	Challenge uint32
	Digest [16]byte
}, Failure] {
	match DecodePacket2(packet) {
	case result.Err(failure):
		return result.Err[struct { Challenge uint32; Digest [16]byte }, Failure](failure)
	case result.Ok(body):
		if len(body) != 21 || body[0] != wireReplyTag {
			return result.Err[struct { Challenge uint32; Digest [16]byte }, Failure](MalformedPacket("invalid challenge reply"))
		}
		var digest [16]byte
		copy(digest[:], body[5:])
		return result.Ok[struct { Challenge uint32; Digest [16]byte }, Failure](struct { Challenge uint32; Digest [16]byte }{
			Challenge: binary.BigEndian.Uint32(body[1:5]), Digest: digest,
		})
	}
}

func EncodeAcknowledgement(acknowledgement Acknowledgement) result.Result[[]byte, Failure] {
	body := append([]byte{wireAckTag}, acknowledgement.Digest[:]...)
	return EncodePacket2(body)
}

func DecodeAcknowledgement(packet []byte) result.Result[Acknowledgement, Failure] {
	match DecodePacket2(packet) {
	case result.Err(failure): return result.Err[Acknowledgement, Failure](failure)
	case result.Ok(body):
		if len(body) != 17 || body[0] != wireAckTag {
			return result.Err[Acknowledgement, Failure](MalformedPacket("invalid challenge acknowledgement"))
		}
		var digest [16]byte
		copy(digest[:], body[1:])
		return result.Ok[Acknowledgement, Failure](Acknowledgement{Digest: digest})
	}
}

func encodeNodeTail(node Node) result.Result[[]byte, Failure] {
	match validateWireNode(node) {
	case result.Err(failure): return result.Err[[]byte, Failure](failure)
	case result.Ok(_):
	}
	name := []byte(node.Name)
	tail := make([]byte, 8+4+2+len(name))
	binary.BigEndian.PutUint64(tail[0:8], node.Flags)
	binary.BigEndian.PutUint32(tail[8:12], node.Creation)
	binary.BigEndian.PutUint16(tail[12:14], uint16(len(name)))
	copy(tail[14:], name)
	return result.Ok[[]byte, Failure](tail)
}

func decodeNodeTail(tail []byte) result.Result[Node, Failure] {
	if len(tail) < 14 {
		return result.Err[Node, Failure](MalformedPacket("node fields are truncated"))
	}
	length := int(binary.BigEndian.Uint16(tail[12:14]))
	if length > len(tail)-14 {
		return result.Err[Node, Failure](MalformedPacket("node name is truncated"))
	}
	node := Node{
		Flags: binary.BigEndian.Uint64(tail[0:8]),
		Creation: binary.BigEndian.Uint32(tail[8:12]),
		Name: string(tail[14:14+length]),
	}
	match validateWireNode(node) {
	case result.Err(failure): return result.Err[Node, Failure](failure)
	case result.Ok(_): return result.Ok[Node, Failure](node)
	}
}

func validateWireNode(node Node) result.Result[bool, Failure] {
	if node.Name == "" || len([]byte(node.Name)) > math.MaxUint16 {
		return result.Err[bool, Failure](InvalidNode(node.Name))
	}
	match term.Atom(node.Name) {
	case result.Err(_): return result.Err[bool, Failure](InvalidNode(node.Name))
	case result.Ok(_): return result.Ok[bool, Failure](true)
	}
}
