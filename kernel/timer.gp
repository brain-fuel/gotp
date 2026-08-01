package kernel

import (
	"sync"
	"time"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type wakeQueue struct {
	mutex sync.Mutex
	pids  []term.PID
	messages []scheduledMessage
}

type scheduledMessage struct { from term.PID; target term.Term; message term.Term }

type WakeTimerStatus enum {
	WakeTimerPending()
	WakeTimerFired()
	WakeTimerCancelled()
}

type WakeTimer struct {
	mutex  sync.Mutex
	status WakeTimerStatus
	stop   clock.Stop
}

type MessageTimer struct {
	mutex sync.Mutex
	status WakeTimerStatus
	stop clock.Stop
}

func newWakeQueue() *wakeQueue {
	return &wakeQueue{}
}

func (queue *wakeQueue) push(pid term.PID) {
	queue.mutex.Lock()
	defer queue.mutex.Unlock()
	queue.pids = append(queue.pids, pid)
}

func (queue *wakeQueue) take() []term.PID {
	queue.mutex.Lock()
	defer queue.mutex.Unlock()
	pids := append([]term.PID(nil), queue.pids...)
	queue.pids = queue.pids[:0]
	return pids
}

func (queue *wakeQueue) pushMessage(message scheduledMessage) {
	queue.mutex.Lock(); defer queue.mutex.Unlock()
	queue.messages = append(queue.messages, scheduledMessage{from: message.from, target: message.target.Clone(), message: message.message.Clone()})
}

func (queue *wakeQueue) takeMessages() []scheduledMessage {
	queue.mutex.Lock(); defer queue.mutex.Unlock()
	messages := append([]scheduledMessage(nil), queue.messages...)
	queue.messages = queue.messages[:0]
	return messages
}

// assayxport:unit gotp.kernel.timer-wakeup
func (kernel *Kernel) WakeAfter(
	source clock.Clock,
	pid term.PID,
	delay time.Duration,
) result.Result[clock.Stop, Failure] {
	match kernel.WakeTimerAfter(source, pid, delay) {
	case result.Err(failure):
		return result.Err[clock.Stop, Failure](failure)
	case result.Ok(timer):
		return result.Ok[clock.Stop, Failure](timer)
	}
}

func (kernel *Kernel) WakeTimerAfter(
	source clock.Clock,
	pid term.PID,
	delay time.Duration,
) result.Result[*WakeTimer, Failure] {
	if source == nil {
		return result.Err[*WakeTimer, Failure](InvalidTimer("clock capability is nil"))
	}
	if delay < 0 {
		return result.Err[*WakeTimer, Failure](InvalidTimer("delay is negative"))
	}
	match kernel.liveProcess(pid) {
	case option.None:
		return result.Err[*WakeTimer, Failure](MissingProcess("timer target", pid))
	case option.Some(_):
		timer := &WakeTimer{status: WakeTimerPending()}
		stop := source.AfterFunc(delay, func() { timer.fire(kernel.wakeups, pid) })
		if stop == nil {
			return result.Err[*WakeTimer, Failure](InvalidTimer("clock returned nil stop handle"))
		}
		timer.attach(stop)
		return result.Ok[*WakeTimer, Failure](timer)
	}
}

func (context *Context) WakeAfter(
	source clock.Clock,
	delay time.Duration,
) result.Result[clock.Stop, Failure] {
	return context.kernel.WakeAfter(source, context.process.pid, delay)
}

func (context *Context) WakeTimerAfter(
	source clock.Clock,
	delay time.Duration,
) result.Result[*WakeTimer, Failure] {
	return context.kernel.WakeTimerAfter(source, context.process.pid, delay)
}

func (kernel *Kernel) StartMessageTimer(source clock.Clock, owner term.PID, target term.Term, message term.Term, delay time.Duration) result.Result[term.Reference, Failure] {
	if source == nil { return result.Err[term.Reference, Failure](InvalidTimer("clock capability is nil")) }
	if delay < 0 { return result.Err[term.Reference, Failure](InvalidTimer("delay is negative")) }
	match kernel.liveProcess(owner) { case option.None: return result.Err[term.Reference, Failure](MissingProcess("timer owner", owner)); case option.Some(_): }
	reference := kernel.newReference()
	timer := &MessageTimer{status: WakeTimerPending()}
	stop := source.AfterFunc(delay, func() { timer.fire(kernel.wakeups, scheduledMessage{from: owner, target: target.Clone(), message: term.Tuple(term.MustAtom("timeout"), term.ReferenceValue(reference), message.Clone())}) })
	if stop == nil { return result.Err[term.Reference, Failure](InvalidTimer("clock returned nil stop handle")) }
	timer.stop = stop
	kernel.messageTimers[reference] = timer
	return result.Ok[term.Reference, Failure](reference)
}

func (kernel *Kernel) CancelMessageTimer(reference term.Reference) bool {
	timer, present := kernel.messageTimers[reference]
	if !present { return false }
	delete(kernel.messageTimers, reference)
	return timer.Stop()
}

func (context *Context) StartMessageTimer(source clock.Clock, target term.Term, message term.Term, delay time.Duration) result.Result[term.Reference, Failure] { return context.kernel.StartMessageTimer(source, context.process.pid, target, message, delay) }
func (context *Context) CancelMessageTimer(reference term.Reference) bool { return context.kernel.CancelMessageTimer(reference) }

func (timer *WakeTimer) Status() WakeTimerStatus {
	timer.mutex.Lock()
	defer timer.mutex.Unlock()
	return timer.status
}

func (timer *WakeTimer) Stop() bool {
	timer.mutex.Lock()
	var status WakeTimerStatus = timer.status
	match status {
	case WakeTimerPending:
		timer.status = WakeTimerCancelled()
		stop := timer.stop
		timer.mutex.Unlock()
		if stop != nil {
			stop.Stop()
		}
		return true
	case WakeTimerFired, WakeTimerCancelled:
		timer.mutex.Unlock()
		return false
	}
}

func (timer *WakeTimer) attach(stop clock.Stop) {
	timer.mutex.Lock()
	timer.stop = stop
	var status WakeTimerStatus = timer.status
	timer.mutex.Unlock()
	match status {
	case WakeTimerCancelled:
		stop.Stop()
	case WakeTimerPending, WakeTimerFired:
	}
}

func (timer *WakeTimer) fire(queue *wakeQueue, pid term.PID) {
	timer.mutex.Lock()
	var status WakeTimerStatus = timer.status
	match status {
	case WakeTimerPending:
		timer.status = WakeTimerFired()
		timer.mutex.Unlock()
		queue.push(pid)
	case WakeTimerFired, WakeTimerCancelled:
		timer.mutex.Unlock()
	}
}

func (timer *MessageTimer) Stop() bool {
	timer.mutex.Lock(); defer timer.mutex.Unlock()
	match timer.status {
	case WakeTimerPending:
		timer.status = WakeTimerCancelled(); if timer.stop != nil { timer.stop.Stop() }; return true
	case WakeTimerFired, WakeTimerCancelled: return false
	}
}

func (timer *MessageTimer) fire(queue *wakeQueue, message scheduledMessage) {
	timer.mutex.Lock()
	match timer.status {
	case WakeTimerPending: timer.status = WakeTimerFired(); timer.mutex.Unlock(); queue.pushMessage(message)
	case WakeTimerFired, WakeTimerCancelled: timer.mutex.Unlock()
	}
}

func (kernel *Kernel) drainWakeups() {
	if kernel.wakeups == nil {
		kernel.wakeups = newWakeQueue()
	}
	for _, pid := range kernel.wakeups.take() {
		kernel.enqueueRunnable(pid)
	}
	for _, scheduled := range kernel.wakeups.takeMessages() {
		match scheduled.target {
		case term.PIDTerm(pid): kernel.Send(scheduled.from, pid, scheduled.message)
		case term.ReferenceTerm(reference): kernel.SendAlias(scheduled.from, reference, scheduled.message)
		case term.AtomTerm(name): kernel.SendRegistered(scheduled.from, name, scheduled.message)
		case term.TupleTerm(parts):
			if len(parts) == 2 { match term.AtomName(parts[0]) { case option.None: case option.Some(name): match term.AtomName(parts[1]) { case option.None: case option.Some(node): kernel.SendRemoteRegistered(scheduled.from, node, name, scheduled.message) } } }
		case _:
		}
	}
}
