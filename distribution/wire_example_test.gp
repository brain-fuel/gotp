package distribution

import (
	"bytes"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
)

// assayxport:unit gotp.distribution.handshake-wire-laws
func TestSendNameMatchesOTPVersionSixLayout(t *testing.T) {
	node := Node{Name: "a@b", Flags: 0x0102030405060708, Creation: 0x090a0b0c}
	match EncodeSendName(node) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(packet):
		want := []byte{
			0, 18, 'N', 1, 2, 3, 4, 5, 6, 7, 8,
			9, 10, 11, 12, 0, 3, 'a', '@', 'b',
		}
		if !bytes.Equal(packet, want) { t.Fatalf("packet = %x, want %x", packet, want) }
	}
}

func TestHandshakeWireRoundTrips(t *testing.T) {
	node := Node{Name: "client@local", Flags: 1<<36 | 1<<35, Creation: 17}
	match EncodeChallenge(node, 0x01020304) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(packet):
		packet = append(packet, 0xaa)
		packet[1]++
		match DecodeChallenge(packet) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(decoded):
			if decoded.Node != node || decoded.Challenge != 0x01020304 {
				t.Fatalf("decoded = %#v", decoded)
			}
		}
	}
	for _, status := range []Status{
		StatusOK(), StatusOKSimultaneous(), StatusNOK(), StatusNotAllowed(),
		StatusAlive(), StatusContinue(true), StatusContinue(false),
		StatusNamed(Node{Name: "dynamic@local", Creation: 99}),
	} {
		match EncodeStatus(status) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(packet):
			match DecodeStatus(packet) {
			case result.Err(failure): t.Fatal(failure.Error())
			case result.Ok(decoded):
				if decoded != status { t.Fatalf("status = %#v, want %#v", decoded, status) }
			}
		}
	}
}

func TestPacketFramingClonesAndSupportsTicks(t *testing.T) {
	payload := []byte{1, 2, 3}
	match EncodePacket4(payload) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(packet):
		payload[0] = 9
		match DecodePacket4(packet) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(decoded):
			if !bytes.Equal(decoded, []byte{1, 2, 3}) { t.Fatalf("decoded = %v", decoded) }
			decoded[0] = 8
			if packet[4] != 1 { t.Fatal("decode aliased packet") }
		}
	}
	match DecodePacket4([]byte{0, 0, 0, 0}) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(tick): if len(tick) != 0 { t.Fatalf("tick = %v", tick) }
	}
}

func TestWireDecodersNeverPanic(t *testing.T) {
	law := func(raw []byte) bool {
		if len(raw) > 512 { raw = raw[:512] }
		DecodePacket2(raw)
		DecodePacket4(raw)
		DecodeSendName(raw)
		DecodeChallenge(raw)
		DecodeStatus(raw)
		DecodeComplement(raw)
		DecodeReply(raw)
		DecodeAcknowledgement(raw)
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2_000})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}

func TestExactMessagesRejectTrailingBytes(t *testing.T) {
	match EncodeComplement(Complement{FlagsHigh: 1, Creation: 2}) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(packet):
		packet = append(packet, 0)
		packet[1]++
		match DecodeComplement(packet) {
		case result.Err(_):
		case result.Ok(_): t.Fatal("extended complement was accepted")
		}
	}
}
