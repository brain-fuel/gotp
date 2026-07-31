package kernel

import (
	"fmt"
	"sync"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type TraceEvent enum {
	ProcessSpawned(PID term.PID)
	ProcessScheduled(PID term.PID)
	ProcessesLinked(Left term.PID, Right term.PID)
	ProcessMonitored(Watcher term.PID, Target term.PID, Reference term.Reference)
	UserSignalQueued(From term.PID, To term.PID, Sequence uint64, Message term.Term)
	ExitSignalQueued(From term.PID, To term.PID, Sequence uint64, Reason term.Term)
	DownSignalQueued(From term.PID, To term.PID, Sequence uint64, Reason term.Term, Reference term.Reference)
	ProcessExited(PID term.PID, Reason term.Term)
}

type TraceRecord struct {
	Sequence uint64
	Event TraceEvent
}

type TraceFailure enum {
	InvalidTraceCapacity(Capacity int)
}

func (failure TraceFailure) Error() string {
	match failure {
	case InvalidTraceCapacity(capacity):
		return fmt.Sprintf("gotp/kernel: trace capacity must be positive, got %d", capacity)
	}
}

type Tracer struct {
	mu sync.RWMutex
	capacity int
	next uint64
	records []TraceRecord
}

// assayxport:unit gotp.kernel.runtime-tracing
func NewTracer(capacity int) result.Result[*Tracer, TraceFailure] {
	if capacity <= 0 {
		return result.Err[*Tracer, TraceFailure](InvalidTraceCapacity(capacity))
	}
	return result.Ok[*Tracer, TraceFailure](&Tracer{capacity: capacity})
}

func (tracer *Tracer) Record(event TraceEvent) TraceRecord {
	tracer.mu.Lock()
	defer tracer.mu.Unlock()
	tracer.next++
	record := TraceRecord{Sequence: tracer.next, Event: cloneTraceEvent(event)}
	if len(tracer.records) == tracer.capacity {
		copy(tracer.records, tracer.records[1:])
		tracer.records[len(tracer.records)-1] = record
	} else {
		tracer.records = append(tracer.records, record)
	}
	return cloneTraceRecord(record)
}

func (tracer *Tracer) Snapshot() []TraceRecord {
	tracer.mu.RLock()
	defer tracer.mu.RUnlock()
	records := make([]TraceRecord, len(tracer.records))
	for index, record := range tracer.records {
		records[index] = cloneTraceRecord(record)
	}
	return records
}

func (kernel *Kernel) EnableTracing(capacity int) result.Result[*Tracer, TraceFailure] {
	match NewTracer(capacity) {
	case result.Err(failure):
		return result.Err[*Tracer, TraceFailure](failure)
	case result.Ok(tracer):
		kernel.tracer = tracer
		return result.Ok[*Tracer, TraceFailure](tracer)
	}
}

func (kernel *Kernel) DisableTracing() option.Option[*Tracer] {
	prior := kernel.tracer
	kernel.tracer = nil
	return option.Of(prior, prior != nil)
}

func (kernel *Kernel) TraceSnapshot() option.Option[[]TraceRecord] {
	if kernel.tracer == nil {
		return option.None[[]TraceRecord]
	}
	return option.Some[[]TraceRecord](kernel.tracer.Snapshot())
}

func (kernel *Kernel) trace(event TraceEvent) {
	if kernel.tracer != nil {
		kernel.tracer.Record(event)
	}
}

func (kernel *Kernel) traceSignal(to term.PID, signal Signal) {
	match signal {
	case UserSignal(from, sequence, message):
		kernel.trace(UserSignalQueued(from, to, sequence, message))
	case ExitSignal(from, sequence, reason, _):
		kernel.trace(ExitSignalQueued(from, to, sequence, reason))
	case DownSignal(from, sequence, reason, reference, _):
		kernel.trace(DownSignalQueued(from, to, sequence, reason, reference))
	}
}

func cloneTraceRecord(record TraceRecord) TraceRecord {
	return TraceRecord{Sequence: record.Sequence, Event: cloneTraceEvent(record.Event)}
}

func cloneTraceEvent(event TraceEvent) TraceEvent {
	match event {
	case ProcessSpawned(pid):
		return ProcessSpawned(pid)
	case ProcessScheduled(pid):
		return ProcessScheduled(pid)
	case ProcessesLinked(left, right):
		return ProcessesLinked(left, right)
	case ProcessMonitored(watcher, target, reference):
		return ProcessMonitored(watcher, target, reference)
	case UserSignalQueued(from, to, sequence, message):
		return UserSignalQueued(from, to, sequence, message.Clone())
	case ExitSignalQueued(from, to, sequence, reason):
		return ExitSignalQueued(from, to, sequence, reason.Clone())
	case DownSignalQueued(from, to, sequence, reason, reference):
		return DownSignalQueued(from, to, sequence, reason.Clone(), reference)
	case ProcessExited(pid, reason):
		return ProcessExited(pid, reason.Clone())
	}
}
