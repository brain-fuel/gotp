package distribution

import (
	"fmt"
	"math/big"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type ControlCode enum {
	LinkCode()
	SendCode()
	ExitCode()
	NodeLinkCode()
	RegisteredSendCode()
	GroupLeaderCode()
	Exit2Code()
	SendTraceCode()
	ExitTraceCode()
	RegisteredSendTraceCode()
	Exit2TraceCode()
	MonitorCode()
	DemonitorCode()
	MonitorExitCode()
	SendSenderCode()
	SendSenderTraceCode()
	PayloadExitCode()
	PayloadExitTraceCode()
	PayloadExit2Code()
	PayloadExit2TraceCode()
	PayloadMonitorExitCode()
	SpawnRequestCode()
	SpawnRequestTraceCode()
	SpawnReplyCode()
	SpawnReplyTraceCode()
	AliasSendCode()
	AliasSendTraceCode()
	UnlinkIDCode()
	UnlinkIDAckCode()
}

type PayloadRule enum {
	PayloadForbidden()
	PayloadRequired()
}

type Control struct {
	code   ControlCode
	fields []term.Term
}

func (control Control) Code() ControlCode { return control.code }

func (control Control) Number() uint8 { return controlNumber(control.code) }

func (control Control) Fields() []term.Term {
	fields := make([]term.Term, len(control.fields))
	for index, field := range control.fields { fields[index] = field.Clone() }
	return fields
}

func NewControl(code ControlCode, fields ...term.Term) result.Result[Control, Failure] {
	match validateControl(code, fields) {
	case result.Err(failure): return result.Err[Control, Failure](failure)
	case result.Ok(_):
		cloned := make([]term.Term, len(fields))
		for index, field := range fields { cloned[index] = field.Clone() }
		return result.Ok[Control, Failure](Control{code: code, fields: cloned})
	}
}

// assayxport:unit gotp.distribution.control-messages
func DecodeControl(value term.Term) result.Result[Control, Failure] {
	match value {
	case term.TupleTerm(elements):
		if len(elements) == 0 {
			return result.Err[Control, Failure](InvalidControl("tuple is empty"))
		}
		match controlCode(elements[0]) {
		case result.Err(failure): return result.Err[Control, Failure](failure)
		case result.Ok(code): return NewControl(code, elements[1:]...)
		}
	case _:
		return result.Err[Control, Failure](InvalidControl("value is not a tuple"))
	}
}

func EncodeControl(control Control) result.Result[term.Term, Failure] {
	match validateControl(control.code, control.fields) {
	case result.Err(failure): return result.Err[term.Term, Failure](failure)
	case result.Ok(_):
		elements := []term.Term{term.Integer(int64(controlNumber(control.code)))}
		for _, field := range control.fields { elements = append(elements, field.Clone()) }
		return result.Ok[term.Term, Failure](term.Tuple(elements...))
	}
}

func ValidatePayload(control Control, payload option.Option[term.Term]) result.Result[bool, Failure] {
	rule := payloadRule(control.code)
	match rule {
	case PayloadForbidden:
		match payload {
		case option.None: return result.Ok[bool, Failure](true)
		case option.Some(_): return result.Err[bool, Failure](InvalidControl("opcode forbids a payload"))
		}
	case PayloadRequired:
		match payload {
		case option.None: return result.Err[bool, Failure](InvalidControl("opcode requires a payload"))
		case option.Some(value):
			match control.code {
			case SpawnRequestCode:
				return requireProperListValue(value, "spawn argument payload")
			case SpawnRequestTraceCode:
				return requireProperListValue(value, "spawn argument payload")
			case _:
				return result.Ok[bool, Failure](true)
			}
		}
	}
}

func validateControl(code ControlCode, fields []term.Term) result.Result[bool, Failure] {
	want := controlArity(code)
	if len(fields) != want {
		return result.Err[bool, Failure](InvalidControl(fmt.Sprintf(
			"opcode %d has %d fields; want %d", controlNumber(code), len(fields), want,
		)))
	}
	match validateKinds(code, fields) {
	case result.Err(failure): return result.Err[bool, Failure](failure)
	case result.Ok(_): return result.Ok[bool, Failure](true)
	}
}

func validateKinds(code ControlCode, fields []term.Term) result.Result[bool, Failure] {
	match code {
	case NodeLinkCode: return valid()
	case LinkCode:
		return requirePIDs(fields, 0, 1)
	case GroupLeaderCode:
		return requirePIDs(fields, 0, 1)
	case SendSenderCode:
		return requirePIDs(fields, 0, 1)
	case PayloadExitCode:
		return requirePIDs(fields, 0, 1)
	case PayloadExit2Code:
		return requirePIDs(fields, 0, 1)
	case SendCode:
		return requirePIDs(fields, 1)
	case ExitCode:
		return requirePIDs(fields, 0, 1)
	case Exit2Code:
		return requirePIDs(fields, 0, 1)
	case RegisteredSendCode:
		match requirePIDs(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_): return requireAtom(fields, 2)
		}
	case SendTraceCode:
		return requirePIDs(fields, 1)
	case ExitTraceCode:
		return requirePIDs(fields, 0, 1)
	case Exit2TraceCode:
		return requirePIDs(fields, 0, 1)
	case RegisteredSendTraceCode:
		match requirePIDs(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_): return requireAtom(fields, 2)
		}
	case MonitorCode:
		match requirePIDs(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_):
			match requireProcessTarget(fields, 1) {
			case result.Err(failure): return result.Err[bool, Failure](failure)
			case result.Ok(_): return requireReference(fields, 2)
			}
		}
	case DemonitorCode:
		match requirePIDs(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_):
			match requireProcessTarget(fields, 1) {
			case result.Err(failure): return result.Err[bool, Failure](failure)
			case result.Ok(_): return requireReference(fields, 2)
			}
		}
	case MonitorExitCode:
		match requireProcessTarget(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_):
			match requirePIDs(fields, 1) {
			case result.Err(failure): return result.Err[bool, Failure](failure)
			case result.Ok(_): return requireReference(fields, 2)
			}
		}
	case SendSenderTraceCode:
		return requirePIDs(fields, 0, 1)
	case PayloadExitTraceCode:
		return requirePIDs(fields, 0, 1)
	case PayloadExit2TraceCode:
		return requirePIDs(fields, 0, 1)
	case PayloadMonitorExitCode:
		match requireProcessTarget(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_):
			match requirePIDs(fields, 1) {
			case result.Err(failure): return result.Err[bool, Failure](failure)
			case result.Ok(_): return requireReference(fields, 2)
			}
		}
	case SpawnRequestCode:
		return validateSpawnRequest(fields)
	case SpawnRequestTraceCode:
		return validateSpawnRequest(fields)
	case SpawnReplyCode:
		return validateSpawnReply(fields)
	case SpawnReplyTraceCode:
		return validateSpawnReply(fields)
	case AliasSendCode:
		match requirePIDs(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_): return requireReference(fields, 1)
		}
	case AliasSendTraceCode:
		match requirePIDs(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_): return requireReference(fields, 1)
		}
	case UnlinkIDCode:
		match requireUnlinkID(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_): return requirePIDs(fields, 1, 2)
		}
	case UnlinkIDAckCode:
		match requireUnlinkID(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_): return requirePIDs(fields, 1, 2)
		}
	}
}

func validateSpawnRequest(fields []term.Term) result.Result[bool, Failure] {
		match requireReference(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_):
			match requirePIDs(fields, 1, 2) {
			case result.Err(failure): return result.Err[bool, Failure](failure)
			case result.Ok(_):
				match requireMFA(fields, 3) {
				case result.Err(failure): return result.Err[bool, Failure](failure)
				case result.Ok(_): return requireProperList(fields, 4)
				}
			}
		}
}

func validateSpawnReply(fields []term.Term) result.Result[bool, Failure] {
		match requireReference(fields, 0) {
		case result.Err(failure): return result.Err[bool, Failure](failure)
		case result.Ok(_):
			match requirePIDs(fields, 1) {
			case result.Err(failure): return result.Err[bool, Failure](failure)
			case result.Ok(_):
				match requireSpawnFlags(fields, 2) {
				case result.Err(failure): return result.Err[bool, Failure](failure)
				case result.Ok(_): return requireProcessTarget(fields, 3)
				}
			}
		}
}

func valid() result.Result[bool, Failure] { return result.Ok[bool, Failure](true) }

func requirePIDs(fields []term.Term, indexes ...int) result.Result[bool, Failure] {
	for _, index := range indexes {
		match fields[index] {
		case term.PIDTerm(pid):
			if !pid.Valid() { return invalidField(index, "invalid pid") }
		case _: return invalidField(index, "expected pid")
		}
	}
	return valid()
}

func requireAtom(fields []term.Term, index int) result.Result[bool, Failure] {
	match fields[index] {
	case term.AtomTerm(_): return valid()
	case _: return invalidField(index, "expected atom")
	}
}

func requireProcessTarget(fields []term.Term, index int) result.Result[bool, Failure] {
	match fields[index] {
	case term.AtomTerm(_): return valid()
	case term.PIDTerm(pid):
		if pid.Valid() { return valid() }
		return invalidField(index, "invalid pid target")
	case _: return invalidField(index, "expected pid or atom")
	}
}

func requireReference(fields []term.Term, index int) result.Result[bool, Failure] {
	match fields[index] {
	case term.ReferenceTerm(reference):
		if reference.Valid() { return valid() }
		return invalidField(index, "invalid reference")
	case _: return invalidField(index, "expected reference")
	}
}

func requireMFA(fields []term.Term, index int) result.Result[bool, Failure] {
	match fields[index] {
	case term.TupleTerm(elements):
		if len(elements) != 3 { return invalidField(index, "MFA must have three elements") }
		match elements[0] { case term.AtomTerm(_): case _: return invalidField(index, "MFA module is not an atom") }
		match elements[1] { case term.AtomTerm(_): case _: return invalidField(index, "MFA function is not an atom") }
		match nonnegativeInteger(elements[2]) {
		case option.None: return invalidField(index, "MFA arity is not nonnegative")
		case option.Some(_): return valid()
		}
	case _: return invalidField(index, "expected MFA tuple")
	}
}

func requireSpawnFlags(fields []term.Term, index int) result.Result[bool, Failure] {
	match nonnegativeInteger(fields[index]) {
	case option.None: return invalidField(index, "spawn flags are not nonnegative")
	case option.Some(flags):
		if flags.BitLen() > 2 { return invalidField(index, "spawn flags contain unknown bits") }
		return valid()
	}
}

func requireProperList(fields []term.Term, index int) result.Result[bool, Failure] {
	return requireProperListValue(fields[index], fmt.Sprintf("field %d", index))
}

func requireProperListValue(value term.Term, location string) result.Result[bool, Failure] {
	match value {
	case term.ProperListTerm(_): return valid()
	case _: return result.Err[bool, Failure](InvalidControl(location + " is not a proper list"))
	}
}

func requireUnlinkID(fields []term.Term, index int) result.Result[bool, Failure] {
	match nonnegativeInteger(fields[index]) {
	case option.None: return invalidField(index, "unlink id is not positive")
	case option.Some(identifier):
		if identifier.Sign() == 0 || !identifier.IsUint64() {
			return invalidField(index, "unlink id is outside 1..2^64-1")
		}
		return valid()
	}
}

func nonnegativeInteger(value term.Term) option.Option[*big.Int] {
	match value {
	case term.IntegerTerm(integer):
		if integer.Sign() >= 0 { return option.Some[*big.Int](new(big.Int).Set(integer)) }
		return option.None[*big.Int]
	case _: return option.None[*big.Int]
	}
}

func invalidField(index int, detail string) result.Result[bool, Failure] {
	return result.Err[bool, Failure](InvalidControl(fmt.Sprintf("field %d: %s", index, detail)))
}

func controlCode(value term.Term) result.Result[ControlCode, Failure] {
	match nonnegativeInteger(value) {
	case option.None: return result.Err[ControlCode, Failure](InvalidControl("opcode is not a nonnegative integer"))
	case option.Some(integer):
		if !integer.IsUint64() { return result.Err[ControlCode, Failure](InvalidControl("opcode is too large")) }
		switch integer.Uint64() {
		case 1: return result.Ok[ControlCode, Failure](LinkCode())
		case 2: return result.Ok[ControlCode, Failure](SendCode())
		case 3: return result.Ok[ControlCode, Failure](ExitCode())
		case 5: return result.Ok[ControlCode, Failure](NodeLinkCode())
		case 6: return result.Ok[ControlCode, Failure](RegisteredSendCode())
		case 7: return result.Ok[ControlCode, Failure](GroupLeaderCode())
		case 8: return result.Ok[ControlCode, Failure](Exit2Code())
		case 12: return result.Ok[ControlCode, Failure](SendTraceCode())
		case 13: return result.Ok[ControlCode, Failure](ExitTraceCode())
		case 16: return result.Ok[ControlCode, Failure](RegisteredSendTraceCode())
		case 18: return result.Ok[ControlCode, Failure](Exit2TraceCode())
		case 19: return result.Ok[ControlCode, Failure](MonitorCode())
		case 20: return result.Ok[ControlCode, Failure](DemonitorCode())
		case 21: return result.Ok[ControlCode, Failure](MonitorExitCode())
		case 22: return result.Ok[ControlCode, Failure](SendSenderCode())
		case 23: return result.Ok[ControlCode, Failure](SendSenderTraceCode())
		case 24: return result.Ok[ControlCode, Failure](PayloadExitCode())
		case 25: return result.Ok[ControlCode, Failure](PayloadExitTraceCode())
		case 26: return result.Ok[ControlCode, Failure](PayloadExit2Code())
		case 27: return result.Ok[ControlCode, Failure](PayloadExit2TraceCode())
		case 28: return result.Ok[ControlCode, Failure](PayloadMonitorExitCode())
		case 29: return result.Ok[ControlCode, Failure](SpawnRequestCode())
		case 30: return result.Ok[ControlCode, Failure](SpawnRequestTraceCode())
		case 31: return result.Ok[ControlCode, Failure](SpawnReplyCode())
		case 32: return result.Ok[ControlCode, Failure](SpawnReplyTraceCode())
		case 33: return result.Ok[ControlCode, Failure](AliasSendCode())
		case 34: return result.Ok[ControlCode, Failure](AliasSendTraceCode())
		case 35: return result.Ok[ControlCode, Failure](UnlinkIDCode())
		case 36: return result.Ok[ControlCode, Failure](UnlinkIDAckCode())
		default: return result.Err[ControlCode, Failure](InvalidControl(fmt.Sprintf("unsupported opcode %d", integer.Uint64())))
		}
	}
}

func controlNumber(code ControlCode) uint8 {
	match code {
	case LinkCode: return 1
	case SendCode: return 2
	case ExitCode: return 3
	case NodeLinkCode: return 5
	case RegisteredSendCode: return 6
	case GroupLeaderCode: return 7
	case Exit2Code: return 8
	case SendTraceCode: return 12
	case ExitTraceCode: return 13
	case RegisteredSendTraceCode: return 16
	case Exit2TraceCode: return 18
	case MonitorCode: return 19
	case DemonitorCode: return 20
	case MonitorExitCode: return 21
	case SendSenderCode: return 22
	case SendSenderTraceCode: return 23
	case PayloadExitCode: return 24
	case PayloadExitTraceCode: return 25
	case PayloadExit2Code: return 26
	case PayloadExit2TraceCode: return 27
	case PayloadMonitorExitCode: return 28
	case SpawnRequestCode: return 29
	case SpawnRequestTraceCode: return 30
	case SpawnReplyCode: return 31
	case SpawnReplyTraceCode: return 32
	case AliasSendCode: return 33
	case AliasSendTraceCode: return 34
	case UnlinkIDCode: return 35
	case UnlinkIDAckCode: return 36
	}
}

func controlArity(code ControlCode) int {
	match code {
	case NodeLinkCode: return 0
	case LinkCode: return 2
	case GroupLeaderCode: return 2
	case SendSenderCode: return 2
	case PayloadExitCode: return 2
	case PayloadExit2Code: return 2
	case AliasSendCode: return 2
	case SendCode: return 2
	case ExitCode: return 3
	case RegisteredSendCode: return 3
	case Exit2Code: return 3
	case SendTraceCode: return 3
	case MonitorCode: return 3
	case DemonitorCode: return 3
	case SendSenderTraceCode: return 3
	case PayloadExitTraceCode: return 3
	case PayloadExit2TraceCode: return 3
	case PayloadMonitorExitCode: return 3
	case AliasSendTraceCode: return 3
	case UnlinkIDCode: return 3
	case UnlinkIDAckCode: return 3
	case ExitTraceCode: return 4
	case RegisteredSendTraceCode: return 4
	case Exit2TraceCode: return 4
	case MonitorExitCode: return 4
	case SpawnReplyCode: return 4
	case SpawnRequestCode: return 5
	case SpawnReplyTraceCode: return 5
	case SpawnRequestTraceCode: return 6
	}
}

func payloadRule(code ControlCode) PayloadRule {
	match code {
	case SendCode: return PayloadRequired()
	case RegisteredSendCode: return PayloadRequired()
	case SendTraceCode: return PayloadRequired()
	case RegisteredSendTraceCode: return PayloadRequired()
	case SendSenderCode: return PayloadRequired()
	case SendSenderTraceCode: return PayloadRequired()
	case PayloadExitCode: return PayloadRequired()
	case PayloadExitTraceCode: return PayloadRequired()
	case PayloadExit2Code: return PayloadRequired()
	case PayloadExit2TraceCode: return PayloadRequired()
	case PayloadMonitorExitCode: return PayloadRequired()
	case SpawnRequestCode: return PayloadRequired()
	case SpawnRequestTraceCode: return PayloadRequired()
	case AliasSendCode: return PayloadRequired()
	case AliasSendTraceCode: return PayloadRequired()
	case _:
		return PayloadForbidden()
	}
}
