package kernel

import (
	"testing"
	"testing/quick"
	"time"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

// assayxport:unit gotp.kernel.timer-wakeup-laws
func TestFakeClockWakeupProperty(t *testing.T) {
	property := func(rawDelay uint16) bool {
		delay := time.Duration(rawDelay%1000+1) * time.Millisecond
		kernel := New(KernelConfig{})
		steps := 0
		var spawned result.Result[term.PID, Failure] = kernel.Spawn(
			func(_ *Context) StepResult {
				steps++
				if steps == 1 { return Wait() }
				return Stop(term.MustAtom("normal"))
			},
			Unlinked(false),
		)
		match spawned {
		case result.Err(_):
			return false
		case result.Ok(pid):
			kernel.Run(1)
			fake := clock.NewFake(time.Unix(0, 0))
			match kernel.WakeAfter(fake, pid, delay) {
			case result.Err(_):
				return false
			case result.Ok(_):
				fake.Advance(delay - time.Nanosecond)
				before := kernel.Run(1)
				if before.Reductions != 0 || steps != 1 { return false }
				fake.Advance(time.Nanosecond)
				after := kernel.Run(1)
				return after.Reductions == 1 && after.Exited == 1 && steps == 2
			}
		}
	}
	if failure := quick.Check(property, nil); failure != nil {
		t.Fatal(failure)
	}
}

func TestCancelledWakeupRemainsWaiting(t *testing.T) {
	kernel := New(KernelConfig{})
	var spawned result.Result[term.PID, Failure] = kernel.Spawn(
		func(_ *Context) StepResult { return Wait() },
		Unlinked(false),
	)
	match spawned {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(pid):
		kernel.Run(1)
		fake := clock.NewFake(time.Unix(0, 0))
		match kernel.WakeAfter(fake, pid, time.Second) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(stop):
			if !stop.Stop() { t.Fatal("pending timer was not cancelled") }
			fake.Advance(time.Second)
			report := kernel.Run(1)
			if report.Reductions != 0 || report.Waiting != 1 {
				t.Fatalf("report=%#v", report)
			}
		}
	}
}
