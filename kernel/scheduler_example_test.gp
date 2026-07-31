package kernel

import (
	"fmt"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func ExampleKernel_RunSlice() {
	kernel := New(KernelConfig{})
	steps := 0
	var spawned result.Result[term.PID, Failure] = kernel.Spawn(
		func(_ *Context) StepResult {
			steps++
			return Yield()
		},
		Unlinked(false),
	)
	match spawned {
	case result.Err(failure):
		fmt.Println(failure.Error())
	case result.Ok(_):
		var checked result.Result[ReductionBudget, SchedulerFailure] = NewReductionBudget(3)
		match checked {
		case result.Err(failure):
			fmt.Println(failure.Error())
		case result.Ok(budget):
			report := kernel.RunSlice(budget)
			fmt.Println(report.Run.Reductions, steps)
		}
	}
	// Output:
	// 3 3
}

// assayxport:unit gotp.kernel.scheduler-laws
func TestReductionBudgetFairnessProperty(t *testing.T) {
	property := func(rawBudget uint8, rawProcesses uint8) bool {
		budgetValue := int(rawBudget%64) + 1
		processCount := int(rawProcesses%8) + 1
		kernel := New(KernelConfig{})
		counts := make([]int, processCount)
		for index := range counts {
			slot := index
			var spawned result.Result[term.PID, Failure] = kernel.Spawn(
				func(_ *Context) StepResult {
					counts[slot]++
					return Yield()
				},
				Unlinked(false),
			)
			match spawned {
			case result.Err(_):
				return false
			case result.Ok(_):
			}
		}
		var checked result.Result[ReductionBudget, SchedulerFailure] = NewReductionBudget(budgetValue)
		match checked {
		case result.Err(_):
			return false
		case result.Ok(budget):
			report := kernel.RunSlice(budget)
			if report.Run.Reductions != budgetValue {
				return false
			}
			total := 0
			minimum := counts[0]
			maximum := counts[0]
			for _, count := range counts {
				total += count
				if count < minimum { minimum = count }
				if count > maximum { maximum = count }
			}
			if total != budgetValue || maximum-minimum > 1 {
				return false
			}
			match report.State {
			case SliceExhausted:
				return true
			case SliceQuiescent:
				return false
			}
		}
	}
	if failure := quick.Check(property, nil); failure != nil {
		t.Fatal(failure)
	}
}

func TestWaitingProcessDoesNotConsumeReductions(t *testing.T) {
	kernel := New(KernelConfig{})
	steps := 0
	mustSpawnSchedulerTest(t, kernel, func(_ *Context) StepResult {
		steps++
		return Wait()
	})
	report := kernel.RunSlice(mustBudgetSchedulerTest(t, 100))
	if steps != 1 || report.Run.Reductions != 1 || report.Run.Runnable != 0 || report.Run.Waiting != 1 {
		t.Fatalf("steps=%d report=%#v", steps, report.Run)
	}
	match report.State {
	case SliceQuiescent:
	case SliceExhausted:
		t.Fatal("waiting-only scheduler reported exhausted budget")
	}
}

func TestMessageWakesWaitingProcess(t *testing.T) {
	kernel := New(KernelConfig{})
	received := 0
	pid := mustSpawnSchedulerTest(t, kernel, func(context *Context) StepResult {
		var message option.Option[MessageEnvelope] = context.ReceiveMessage(nil)
		match message {
		case option.None:
			return Wait()
		case option.Some(_):
			received++
			return Stop(term.MustAtom("normal"))
		}
	})
	kernel.RunSlice(mustBudgetSchedulerTest(t, 1))
	kernel.Send(pid, pid, term.MustAtom("wake"))
	report := kernel.RunSlice(mustBudgetSchedulerTest(t, 1))
	if received != 1 || report.Run.Reductions != 1 || report.Run.Exited != 1 {
		t.Fatalf("received=%d report=%#v", received, report.Run)
	}
}

func mustSpawnSchedulerTest(t *testing.T, kernel *Kernel, behavior Behavior) term.PID {
	t.Helper()
	var spawned result.Result[term.PID, Failure] = kernel.Spawn(behavior, Unlinked(false))
	match spawned {
	case result.Ok(pid):
		return pid
	case result.Err(failure):
		t.Fatal(failure.Error())
		return term.PID{}
	}
}

func mustBudgetSchedulerTest(t *testing.T, value int) ReductionBudget {
	t.Helper()
	var checked result.Result[ReductionBudget, SchedulerFailure] = NewReductionBudget(value)
	match checked {
	case result.Ok(budget):
		return budget
	case result.Err(failure):
		t.Fatal(failure.Error())
		return ReductionBudget{}
	}
}
