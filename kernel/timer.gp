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
	if source == nil {
		return result.Err[clock.Stop, Failure](InvalidTimer("clock capability is nil"))
	}
	if delay < 0 {
		return result.Err[clock.Stop, Failure](InvalidTimer("delay is negative"))
	}
	match kernel.liveProcess(pid) {
	case option.None:
		return result.Err[clock.Stop, Failure](MissingProcess("timer target", pid))
	case option.Some(_):
		stop := source.AfterFunc(delay, func() {
			kernel.wakeups.push(pid)
		})
		if stop == nil {
			return result.Err[clock.Stop, Failure](InvalidTimer("clock returned nil stop handle"))
		}
		return result.Ok[clock.Stop, Failure](stop)
	}
}

func (context *Context) WakeAfter(
	source clock.Clock,
	delay time.Duration,
) result.Result[clock.Stop, Failure] {
	return context.kernel.WakeAfter(source, context.process.pid, delay)
}

func (kernel *Kernel) drainWakeups() {
	if kernel.wakeups == nil {
		kernel.wakeups = newWakeQueue()
	}
	for _, pid := range kernel.wakeups.take() {
		kernel.enqueueRunnable(pid)
	}
}
