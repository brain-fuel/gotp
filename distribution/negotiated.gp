package distribution

import (
	"sync"

	"goforge.dev/goplus/std/result"
)

const (
	DFlagDistributionHeader uint64 = 0x2000
	DFlagSendSender         uint64 = 0x80000
	DFlagExitPayload        uint64 = 0x400000
	DFlagFragments          uint64 = 0x800000
	DFlagHandshake23        uint64 = 0x1000000
	DFlagUnlinkID           uint64 = 0x2000000
	DFlagSpawn              uint64 = 1 << 32
	DFlagNameMe             uint64 = 1 << 33
	DFlagV4NC               uint64 = 1 << 34
	DFlagAlias              uint64 = 1 << 35
	DFlagMandatory25Digest  uint64 = 1 << 36
)

type senderMode enum {
	LegacySenderAllowed()
	ExplicitSenderObserved()
}

type exitMode enum {
	EmbeddedExitAllowed()
	PayloadExitObserved()
}

type NegotiatedPolicy struct {
	mu         sync.Mutex
	flags      uint64
	senderMode senderMode
	exitMode   exitMode
}

func NewNegotiatedPolicy(flags uint64) *NegotiatedPolicy {
	return &NegotiatedPolicy{
		flags: flags,
		senderMode: LegacySenderAllowed(),
		exitMode: EmbeddedExitAllowed(),
	}
}

func (policy *NegotiatedPolicy) Flags() uint64 {
	policy.mu.Lock()
	defer policy.mu.Unlock()
	return policy.flags
}

// assayxport:unit gotp.distribution.negotiated-controls
func (policy *NegotiatedPolicy) Accept(control Control) result.Result[bool, Failure] {
	policy.mu.Lock()
	defer policy.mu.Unlock()
	nextSender := policy.senderMode
	nextExit := policy.exitMode
	match validateFeature(policy.flags, control.code) {
	case result.Err(failure): return result.Err[bool, Failure](failure)
	case result.Ok(_):
	}
	match control.code {
	case SendSenderCode:
		nextSender = ExplicitSenderObserved()
	case SendSenderTraceCode:
		nextSender = ExplicitSenderObserved()
	case SendCode:
		match policy.senderMode {
		case ExplicitSenderObserved:
			return result.Err[bool, Failure](InvalidControl("legacy SEND after SEND_SENDER transition"))
		case LegacySenderAllowed:
		}
	case SendTraceCode:
		match policy.senderMode {
		case ExplicitSenderObserved:
			return result.Err[bool, Failure](InvalidControl("legacy SEND_TT after SEND_SENDER transition"))
		case LegacySenderAllowed:
		}
	case PayloadExitCode:
		nextExit = PayloadExitObserved()
	case PayloadExitTraceCode:
		nextExit = PayloadExitObserved()
	case PayloadExit2Code:
		nextExit = PayloadExitObserved()
	case PayloadExit2TraceCode:
		nextExit = PayloadExitObserved()
	case PayloadMonitorExitCode:
		nextExit = PayloadExitObserved()
	case ExitCode:
		match policy.exitMode {
		case PayloadExitObserved:
			return result.Err[bool, Failure](InvalidControl("embedded EXIT after payload transition"))
		case EmbeddedExitAllowed:
		}
	case ExitTraceCode:
		match policy.exitMode {
		case PayloadExitObserved:
			return result.Err[bool, Failure](InvalidControl("embedded EXIT_TT after payload transition"))
		case EmbeddedExitAllowed:
		}
	case Exit2Code:
		match policy.exitMode {
		case PayloadExitObserved:
			return result.Err[bool, Failure](InvalidControl("embedded EXIT2 after payload transition"))
		case EmbeddedExitAllowed:
		}
	case Exit2TraceCode:
		match policy.exitMode {
		case PayloadExitObserved:
			return result.Err[bool, Failure](InvalidControl("embedded EXIT2_TT after payload transition"))
		case EmbeddedExitAllowed:
		}
	case MonitorExitCode:
		match policy.exitMode {
		case PayloadExitObserved:
			return result.Err[bool, Failure](InvalidControl("embedded MONITOR_P_EXIT after payload transition"))
		case EmbeddedExitAllowed:
		}
	case _:
	}
	policy.senderMode = nextSender
	policy.exitMode = nextExit
	return result.Ok[bool, Failure](true)
}

func validateFeature(flags uint64, code ControlCode) result.Result[bool, Failure] {
	match code {
	case SendSenderCode:
		return requireFlag(flags, DFlagSendSender, "SEND_SENDER")
	case SendSenderTraceCode:
		return requireFlag(flags, DFlagSendSender, "SEND_SENDER_TT")
	case PayloadExitCode:
		return requireFlag(flags, DFlagExitPayload, "PAYLOAD_EXIT")
	case PayloadExitTraceCode:
		return requireFlag(flags, DFlagExitPayload, "PAYLOAD_EXIT_TT")
	case PayloadExit2Code:
		return requireFlag(flags, DFlagExitPayload, "PAYLOAD_EXIT2")
	case PayloadExit2TraceCode:
		return requireFlag(flags, DFlagExitPayload, "PAYLOAD_EXIT2_TT")
	case PayloadMonitorExitCode:
		return requireFlag(flags, DFlagExitPayload, "PAYLOAD_MONITOR_P_EXIT")
	case SpawnRequestCode:
		return requireFlag(flags, DFlagSpawn, "SPAWN_REQUEST")
	case SpawnRequestTraceCode:
		return requireFlag(flags, DFlagSpawn, "SPAWN_REQUEST_TT")
	case SpawnReplyCode:
		return requireFlag(flags, DFlagSpawn, "SPAWN_REPLY")
	case SpawnReplyTraceCode:
		return requireFlag(flags, DFlagSpawn, "SPAWN_REPLY_TT")
	case AliasSendCode:
		return requireFlag(flags, DFlagAlias, "ALIAS_SEND")
	case AliasSendTraceCode:
		return requireFlag(flags, DFlagAlias, "ALIAS_SEND_TT")
	case UnlinkIDCode:
		return requireFlag(flags, DFlagUnlinkID, "UNLINK_ID")
	case UnlinkIDAckCode:
		return requireFlag(flags, DFlagUnlinkID, "UNLINK_ID_ACK")
	case _:
		return result.Ok[bool, Failure](true)
	}
}

func requireFlag(flags uint64, required uint64, operation string) result.Result[bool, Failure] {
	if flags&required == 0 {
		return result.Err[bool, Failure](InvalidControl(operation + " was not negotiated"))
	}
	return result.Ok[bool, Failure](true)
}
