package kernel

import (
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func mustEnableTracing(t *testing.T, runtime *Kernel, capacity int) *Tracer {
	match runtime.EnableTracing(capacity) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(tracer):
		return tracer
	}
	panic("unreachable")
}

// assayxport:law gotp.kernel.runtime-tracing-laws
func TestTraceRecordsRuntimeTransitionsInSequence(t *testing.T) {
	runtime := New(KernelConfig{})
	tracer := mustEnableTracing(t, runtime, 32)
	left := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	right := mustSpawn(t, runtime, func(_ *Context) StepResult {
		return Stop(term.MustAtom("done"))
	}, Unlinked(false))
	match runtime.Link(left, right) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	runtime.Run(10)
	records := tracer.Snapshot()
	if len(records) < 6 {
		t.Fatalf("trace records = %v", records)
	}
	for index, record := range records {
		if record.Sequence != uint64(index+1) {
			t.Fatalf("trace sequence at %d = %d", index, record.Sequence)
		}
	}
	match records[0].Event {
	case ProcessSpawned(pid):
		if pid != left { t.Fatalf("first spawn = %v", pid) }
	case _:
		t.Fatalf("first event = %T", records[0].Event)
	}
	linked := false
	exited := false
	for _, record := range records {
		var event TraceEvent = record.Event
		match event {
		case ProcessesLinked(foundLeft, foundRight):
			linked = foundLeft == left && foundRight == right
		case ProcessExited(pid, reason):
			if pid == right && term.Equal(reason, term.MustAtom("done")) { exited = true }
		case ProcessSpawned(_), ProcessScheduled(_), ProcessMonitored(_, _, _), UserSignalQueued(_, _, _, _), ExitSignalQueued(_, _, _, _), DownSignalQueued(_, _, _, _, _):
		}
	}
	if !linked || !exited { t.Fatalf("linked=%v exited=%v records=%v", linked, exited, records) }
}

func TestTraceSignalTermsAreCloned(t *testing.T) {
	runtime := New(KernelConfig{})
	tracer := mustEnableTracing(t, runtime, 16)
	receiver := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	sender := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	payload := []byte("before")
	runtime.Send(sender, receiver, term.Binary(payload))
	payload[0] = 'X'
	found := false
	for _, record := range tracer.Snapshot() {
		var event TraceEvent = record.Event
		match event {
		case UserSignalQueued(_, _, _, message):
			if term.Equal(message, term.Binary([]byte("before"))) { found = true }
		case ProcessSpawned(_), ProcessScheduled(_), ProcessesLinked(_, _), ProcessMonitored(_, _, _), ExitSignalQueued(_, _, _, _), DownSignalQueued(_, _, _, _, _), ProcessExited(_, _):
		}
	}
	if !found { t.Fatal("trace message shared caller bytes") }
}

func TestTraceCapacityRetainsNewestRecords(t *testing.T) {
	runtime := New(KernelConfig{})
	tracer := mustEnableTracing(t, runtime, 3)
	for index := 0; index < 5; index++ {
		mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	}
	records := tracer.Snapshot()
	if len(records) != 3 || records[0].Sequence != 3 || records[2].Sequence != 5 {
		t.Fatalf("bounded trace = %v", records)
	}
	match runtime.DisableTracing() {
	case option.None:
		t.Fatal("enabled tracer was absent")
	case option.Some(_):
	}
}
