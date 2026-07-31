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
}

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

func (kernel *Kernel) drainWakeups() {
	if kernel.wakeups == nil {
		kernel.wakeups = newWakeQueue()
	}
	for _, pid := range kernel.wakeups.take() {
		kernel.enqueueRunnable(pid)
	}
}
