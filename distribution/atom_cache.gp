package distribution

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"sync"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

const (
	distributionVersion byte = 131
	distributionHeaderTag byte = 68
	atomCacheSegments = 8
	atomCacheSegmentSize = 256
	atomCacheSize = atomCacheSegments * atomCacheSegmentSize
)

type AtomReference struct {
	Segment  uint8
	Internal uint8
	NewAtom  option.Option[string]
}

type DecodedHeader struct {
	Atoms         []string
	BytesConsumed int
}

type AtomCache struct {
	mu      sync.Mutex
	atoms   [atomCacheSize]string
	present [atomCacheSize]bool
}

func NewAtomCache() *AtomCache {
	return &AtomCache{}
}

// assayxport:unit gotp.distribution.atom-cache-header
func (cache *AtomCache) EncodeHeader(references []AtomReference) result.Result[[]byte, Failure] {
	if len(references) > 255 {
		return result.Err[[]byte, Failure](PacketTooLarge(uint64(len(references))))
	}
	cache.mu.Lock()
	defer cache.mu.Unlock()
	atoms := cache.atoms
	present := cache.present
	longAtoms := false
	for _, reference := range references {
		match validateReference(reference, &atoms, &present) {
		case result.Err(failure):
			return result.Err[[]byte, Failure](failure)
		case result.Ok(length):
			if length > 255 { longAtoms = true }
		}
	}
	if len(references) == 0 {
		return result.Ok[[]byte, Failure]([]byte{distributionVersion, distributionHeaderTag, 0})
	}
	flagBytes := len(references)/2 + 1
	flags := make([]byte, flagBytes)
	if longAtoms { setNibble(flags, len(references), 1) }
	body := make([]byte, 0, 3+flagBytes+len(references)*2)
	body = append(body, distributionVersion, distributionHeaderTag, byte(len(references)))
	for index, reference := range references {
		nibble := reference.Segment
		match reference.NewAtom {
		case option.Some(_): nibble |= 8
		case option.None:
		}
		setNibble(flags, index, nibble)
	}
	body = append(body, flags...)
	for _, reference := range references {
		body = append(body, reference.Internal)
		match reference.NewAtom {
		case option.None:
		case option.Some(name):
			raw := []byte(name)
			if longAtoms {
				var length [2]byte
				binary.BigEndian.PutUint16(length[:], uint16(len(raw)))
				body = append(body, length[:]...)
			} else {
				body = append(body, byte(len(raw)))
			}
			body = append(body, raw...)
		}
	}
	cache.atoms = atoms
	cache.present = present
	return result.Ok[[]byte, Failure](bytes.Clone(body))
}

func (cache *AtomCache) DecodeHeader(encoded []byte) result.Result[DecodedHeader, Failure] {
	cache.mu.Lock()
	defer cache.mu.Unlock()
	if len(encoded) < 3 || encoded[0] != distributionVersion || encoded[1] != distributionHeaderTag {
		return result.Err[DecodedHeader, Failure](MalformedPacket("invalid distribution header"))
	}
	count := int(encoded[2])
	if count == 0 {
		return result.Ok[DecodedHeader, Failure](DecodedHeader{Atoms: []string{}, BytesConsumed: 3})
	}
	flagBytes := count/2 + 1
	if len(encoded) < 3+flagBytes {
		return result.Err[DecodedHeader, Failure](MalformedPacket("atom-cache flags are truncated"))
	}
	flags := encoded[3:3+flagBytes]
	longAtoms := nibble(flags, count)&1 != 0
	position := 3+flagBytes
	atoms := cache.atoms
	present := cache.present
	resolved := make([]string, count)
	for index := 0; index < count; index++ {
		flag := nibble(flags, index)
		segment := flag & 7
		fresh := flag&8 != 0
		if position >= len(encoded) {
			return result.Err[DecodedHeader, Failure](MalformedPacket("atom-cache reference is truncated"))
		}
		internal := encoded[position]
		position++
		location := cacheLocation(segment, internal)
		if fresh {
			lengthBytes := 1
			if longAtoms { lengthBytes = 2 }
			if len(encoded)-position < lengthBytes {
				return result.Err[DecodedHeader, Failure](MalformedPacket("atom length is truncated"))
			}
			length := int(encoded[position])
			if longAtoms { length = int(binary.BigEndian.Uint16(encoded[position:position+2])) }
			position += lengthBytes
			if length > len(encoded)-position {
				return result.Err[DecodedHeader, Failure](MalformedPacket("atom text is truncated"))
			}
			name := string(encoded[position:position+length])
			position += length
			match term.Atom(name) {
			case result.Err(_):
				return result.Err[DecodedHeader, Failure](MalformedPacket("atom text is invalid"))
			case result.Ok(_):
			}
			atoms[location] = name
			present[location] = true
		} else if !present[location] {
			return result.Err[DecodedHeader, Failure](MalformedPacket(fmt.Sprintf(
				"atom-cache entry %d:%d is undefined", segment, internal,
			)))
		}
		resolved[index] = atoms[location]
	}
	cache.atoms = atoms
	cache.present = present
	return result.Ok[DecodedHeader, Failure](DecodedHeader{
		Atoms: append([]string{}, resolved...), BytesConsumed: position,
	})
}

func validateReference(
	reference AtomReference,
	atoms *[atomCacheSize]string,
	present *[atomCacheSize]bool,
) result.Result[int, Failure] {
	if reference.Segment >= atomCacheSegments {
		return result.Err[int, Failure](MalformedPacket("atom-cache segment exceeds seven"))
	}
	location := cacheLocation(reference.Segment, reference.Internal)
	match reference.NewAtom {
	case option.None:
		if !present[location] {
			return result.Err[int, Failure](MalformedPacket("atom-cache reference is undefined"))
		}
		return result.Ok[int, Failure](0)
	case option.Some(name):
		match term.Atom(name) {
		case result.Err(_):
			return result.Err[int, Failure](MalformedPacket("new atom is invalid"))
		case result.Ok(_):
		}
		raw := []byte(name)
		if len(raw) > 65535 {
			return result.Err[int, Failure](PacketTooLarge(uint64(len(raw))))
		}
		atoms[location] = name
		present[location] = true
		return result.Ok[int, Failure](len(raw))
	}
}

func cacheLocation(segment uint8, internal uint8) int {
	return int(segment)*atomCacheSegmentSize + int(internal)
}

func setNibble(flags []byte, index int, value uint8) {
	position := index/2
	if index%2 == 0 {
		flags[position] = flags[position]&0xf0 | value&0x0f
	} else {
		flags[position] = flags[position]&0x0f | value<<4
	}
}

func nibble(flags []byte, index int) uint8 {
	value := flags[index/2]
	if index%2 == 0 { return value & 0x0f }
	return value >> 4
}
