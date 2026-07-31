package genserver

import (
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

func upgradeServer(t *testing.T, change CodeChangeHandler[int64]) *Server[int64, int64, int64, int64] {
	t.Helper()
	match New(Config[int64, int64, int64, int64]{
		InitialState: 7, RequestCodec: Int64Codec{}, ReplyCodec: Int64Codec{}, CastCodec: Int64Codec{}, CodeChange: change,
		HandleCall: func(*kernel.Context, int64, int64) result.Result[CallResult[int64, int64], Failure] { return result.Ok[CallResult[int64, int64], Failure](ContinueCall(0, 0)) },
		HandleCast: func(_ *kernel.Context, value int64, state int64) result.Result[EventResult[int64], Failure] { return result.Ok[EventResult[int64], Failure](ContinueEvent(state + value)) },
	}) {
	case result.Err(failure): t.Fatal(failure.Error()); return nil
	case result.Ok(server): return server
	}
}

// assayxport:law gotp.otp.gen-server-code-change-laws
func TestCodeChangeAtomicallyMigratesState(t *testing.T) {
	server := upgradeServer(t, func(oldVersion term.Term, state int64, extra term.Term) result.Result[int64, Failure] {
		if !term.Equal(oldVersion, term.MustAtom("v1")) || !term.Equal(extra, term.Integer(5)) { return result.Err[int64, Failure](CallbackFailure("upgrade arguments differ")) }
		return result.Ok[int64, Failure](state + 5)
	})
	match server.ChangeCode(term.MustAtom("v1"), term.Integer(5)) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(state): if state != 12 || server.State() != 12 { t.Fatalf("state = %d/%d", state, server.State()) }
	}
}

func TestFailedCodeChangePreservesState(t *testing.T) {
	server := upgradeServer(t, func(term.Term, int64, term.Term) result.Result[int64, Failure] { return result.Err[int64, Failure](CallbackFailure("rejected")) })
	match server.ChangeCode(term.MustAtom("v1"), term.InvalidTerm()) {
	case result.Err(_): if server.State() != 7 { t.Fatalf("failed upgrade state = %d", server.State()) }
	case result.Ok(_): t.Fatal("rejected upgrade succeeded")
	}
}
