package etf

import (
	"fmt"

	"goforge.dev/gotp/term"
)

// Failure is the closed set of failures produced by ETF codecs. Keeping this
// algebra closed makes failure handling exhaustive in Go+ while the generated
// Go remains usable by ordinary Go tooling.
type Failure enum {
	Invalid(Area string, Detail string)
	LimitExceeded(Resource string, Actual int, Limit int)
	MissingVersion()
	TrailingBytes(Count int)
	UnsupportedTag(Tag byte, Offset int)
	Truncated(Offset int, Need int)
	ResolverRequired()
	UnknownNodeID(ID uint32)
	UnknownNodeName(Name string)
	Foreign(Operation string, Cause error)
	TermRejected(Cause term.ValidationFailure)
}

func (failure Failure) Error() string {
	match failure {
	case Invalid(area, detail):
		return fmt.Sprintf("gotp/etf: invalid %s: %s", area, detail)
	case LimitExceeded(resource, actual, limit):
		return fmt.Sprintf("gotp/etf: %s size %d exceeds limit %d", resource, actual, limit)
	case MissingVersion:
		return fmt.Sprintf("gotp/etf: missing external term version %d", Version)
	case TrailingBytes(count):
		return fmt.Sprintf("gotp/etf: %d trailing bytes", count)
	case UnsupportedTag(tag, offset):
		return fmt.Sprintf("gotp/etf: unsupported tag %d at byte %d", tag, offset)
	case Truncated(offset, need):
		return fmt.Sprintf("gotp/etf: truncated input at byte %d; need %d bytes", offset, need)
	case ResolverRequired:
		return "gotp/etf: identifier requires a node resolver"
	case UnknownNodeID(id):
		return fmt.Sprintf("gotp/etf: unknown node ID %d", id)
	case UnknownNodeName(name):
		return fmt.Sprintf("gotp/etf: unknown node name %q", name)
	case Foreign(operation, cause):
		return fmt.Sprintf("gotp/etf: %s: %v", operation, cause)
	case TermRejected(cause):
		return fmt.Sprintf("gotp/etf: term rejected: %s", cause.Error())
	}
}
