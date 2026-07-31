package kernel

import (
	"fmt"

	"goforge.dev/goplus/std/result"
)

type ReductionBudget struct {
	value int
}

type SchedulerFailure enum {
	InvalidReductionBudget(Value int)
}

func (failure SchedulerFailure) Error() string {
	match failure {
	case InvalidReductionBudget(value):
		return fmt.Sprintf("gotp/kernel: reduction budget must be positive, got %d", value)
	}
}

type SliceState enum {
	SliceExhausted()
	SliceQuiescent()
}

type SliceReport struct {
	Run   RunReport
	State SliceState
}

// assayxport:unit gotp.kernel.scheduler
func NewReductionBudget(value int) result.Result[ReductionBudget, SchedulerFailure] {
	if value <= 0 {
		return result.Err[ReductionBudget, SchedulerFailure](InvalidReductionBudget(value))
	}
	return result.Ok[ReductionBudget, SchedulerFailure](ReductionBudget{value: value})
}

func ReductionBudgetValue(budget ReductionBudget) int {
	return budget.value
}

func (kernel *Kernel) RunSlice(budget ReductionBudget) SliceReport {
	report := kernel.Run(budget.value)
	var state SliceState = SliceQuiescent()
	if report.Reductions == budget.value && report.Runnable > 0 {
		state = SliceExhausted()
	}
	return SliceReport{Run: report, State: state}
}
