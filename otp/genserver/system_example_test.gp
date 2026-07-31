package genserver

import (
	"testing"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

func systemMessage(from term.PID, tag string, request term.Term) term.Term { return term.Tuple(systemTag, term.Tuple(term.PIDTerm(from), term.MustAtom(tag)), request) }

// assayxport:law gotp.otp.gen-server-system-laws
func TestSystemSuspendChangeCodeResumeIsSelective(t *testing.T) {
	server := upgradeServer(t, func(_ term.Term, state int64, extra term.Term) result.Result[int64, Failure] {
		match term.Int64(extra) { case option.None: return result.Err[int64, Failure](CallbackFailure("extra is not int64")); case option.Some(value): return result.Ok[int64, Failure](state + value) }
	})
	runtime := kernel.New(kernel.KernelConfig{})
	serverPID := spawn(t, runtime, server.Behavior())
	replies := []term.Term{}
	clientPID := spawn(t, runtime, func(context *kernel.Context) kernel.StepResult {
		match context.ReceiveMessage(nil) { case option.None: return kernel.Wait(); case option.Some(envelope): replies = append(replies, envelope.Message); return kernel.Yield() }
	})
	runtime.Send(clientPID, serverPID, systemMessage(clientPID, "suspended", term.MustAtom("suspend")))
	runtime.Run(20)
	if !server.Suspended() || server.State() != 7 { t.Fatalf("suspended/state = %v/%d", server.Suspended(), server.State()) }
	runtime.Send(clientPID, serverPID, term.Tuple(castTag, term.Integer(5)))
	runtime.Send(clientPID, serverPID, systemMessage(clientPID, "changed", term.Tuple(term.MustAtom("change_code"), term.MustAtom("sample"), term.MustAtom("v1"), term.Integer(100))))
	runtime.Run(20)
	if server.State() != 107 { t.Fatalf("state while suspended = %d", server.State()) }
	runtime.Send(clientPID, serverPID, systemMessage(clientPID, "resumed", term.MustAtom("resume")))
	runtime.Run(30)
	if server.Suspended() || server.State() != 112 { t.Fatalf("resumed/state = %v/%d", server.Suspended(), server.State()) }
	if len(replies) != 3 { t.Fatalf("system replies = %d, want 3", len(replies)) }
	for index, tag := range []string{"suspended", "changed", "resumed"} {
		match replies[index] { case term.TupleTerm(values): if len(values) != 2 || !term.Equal(values[0], term.MustAtom(tag)) || !term.Equal(values[1], okReply) { t.Fatalf("reply %d = %v", index, replies[index]) }; case _: t.Fatalf("reply %d is not tuple", index) }
	}
}

func TestSystemChangeCodeRequiresSuspension(t *testing.T) {
	server := upgradeServer(t, func(_ term.Term, state int64, _ term.Term) result.Result[int64, Failure] { return result.Ok[int64, Failure](state + 1) })
	runtime := kernel.New(kernel.KernelConfig{})
	serverPID := spawn(t, runtime, server.Behavior())
	clientPID := spawn(t, runtime, func(context *kernel.Context) kernel.StepResult { return kernel.Wait() })
	runtime.Send(clientPID, serverPID, systemMessage(clientPID, "change", term.Tuple(term.MustAtom("change_code"), term.MustAtom("sample"), term.MustAtom("v1"), term.Integer(0))))
	runtime.Run(20)
	if server.State() != 7 { t.Fatalf("unsuspended change state = %d", server.State()) }
}
