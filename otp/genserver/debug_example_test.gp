package genserver

import (
	"testing"
	"testing/quick"
	"time"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

func debugServer(t *testing.T, source clock.Clock, output DebugOutputCapability) *Server[int64, int64, int64, int64] {
	t.Helper()
	match New(Config[int64, int64, int64, int64]{
		InitialState: 3, RequestCodec: Int64Codec{}, ReplyCodec: Int64Codec{}, CastCodec: Int64Codec{}, StateCodec: Int64Codec{}, Clock: source, DebugOutput: output,
		HandleCall: func(_ *kernel.Context, _ int64, state int64) result.Result[CallResult[int64, int64], Failure] { return result.Ok[CallResult[int64, int64], Failure](ContinueCall(state, state)) },
		HandleCast: func(_ *kernel.Context, value int64, state int64) result.Result[EventResult[int64], Failure] { return result.Ok[EventResult[int64], Failure](ContinueEvent(state + value)) },
	}) {
	case result.Err(failure): t.Fatal(failure.Error()); return nil
	case result.Ok(server): return server
	}
}

// assayxport:law gotp.otp.gen-server-debug-laws
func TestSystemDebugTraceLogAndStatistics(t *testing.T) {
	source := clock.NewFake(time.Date(2026, 7, 31, 12, 0, 0, 0, time.UTC))
	traced := []term.Term{}
	server := debugServer(t, source, DebugOutputWith(func(event term.Term, _ term.Term) { traced = append(traced, event) }))
	if !term.Equal(server.debugCommand(term.Tuple(term.MustAtom("log"), term.Tuple(term.MustAtom("true"), term.Integer(2)))), okReply) { t.Fatal("log enable failed") }
	if !term.Equal(server.debugCommand(term.Tuple(term.MustAtom("statistics"), term.MustAtom("true"))), okReply) { t.Fatal("statistics enable failed") }
	if !term.Equal(server.debugCommand(term.Tuple(term.MustAtom("trace"), term.MustAtom("true"))), okReply) { t.Fatal("trace enable failed") }
	server.debugEvent(term.Tuple(term.MustAtom("in"), term.MustAtom("first")))
	server.debugEvent(term.Tuple(term.MustAtom("out"), term.MustAtom("second"), term.PIDTerm(term.PID{Node: 1, Number: 1, Creation: 1})))
	server.debugEvent(term.Tuple(term.MustAtom("in"), term.MustAtom("third")))
	if len(traced) != 3 || len(server.debug.events) != 2 { t.Fatalf("trace/log counts = %d/%d", len(traced), len(server.debug.events)) }
	match server.debugLogCommand(term.MustAtom("get")) { case term.TupleTerm(values): match values[1] { case term.ProperListTerm(events): if len(events) != 2 { t.Fatalf("logged events = %d", len(events)) }; case _: t.Fatal("log response is not list") }; case _: t.Fatal("log response is not tuple") }
	source.Advance(2 * time.Second)
	match server.debugStatisticsCommand(term.MustAtom("get")) { case term.TupleTerm(values): match values[1] { case term.ProperListTerm(stats): if len(stats) != 5 { t.Fatalf("statistics = %d", len(stats)) }; case _: t.Fatal("statistics response is not list") }; case _: t.Fatal("statistics response is not tuple") }
	if !term.Equal(server.debugCommand(term.MustAtom("no_debug")), okReply) || server.debug.trace || server.debug.logLimit != 0 || server.debug.statistics { t.Fatal("no_debug did not reset debug state") }
}

func TestSystemDebugRequestDecodesPinnedShape(t *testing.T) {
	request := term.Tuple(term.MustAtom("debug"), term.Tuple(term.MustAtom("log"), term.MustAtom("get")))
	match systemRequestFromTerm(request) { case SystemDebug(command): if !term.Equal(command, requestTupleValue(t, request, 1)) { t.Fatal("debug command differs") }; case _: t.Fatal("debug request was not decoded") }
}

func TestSystemDebugLogBoundLaw(t *testing.T) {
	law := func(values []int64, rawLimit uint8) bool {
		limit := int(rawLimit%32) + 1
		server := debugServer(t, clock.NewFake(time.Unix(0, 0)), DebugOutputUnavailable())
		server.debugLogCommand(term.Tuple(term.MustAtom("true"), term.Integer(int64(limit))))
		for _, value := range values { server.debugEvent(term.Tuple(term.MustAtom("in"), term.Integer(value))) }
		return len(server.debug.events) <= limit && len(server.debug.events) <= len(values)
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 1000})) { case result.Err(cause): t.Fatal(cause); case result.Ok(_): }
}

func requestTupleValue(t *testing.T, value term.Term, index int) term.Term {
	t.Helper()
	match value { case term.TupleTerm(values): return values[index].Clone(); case _: t.Fatal("request is not tuple"); return term.InvalidTerm() }
}
