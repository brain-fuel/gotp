package genserver

import (
	"fmt"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

var (
	callTag          = term.MustAtom("$gen_call")
	castTag          = term.MustAtom("$gen_cast")
	replyTag         = term.MustAtom("$gen_reply")
	callbackErrorTag = term.MustAtom("callback_error")
	normalReason     = term.MustAtom("normal")
)

type Failure enum {
	InvalidConfiguration(Detail string)
	ExpectedInt64(Found term.Kind)
	Foreign(Operation string, Cause error)
	ServerUnavailable(Server term.PID)
	KernelFailure(Cause kernel.Failure)
	CallbackFailure(Detail string)
}

func (failure Failure) Error() string {
	match failure {
	case InvalidConfiguration(detail):
		return "gotp/genserver: invalid configuration: " + detail
	case ExpectedInt64(found):
		return fmt.Sprintf("gotp/genserver: expected int64; found %v", found)
	case Foreign(operation, cause):
		return fmt.Sprintf("gotp/genserver: %s: %v", operation, cause)
	case ServerUnavailable(server):
		return fmt.Sprintf("gotp/genserver: server process %v does not exist", server)
	case KernelFailure(cause):
		return "gotp/genserver: " + cause.Error()
	case CallbackFailure(detail):
		return "gotp/genserver: callback failed: " + detail
	}
}

type Codec[T any] interface {
	Encode(T) result.Result[term.Term, Failure]
	Decode(term.Term) result.Result[T, Failure]
}

type CodecFuncs[T any] struct {
	EncodeFunc func(T) result.Result[term.Term, Failure]
	DecodeFunc func(term.Term) result.Result[T, Failure]
}

func (codec CodecFuncs[T]) Encode(value T) result.Result[term.Term, Failure] {
	if codec.EncodeFunc == nil {
		return result.Err[term.Term, Failure](InvalidConfiguration("encode function is nil"))
	}
	return codec.EncodeFunc(value)
}

func (codec CodecFuncs[T]) Decode(value term.Term) result.Result[T, Failure] {
	if codec.DecodeFunc == nil {
		return result.Err[T, Failure](InvalidConfiguration("decode function is nil"))
	}
	return codec.DecodeFunc(value)
}

type TermCodec struct{}

func (TermCodec) Encode(value term.Term) result.Result[term.Term, Failure] {
	return result.Ok[term.Term, Failure](value.Clone())
}

func (TermCodec) Decode(value term.Term) result.Result[term.Term, Failure] {
	return result.Ok[term.Term, Failure](value.Clone())
}

type Int64Codec struct{}

func (Int64Codec) Encode(value int64) result.Result[term.Term, Failure] {
	return result.Ok[term.Term, Failure](term.Integer(value))
}

func (Int64Codec) Decode(value term.Term) result.Result[int64, Failure] {
	match value {
	case term.IntegerTerm(integer):
		if integer.IsInt64() {
			return result.Ok[int64, Failure](integer.Int64())
		}
		return result.Err[int64, Failure](ExpectedInt64(value.Kind()))
	case _:
		return result.Err[int64, Failure](ExpectedInt64(value.Kind()))
	}
}

type CallResult[State, Reply any] enum {
	ContinueCall(ReplyValue Reply, StateValue State)
	StopCall(ReplyValue Reply, StateValue State, Reason term.Term)
}

type EventResult[State any] enum {
	ContinueEvent(StateValue State)
	StopEvent(StateValue State, Reason term.Term)
}

type CallHandler[State, Request, Reply any] func(
	*kernel.Context,
	Request,
	State,
) result.Result[CallResult[State, Reply], Failure]

type CastHandler[State, Cast any] func(
	*kernel.Context,
	Cast,
	State,
) result.Result[EventResult[State], Failure]

type InfoHandler[State any] func(
	*kernel.Context,
	kernel.Signal,
	State,
) result.Result[EventResult[State], Failure]

type Config[State, Request, Reply, Cast any] struct {
	InitialState State
	RequestCodec Codec[Request]
	ReplyCodec   Codec[Reply]
	CastCodec    Codec[Cast]
	HandleCall   CallHandler[State, Request, Reply]
	HandleCast   CastHandler[State, Cast]
	HandleInfo   InfoHandler[State]
}

type Server[State, Request, Reply, Cast any] struct {
	state        State
	requestCodec Codec[Request]
	replyCodec   Codec[Reply]
	castCodec    Codec[Cast]
	handleCall   CallHandler[State, Request, Reply]
	handleCast   CastHandler[State, Cast]
	handleInfo   InfoHandler[State]
}

func New[State, Request, Reply, Cast any](
	config Config[State, Request, Reply, Cast],
) result.Result[*Server[State, Request, Reply, Cast], Failure] {
	if config.RequestCodec == nil || config.ReplyCodec == nil || config.CastCodec == nil {
		return result.Err[*Server[State, Request, Reply, Cast], Failure](
			InvalidConfiguration("all codecs are required"),
		)
	}
	if config.HandleCall == nil || config.HandleCast == nil {
		return result.Err[*Server[State, Request, Reply, Cast], Failure](
			InvalidConfiguration("call and cast handlers are required"),
		)
	}
	return result.Ok[*Server[State, Request, Reply, Cast], Failure](
		&Server[State, Request, Reply, Cast]{
			state: config.InitialState, requestCodec: config.RequestCodec,
			replyCodec: config.ReplyCodec, castCodec: config.CastCodec,
			handleCall: config.HandleCall, handleCast: config.HandleCast,
			handleInfo: config.HandleInfo,
		},
	)
}

func (server *Server[State, Request, Reply, Cast]) Behavior() kernel.Behavior {
	return func(context *kernel.Context) kernel.StepResult {
		match context.Receive(nil) {
		case option.None:
			return kernel.Wait()
		case option.Some(signal):
			match signal {
			case kernel.UserSignal(_, _, message):
				match taggedTuple(message, "$gen_call", 4) {
				case option.Some(values):
					return server.call(context, signal, values)
				case option.None:
				}
				match taggedTuple(message, "$gen_cast", 2) {
				case option.Some(values):
					return server.cast(context, values)
				case option.None:
				}
			case _:
			}
			return server.info(context, signal)
		}
	}
}

func (server *Server[State, Request, Reply, Cast]) State() State {
	return server.state
}

func (server *Server[State, Request, Reply, Cast]) call(
	context *kernel.Context,
	signal kernel.Signal,
	values []term.Term,
) kernel.StepResult {
	var caller term.PID
	match values[1] {
	case term.PIDTerm(found):
		caller = found
	case _:
		return server.info(context, signal)
	}
	var reference term.Reference
	match values[2] {
	case term.ReferenceTerm(found):
		reference = found
	case _:
		return server.info(context, signal)
	}
	match signal {
	case kernel.UserSignal(from, _, _):
		if caller != from {
			return server.info(context, signal)
		}
	case _:
		return server.info(context, signal)
	}
	match server.requestCodec.Decode(values[3]) {
	case result.Err(failure):
		return kernel.Stop(callbackFailure(failure))
	case result.Ok(request):
		match server.handleCall(context, request, server.state) {
		case result.Err(failure):
			return kernel.Stop(callbackFailure(failure))
		case result.Ok(decision):
			return server.completeCall(context, caller, reference, decision)
		}
	}
}

func (server *Server[State, Request, Reply, Cast]) completeCall(
	context *kernel.Context,
	caller term.PID,
	reference term.Reference,
	decision CallResult[State, Reply],
) kernel.StepResult {
	var reply Reply
	var transition kernel.StepResult
	match decision {
	case ContinueCall(value, state):
		reply = value
		server.state = state
		transition = kernel.Yield()
	case StopCall(value, state, reason):
		reply = value
		server.state = state
		transition = kernel.Stop(effectiveReason(reason))
	}
	match server.replyCodec.Encode(reply) {
	case result.Err(failure):
		return kernel.Stop(callbackFailure(failure))
	case result.Ok(encoded):
		context.Send(caller, term.Tuple(replyTag, term.ReferenceTerm(reference), encoded))
		return transition
	}
}

func (server *Server[State, Request, Reply, Cast]) cast(
	context *kernel.Context,
	values []term.Term,
) kernel.StepResult {
	match server.castCodec.Decode(values[1]) {
	case result.Err(failure):
		return kernel.Stop(callbackFailure(failure))
	case result.Ok(value):
		match server.handleCast(context, value, server.state) {
		case result.Err(failure):
			return kernel.Stop(callbackFailure(failure))
		case result.Ok(decision):
			return server.applyEvent(decision)
		}
	}
}

func (server *Server[State, Request, Reply, Cast]) info(
	context *kernel.Context,
	signal kernel.Signal,
) kernel.StepResult {
	if server.handleInfo == nil {
		return kernel.Yield()
	}
	match server.handleInfo(context, signal, server.state) {
	case result.Err(failure):
		return kernel.Stop(callbackFailure(failure))
	case result.Ok(decision):
		return server.applyEvent(decision)
	}
}

func (server *Server[State, Request, Reply, Cast]) applyEvent(
	decision EventResult[State],
) kernel.StepResult {
	match decision {
	case ContinueEvent(state):
		server.state = state
		return kernel.Yield()
	case StopEvent(state, reason):
		server.state = state
		return kernel.Stop(effectiveReason(reason))
	}
}

func effectiveReason(reason term.Term) term.Term {
	match reason {
	case term.InvalidTerm:
		return normalReason
	case _:
		return reason
	}
}

func callbackFailure(failure Failure) term.Term {
	return term.Tuple(callbackErrorTag, term.Binary([]byte(failure.Error())))
}

type ClientMutation enum {
	RequestSent()
}

func Cast[Value any](
	context *kernel.Context,
	server term.PID,
	value Value,
	codec Codec[Value],
) result.Result[ClientMutation, Failure] {
	if codec == nil {
		return result.Err[ClientMutation, Failure](InvalidConfiguration("cast codec is nil"))
	}
	match codec.Encode(value) {
	case result.Err(failure):
		return result.Err[ClientMutation, Failure](failure)
	case result.Ok(encoded):
		match context.Send(server, term.Tuple(castTag, encoded)) {
		case kernel.Delivered:
			return result.Ok[ClientMutation, Failure](RequestSent())
		case kernel.NoProcess:
			return result.Err[ClientMutation, Failure](ServerUnavailable(server))
		}
	}
}

func BeginCall[Request any](
	context *kernel.Context,
	server term.PID,
	request Request,
	codec Codec[Request],
) result.Result[term.Reference, Failure] {
	if codec == nil {
		return result.Err[term.Reference, Failure](InvalidConfiguration("request codec is nil"))
	}
	match codec.Encode(request) {
	case result.Err(failure):
		return result.Err[term.Reference, Failure](failure)
	case result.Ok(encoded):
		match context.Monitor(server) {
		case result.Err(cause):
			return result.Err[term.Reference, Failure](KernelFailure(cause))
		case result.Ok(reference):
			context.Send(server, term.Tuple(
				callTag,
				term.PIDTerm(context.Self()),
				term.ReferenceTerm(reference),
				encoded,
			))
			return result.Ok[term.Reference, Failure](reference)
		}
	}
}

type ReplyPoll[Reply any] enum {
	Pending()
	ReplyReceived(Value Reply)
	ServerDown(Reason term.Term)
}

func ReceiveReply[Reply any](
	context *kernel.Context,
	reference term.Reference,
	codec Codec[Reply],
) result.Result[ReplyPoll[Reply], Failure] {
	if codec == nil {
		return result.Err[ReplyPoll[Reply], Failure](InvalidConfiguration("reply codec is nil"))
	}
	received := context.Receive(func(signal kernel.Signal) bool {
		return replySignalFor(signal, reference)
	})
	match received {
	case option.None:
		return result.Ok[ReplyPoll[Reply], Failure](Pending())
	case option.Some(signal):
		match signal {
		case kernel.DownSignal(_, _, reason, _, _):
			return result.Ok[ReplyPoll[Reply], Failure](ServerDown(reason))
		case kernel.UserSignal(_, _, message):
			match taggedTuple(message, "$gen_reply", 3) {
			case option.None:
				return result.Ok[ReplyPoll[Reply], Failure](Pending())
			case option.Some(values):
				match codec.Decode(values[2]) {
				case result.Err(failure):
					return result.Err[ReplyPoll[Reply], Failure](failure)
				case result.Ok(reply):
					context.Demonitor(reference, true)
					return result.Ok[ReplyPoll[Reply], Failure](ReplyReceived(reply))
				}
			}
		case _:
			return result.Ok[ReplyPoll[Reply], Failure](Pending())
		}
	}
}

func replySignalFor(signal kernel.Signal, reference term.Reference) bool {
	match signal {
	case kernel.DownSignal(_, _, _, found, _):
		return found == reference
	case kernel.UserSignal(_, _, message):
		match taggedTuple(message, "$gen_reply", 3) {
		case option.None:
			return false
		case option.Some(values):
			match values[1] {
			case term.ReferenceTerm(found):
				return found == reference
			case _:
				return false
			}
		}
	case _:
		return false
	}
}

func taggedTuple(
	value term.Term,
	tag string,
	length int,
) option.Option[[]term.Term] {
	match value {
	case term.TupleTerm(values):
		if len(values) != length {
			return option.None[[]term.Term]
		}
		match values[0] {
		case term.AtomTerm(name):
			if name == tag {
				return option.Some[[]term.Term](values)
			}
		case _:
		}
		return option.None[[]term.Term]
	case _:
		return option.None[[]term.Term]
	}
}
