package genserver

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

type clientPhase enum {
	SendPhase()
	AwaitPhase()
}

func TestInt64CodecRoundTripLaw(t *testing.T) {
	codec := Int64Codec{}
	law := func(value int64) bool {
		match codec.Encode(value) {
		case result.Err(_):
			return false
		case result.Ok(encoded):
			match codec.Decode(encoded) {
			case result.Ok(decoded):
				return decoded == value
			case result.Err(_):
				return false
			}
		}
	}
	match result.Of(true, quick.Check(law, nil)) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}

func TestTypedCallAndCastRoundTrip(t *testing.T) {
	server := newCounterServer(t)
	runtime := kernel.New(kernel.KernelConfig{})
	serverPID := spawn(t, runtime, server.Behavior())
	reply := int64(0)
	var phase clientPhase = SendPhase()
	var reference option.Option[term.Reference] = option.None[term.Reference]
	clientPID := spawn(t, runtime, func(context *kernel.Context) kernel.StepResult {
		match phase {
		case SendPhase:
			match Cast(context, serverPID, int64(5), Int64Codec{}) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(_):
			}
			match BeginCall(context, serverPID, int64(7), Int64Codec{}) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(found):
				reference = option.Some[term.Reference](found)
				phase = AwaitPhase()
				return kernel.Yield()
			}
		case AwaitPhase:
			match reference {
			case option.None:
				return kernel.Stop(term.MustAtom("missing_reference"))
			case option.Some(found):
				match ReceiveReply(context, found, Int64Codec{}) {
				case result.Err(failure):
					t.Fatal(failure.Error())
				case result.Ok(poll):
					match poll {
					case Pending:
						return kernel.Wait()
					case ReplyReceived(value):
						reply = value
						return kernel.Stop(term.MustAtom("normal"))
					case ServerDown(_):
						return kernel.Stop(term.MustAtom("unexpected_down"))
					}
				}
			}
		}
		return kernel.Stop(term.MustAtom("unreachable"))
	}, kernel.Unlinked(false))

	report := runtime.Run(100)
	if reply != 12 {
		t.Fatalf("reply = %d", reply)
	}
	if server.State() != 5 {
		t.Fatalf("server state = %d", server.State())
	}
	match runtime.ProcessInfo(clientPID) {
	case option.None:
		t.Fatal("client process record is missing")
	case option.Some(info):
		match info.Status {
		case kernel.Exited:
		case _:
			t.Fatalf("client status = %#v; report = %#v", info.Status, report)
		}
	}
}

func TestCallObservesServerDown(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{})
	serverPID := spawn(t, runtime, func(context *kernel.Context) kernel.StepResult {
		return kernel.Stop(term.MustAtom("crashed"))
	})
	runtime.Run(1)

	var observed option.Option[term.Term] = option.None[term.Term]
	var phase clientPhase = SendPhase()
	var reference option.Option[term.Reference] = option.None[term.Reference]
	spawn(t, runtime, func(context *kernel.Context) kernel.StepResult {
		match phase {
		case SendPhase:
			match BeginCall(context, serverPID, int64(1), Int64Codec{}) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(found):
				reference = option.Some[term.Reference](found)
				phase = AwaitPhase()
				return kernel.Yield()
			}
		case AwaitPhase:
			match reference {
			case option.None:
				return kernel.Stop(term.MustAtom("missing_reference"))
			case option.Some(found):
				match ReceiveReply(context, found, Int64Codec{}) {
				case result.Err(failure):
					t.Fatal(failure.Error())
				case result.Ok(poll):
					match poll {
					case Pending:
						return kernel.Wait()
					case ReplyReceived(_):
						return kernel.Stop(term.MustAtom("unexpected_reply"))
					case ServerDown(reason):
						observed = option.Some[term.Term](reason)
						return kernel.Stop(term.MustAtom("normal"))
					}
				}
			}
		}
		return kernel.Stop(term.MustAtom("unreachable"))
	})
	runtime.Run(10)
	match observed {
	case option.None:
		t.Fatal("server DOWN was not observed")
	case option.Some(reason):
		assertAtom(t, reason, "noproc")
	}
}

func TestCallbackFailureTerminatesServer(t *testing.T) {
	var server *Server[int, term.Term, term.Term, term.Term]
	match New(Config[int, term.Term, term.Term, term.Term]{
		RequestCodec: TermCodec{}, ReplyCodec: TermCodec{}, CastCodec: TermCodec{},
		HandleCall: func(
			context *kernel.Context,
			request term.Term,
			state int,
		) result.Result[CallResult[int, term.Term], Failure] {
			return result.Err[CallResult[int, term.Term], Failure](
				CallbackFailure("handler failed"),
			)
		},
		HandleCast: func(
			context *kernel.Context,
			value term.Term,
			state int,
		) result.Result[EventResult[int], Failure] {
			return result.Ok[EventResult[int], Failure](ContinueEvent(state))
		},
	}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(found):
		server = found
	}
	runtime := kernel.New(kernel.KernelConfig{})
	serverPID := spawn(t, runtime, server.Behavior())
	spawn(t, runtime, func(context *kernel.Context) kernel.StepResult {
		match BeginCall(context, serverPID, term.MustAtom("fail"), TermCodec{}) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(_):
		}
		return kernel.Stop(term.MustAtom("normal"))
	})
	runtime.Run(10)
	match runtime.ProcessInfo(serverPID) {
	case option.None:
		t.Fatal("server process record is missing")
	case option.Some(info):
		match info.Status {
		case kernel.Exited:
		case _:
			t.Fatal("server did not exit")
		}
		match info.ExitReason {
		case option.None:
			t.Fatal("server has no exit reason")
		case option.Some(reason):
			match reason {
			case term.TupleTerm(_):
			case _:
				t.Fatal("server exit reason is not callback_error tuple")
			}
		}
	}
}

func newCounterServer(
	t *testing.T,
) *Server[int64, int64, int64, int64] {
	t.Helper()
	match New(Config[int64, int64, int64, int64]{
		InitialState: int64(0),
		RequestCodec: Int64Codec{}, ReplyCodec: Int64Codec{}, CastCodec: Int64Codec{},
		HandleCall: func(
			context *kernel.Context,
			request int64,
			state int64,
		) result.Result[CallResult[int64, int64], Failure] {
			return result.Ok[CallResult[int64, int64], Failure](
				ContinueCall(state+request, state),
			)
		},
		HandleCast: func(
			context *kernel.Context,
			value int64,
			state int64,
		) result.Result[EventResult[int64], Failure] {
			return result.Ok[EventResult[int64], Failure](ContinueEvent(state + value))
		},
	}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
		return nil
	case result.Ok(server):
		return server
	}
}

func spawn(
	t *testing.T,
	runtime *kernel.Kernel,
	behavior kernel.Behavior,
	policy ...kernel.SpawnPolicy,
) term.PID {
	t.Helper()
	var selected kernel.SpawnPolicy = kernel.Unlinked(false)
	if len(policy) == 1 {
		selected = policy[0]
	}
	match runtime.Spawn(behavior, selected) {
	case result.Ok(pid):
		return pid
	case result.Err(failure):
		t.Fatal(failure.Error())
		return term.PID{}
	}
}

func assertAtom(t *testing.T, value term.Term, want string) {
	t.Helper()
	match value {
	case term.AtomTerm(name):
		if name != want {
			t.Fatalf("atom = %q, want %q", name, want)
		}
	case _:
		t.Fatal("term is not an atom")
	}
}
