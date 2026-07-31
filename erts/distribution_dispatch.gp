package erts

import (
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/distribution"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

type DistributionDispatchFailure enum {
	NilDistributionKernel()
	InvalidDistributionField(Detail string)
	DistributionKernelRejected(Cause string)
}

func (failure DistributionDispatchFailure) Error() string {
	match failure {
	case NilDistributionKernel:
		return "gotp/erts: distribution kernel is nil"
	case InvalidDistributionField(detail):
		return "gotp/erts: invalid validated distribution field: " + detail
	case DistributionKernelRejected(cause):
		return "gotp/erts: distribution kernel rejected operation: " + cause
	}
}

type DistributionDispatch enum {
	DistributionApplied()
	DistributionDestinationMissing()
	DistributionUnlinkAcknowledgement(ID term.Term, From term.PID, To term.PID)
	DistributionDeferred(Opcode uint8)
}

// assayxport:unit gotp.erts.distribution-dispatch
func DispatchDistribution(
	runtime *kernel.Kernel,
	frame distribution.TypedConnectedFrame,
) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	if runtime == nil {
		return result.Err[DistributionDispatch, DistributionDispatchFailure](NilDistributionKernel())
	}
	match frame {
	case distribution.TypedTick:
		return result.Ok[DistributionDispatch, DistributionDispatchFailure](DistributionApplied())
	case distribution.TypedSignal(control, payload):
		return dispatchControl(runtime, control, payload)
	}
}

func dispatchControl(
	runtime *kernel.Kernel,
	control distribution.Control,
	payload option.Option[term.Term],
) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	fields := control.Fields()
	match control.Code() {
	case distribution.LinkCode:
		return dispatchLink(runtime, fields)
	case distribution.SendCode:
		return dispatchSend(runtime, term.InvalidValue(), fields[1], payload)
	case distribution.ExitCode:
		return dispatchExit(runtime, fields[0], fields[1], option.Some[term.Term](fields[2]))
	case distribution.NodeLinkCode:
		return deferred(control)
	case distribution.RegisteredSendCode:
		return dispatchRegisteredSend(runtime, fields, payload)
	case distribution.GroupLeaderCode:
		return dispatchGroupLeader(runtime, fields)
	case distribution.Exit2Code:
		return dispatchExit(runtime, fields[0], fields[1], option.Some[term.Term](fields[2]))
	case distribution.SendTraceCode:
		return deferred(control)
	case distribution.ExitTraceCode:
		return deferred(control)
	case distribution.RegisteredSendTraceCode:
		return deferred(control)
	case distribution.Exit2TraceCode:
		return deferred(control)
	case distribution.MonitorCode:
		return dispatchMonitor(runtime, fields)
	case distribution.DemonitorCode:
		return dispatchDemonitor(runtime, fields)
	case distribution.MonitorExitCode:
		return dispatchDown(runtime, control, fields[0], fields[1], fields[2], option.Some[term.Term](fields[3]))
	case distribution.SendSenderCode:
		return dispatchSend(runtime, fields[0], fields[1], payload)
	case distribution.SendSenderTraceCode:
		return deferred(control)
	case distribution.PayloadExitCode:
		return dispatchExit(runtime, fields[0], fields[1], payload)
	case distribution.PayloadExitTraceCode:
		return deferred(control)
	case distribution.PayloadExit2Code:
		return dispatchExit(runtime, fields[0], fields[1], payload)
	case distribution.PayloadExit2TraceCode:
		return deferred(control)
	case distribution.PayloadMonitorExitCode:
		return dispatchDown(runtime, control, fields[0], fields[1], fields[2], payload)
	case distribution.SpawnRequestCode:
		return deferred(control)
	case distribution.SpawnRequestTraceCode:
		return deferred(control)
	case distribution.SpawnReplyCode:
		return deferred(control)
	case distribution.SpawnReplyTraceCode:
		return deferred(control)
	case distribution.AliasSendCode:
		return dispatchAlias(runtime, fields, payload)
	case distribution.AliasSendTraceCode:
		return deferred(control)
	case distribution.UnlinkIDCode:
		return dispatchUnlink(runtime, control, fields)
	case distribution.UnlinkIDAckCode:
		return dispatchUnlinkAcknowledgement(runtime, fields)
	}
}

func dispatchLink(runtime *kernel.Kernel, fields []term.Term) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	match twoPIDs(fields[0], fields[1]) {
	case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
	case result.Ok(pair):
		match runtime.LinkRemote(pair.From, pair.To) {
		case result.Err(failure): return kernelFailure(failure)
		case result.Ok(_): return applied()
		}
	}
}

func dispatchSend(
	runtime *kernel.Kernel,
	fromValue term.Term,
	toValue term.Term,
	payload option.Option[term.Term],
) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	from := term.PID{}
	match fromValue {
	case term.PIDTerm(pid): from = pid
	case term.InvalidTerm:
	case _: return invalidDispatch("send source is not a pid")
	}
	match pidValue(toValue) {
	case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
	case result.Ok(to):
		match requiredPayload(payload) {
		case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
		case result.Ok(message): return delivery(runtime.Send(from, to, message))
		}
	}
}

func dispatchRegisteredSend(
	runtime *kernel.Kernel,
	fields []term.Term,
	payload option.Option[term.Term],
) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	match pidValue(fields[0]) {
	case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
	case result.Ok(from):
		match atomValue(fields[2]) {
		case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
		case result.Ok(name):
			match requiredPayload(payload) {
			case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
			case result.Ok(message): return delivery(runtime.SendRegistered(from, name, message))
			}
		}
	}
}

func dispatchGroupLeader(runtime *kernel.Kernel, fields []term.Term) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	match twoPIDs(fields[0], fields[1]) {
	case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
	case result.Ok(pair):
		match runtime.SetGroupLeader(pair.From, pair.To) {
		case result.Err(failure): return kernelFailure(failure)
		case result.Ok(_): return applied()
		}
	}
}

func dispatchExit(
	runtime *kernel.Kernel,
	fromValue term.Term,
	toValue term.Term,
	reason option.Option[term.Term],
) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	match twoPIDs(fromValue, toValue) {
	case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
	case result.Ok(pair):
		match requiredPayload(reason) {
		case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
		case result.Ok(value): return delivery(runtime.SendExit(pair.From, pair.To, value))
		}
	}
}

func dispatchMonitor(runtime *kernel.Kernel, fields []term.Term) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	match pidValue(fields[0]) {
	case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
	case result.Ok(watcher):
		match pidValue(fields[1]) {
		case result.Err(_):
			match atomValue(fields[1]) {
			case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
			case result.Ok(name):
				match referenceValue(fields[2]) {
				case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
				case result.Ok(reference):
					match runtime.MonitorRemoteName(watcher, name, reference) {
					case result.Err(failure): return kernelFailure(failure)
					case result.Ok(_): return applied()
					}
				}
			}
		case result.Ok(target):
			match referenceValue(fields[2]) {
			case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
			case result.Ok(reference):
				match runtime.MonitorRemote(watcher, target, reference) {
				case result.Err(failure): return kernelFailure(failure)
				case result.Ok(_): return applied()
				}
			}
		}
	}
}

func dispatchDemonitor(runtime *kernel.Kernel, fields []term.Term) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	match pidValue(fields[0]) {
	case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
	case result.Ok(watcher):
		match pidValue(fields[1]) {
		case result.Err(_):
			match atomValue(fields[1]) {
			case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
			case result.Ok(name):
				match referenceValue(fields[2]) {
				case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
				case result.Ok(reference):
					runtime.DemonitorRemoteName(watcher, name, reference)
					return applied()
				}
			}
		case result.Ok(target):
		match referenceValue(fields[2]) {
		case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
		case result.Ok(reference):
			runtime.DemonitorRemote(watcher, target, reference)
			return applied()
		}
		}
	}
}

func dispatchDown(
	runtime *kernel.Kernel,
	control distribution.Control,
	source term.Term,
	toValue term.Term,
	referenceValueTerm term.Term,
	reason option.Option[term.Term],
) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	match pidValue(source) {
	case result.Err(_):
		match atomValue(source) {
		case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
		case result.Ok(name):
			match pidValue(toValue) {
			case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
			case result.Ok(to):
				match referenceValue(referenceValueTerm) {
				case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
				case result.Ok(reference):
					match requiredPayload(reason) {
					case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
					case result.Ok(value): return delivery(runtime.SendDownNamed(name, to, reference, value))
					}
				}
			}
		}
	case result.Ok(from):
	match pidValue(toValue) {
	case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
	case result.Ok(to):
		match referenceValue(referenceValueTerm) {
		case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
		case result.Ok(reference):
			match requiredPayload(reason) {
			case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
			case result.Ok(value): return delivery(runtime.SendDown(from, to, reference, value))
			}
		}
	}
	}
}

func dispatchAlias(
	runtime *kernel.Kernel,
	fields []term.Term,
	payload option.Option[term.Term],
) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	match pidValue(fields[0]) {
	case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
	case result.Ok(from):
		match referenceValue(fields[1]) {
		case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
		case result.Ok(reference):
			match requiredPayload(payload) {
			case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
			case result.Ok(message): return delivery(runtime.SendAlias(from, reference, message))
			}
		}
	}
}

func dispatchUnlink(
	runtime *kernel.Kernel,
	control distribution.Control,
	fields []term.Term,
) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	match twoPIDs(fields[1], fields[2]) {
	case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
	case result.Ok(pair):
		runtime.UnlinkRemote(pair.From, pair.To)
		return result.Ok[DistributionDispatch, DistributionDispatchFailure](
			DistributionUnlinkAcknowledgement(fields[0].Clone(), pair.To, pair.From),
		)
	}
}

func dispatchUnlinkAcknowledgement(
	runtime *kernel.Kernel,
	fields []term.Term,
) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	match twoPIDs(fields[1], fields[2]) {
	case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
	case result.Ok(pair):
		match uint64Value(fields[0]) {
		case result.Err(failure): return result.Err[DistributionDispatch, DistributionDispatchFailure](failure)
		case result.Ok(identifier):
			runtime.AcknowledgeRemoteUnlink(pair.To, pair.From, identifier)
			return applied()
		}
	}
}

type pidPair struct { From term.PID; To term.PID }

func twoPIDs(from term.Term, to term.Term) result.Result[pidPair, DistributionDispatchFailure] {
	match pidValue(from) {
	case result.Err(failure): return result.Err[pidPair, DistributionDispatchFailure](failure)
	case result.Ok(left):
		match pidValue(to) {
		case result.Err(failure): return result.Err[pidPair, DistributionDispatchFailure](failure)
		case result.Ok(right): return result.Ok[pidPair, DistributionDispatchFailure](pidPair{From: left, To: right})
		}
	}
}

func pidValue(value term.Term) result.Result[term.PID, DistributionDispatchFailure] {
	match value {
	case term.PIDTerm(pid): return result.Ok[term.PID, DistributionDispatchFailure](pid)
	case _: return result.Err[term.PID, DistributionDispatchFailure](InvalidDistributionField("expected pid"))
	}
}

func referenceValue(value term.Term) result.Result[term.Reference, DistributionDispatchFailure] {
	match value {
	case term.ReferenceTerm(reference): return result.Ok[term.Reference, DistributionDispatchFailure](reference)
	case _: return result.Err[term.Reference, DistributionDispatchFailure](InvalidDistributionField("expected reference"))
	}
}

func atomValue(value term.Term) result.Result[string, DistributionDispatchFailure] {
	match value {
	case term.AtomTerm(name): return result.Ok[string, DistributionDispatchFailure](name)
	case _: return result.Err[string, DistributionDispatchFailure](InvalidDistributionField("expected atom"))
	}
}

func uint64Value(value term.Term) result.Result[uint64, DistributionDispatchFailure] {
	match value {
	case term.IntegerTerm(integer):
		if integer.Sign() > 0 && integer.IsUint64() {
			return result.Ok[uint64, DistributionDispatchFailure](integer.Uint64())
		}
		return result.Err[uint64, DistributionDispatchFailure](InvalidDistributionField("expected positive uint64"))
	case _: return result.Err[uint64, DistributionDispatchFailure](InvalidDistributionField("expected integer"))
	}
}

func requiredPayload(payload option.Option[term.Term]) result.Result[term.Term, DistributionDispatchFailure] {
	match payload {
	case option.None: return result.Err[term.Term, DistributionDispatchFailure](InvalidDistributionField("payload is absent"))
	case option.Some(value): return result.Ok[term.Term, DistributionDispatchFailure](value.Clone())
	}
}

func delivery(value kernel.Delivery) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	match value {
	case kernel.Delivered: return applied()
	case kernel.NoProcess: return result.Ok[DistributionDispatch, DistributionDispatchFailure](DistributionDestinationMissing())
	}
}

func applied() result.Result[DistributionDispatch, DistributionDispatchFailure] {
	return result.Ok[DistributionDispatch, DistributionDispatchFailure](DistributionApplied())
}

func deferred(control distribution.Control) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	return result.Ok[DistributionDispatch, DistributionDispatchFailure](DistributionDeferred(control.Number()))
}

func invalidDispatch(detail string) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	return result.Err[DistributionDispatch, DistributionDispatchFailure](InvalidDistributionField(detail))
}

func kernelFailure(failure kernel.Failure) result.Result[DistributionDispatch, DistributionDispatchFailure] {
	return result.Err[DistributionDispatch, DistributionDispatchFailure](DistributionKernelRejected(failure.Error()))
}
