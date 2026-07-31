package vm

import (
	"fmt"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

func ExampleContinuation_Resume() {
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("move", integer(42), xregister(0)),
		instruction("return"),
	}
	match NewMachine(program, MachineConfig{}) {
	case result.Err(failure):
		fmt.Println(failure.Error())
	case result.Ok(machine):
		var started result.Result[*Continuation, Failure] = machine.Start(1)
		match started {
		case result.Err(failure):
			fmt.Println(failure.Error())
		case result.Ok(continuation):
			var checked result.Result[VMReductionBudget, Failure] = NewVMReductionBudget(1)
			match checked {
			case result.Err(failure):
				fmt.Println(failure.Error())
			case result.Ok(budget):
				match continuation.Resume(budget) {
				case result.Err(failure):
					fmt.Println(failure.Error())
				case result.Ok(slice):
					var execution ExecutionSlice = slice
					match execution {
					case ExecutionSuspended(_):
						fmt.Println("suspended")
					case ExecutionWaiting(_), ExecutionRaised(_, _, _):
						fmt.Println("waiting")
					case ExecutionCompleted(_, progress):
						fmt.Println("completed", progress.Reductions, progress.Instructions)
					}
				}
			}
		}
	}
	// Output:
	// completed 1 2
}

// assayxport:unit gotp.vm.reduction-continuation-laws
func TestContinuationPartitionLaw(t *testing.T) {
	property := func(rawBudget uint8) bool {
		budgetValue := int(rawBudget%3) + 1
		program := []beam.Instruction{
			instruction("label", label(1)),
			instruction("move", integer(42), xregister(0)),
			instruction("call", unsigned(0), label(2)),
			instruction("return"),
			instruction("label", label(2)),
			instruction("move", xregister(0), xregister(1)),
			instruction("return"),
		}
		var wholeMachineResult result.Result[*Machine, Failure] = NewMachine(program, MachineConfig{})
		var slicedMachineResult result.Result[*Machine, Failure] = NewMachine(program, MachineConfig{})
		match wholeMachineResult {
		case result.Err(_):
			return false
		case result.Ok(wholeMachine):
			match slicedMachineResult {
			case result.Err(_):
				return false
			case result.Ok(slicedMachine):
				var whole result.Result[RunResult, Failure] = wholeMachine.Run(1)
				var started result.Result[*Continuation, Failure] = slicedMachine.Start(1)
				match whole {
				case result.Err(_):
					return false
				case result.Ok(wholeRun):
					match started {
					case result.Err(_):
						return false
					case result.Ok(continuation):
						var checked result.Result[VMReductionBudget, Failure] = NewVMReductionBudget(budgetValue)
						match checked {
						case result.Err(_):
							return false
						case result.Ok(budget):
							for slices := 0; slices < 8; slices++ {
								match continuation.Resume(budget) {
								case result.Err(_):
									return false
								case result.Ok(slice):
									var execution ExecutionSlice = slice
									match execution {
									case ExecutionSuspended(_):
									case ExecutionWaiting(_), ExecutionRaised(_, _, _):
										return false
									case ExecutionCompleted(value, progress):
										return operandInteger(value) == operandInteger(wholeRun.Value) &&
											progress.TotalInstructions == wholeRun.Steps
									}
								}
							}
							return false
						}
					}
				}
			}
		}
	}
	if failure := quick.Check(property, nil); failure != nil {
		t.Fatal(failure)
	}
}

func TestPinnedOTPDispatchReductionClasses(t *testing.T) {
	charged := []string{"call", "call_only", "call_last", "return", "send", "loop_rec_end"}
	for _, name := range charged {
		if OpcodeReductionCost(name) != 1 {
			t.Fatalf("%s cost = %d", name, OpcodeReductionCost(name))
		}
	}
	free := []string{"label", "func_info", "move", "jump", "allocate", "allocate_zero", "deallocate", "int_code_end", "loop_rec", "remove_message", "wait"}
	for _, name := range free {
		if OpcodeReductionCost(name) != 0 {
			t.Fatalf("%s cost = %d", name, OpcodeReductionCost(name))
		}
	}
}

func TestVMReductionBudgetRejectsNonpositiveValues(t *testing.T) {
	for _, value := range []int{-1, 0} {
		var checked result.Result[VMReductionBudget, Failure] = NewVMReductionBudget(value)
		match checked {
		case result.Err(_):
		case result.Ok(_):
			t.Fatalf("accepted reduction budget %d", value)
		}
	}
}

func TestContinuationStepLimitSpansSlices(t *testing.T) {
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("call_only", unsigned(0), label(1)),
	}
	match NewMachine(program, MachineConfig{StepLimit: 3}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		var started result.Result[*Continuation, Failure] = machine.Start(1)
		match started {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(continuation):
			var checked result.Result[VMReductionBudget, Failure] = NewVMReductionBudget(1)
			match checked {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(budget):
				for slice := 0; slice < 2; slice++ {
					match continuation.Resume(budget) {
					case result.Err(failure):
						t.Fatalf("slice %d: %s", slice, failure.Error())
					case result.Ok(_):
					}
				}
				match continuation.Resume(budget) {
				case result.Err(failure):
					var executionFailure Failure = failure
					match executionFailure {
					case StepLimitExceeded(limit):
						if limit != 3 { t.Fatalf("limit = %d", limit) }
					case _:
						t.Fatalf("unexpected failure: %s", failure.Error())
					}
				case result.Ok(_):
					t.Fatal("execution exceeded cumulative step limit")
				}
			}
		}
	}
}

func operandInteger(value term.Term) string {
	match term.Int64(value) {
	case option.Some(integer):
		return fmt.Sprint(integer)
	case option.None:
		return ""
	}
}
