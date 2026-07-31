package erts

import (
	"fmt"
	"math/big"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

func ExampleVMProcess_Behavior() {
	program := []beam.Instruction{
		vmInstruction("label", vmLabel(1)),
		vmInstruction("move", vmInteger(42), vmXRegister(0)),
		vmInstruction("return"),
	}
	match vm.NewMachine(program, vm.MachineConfig{}) {
	case result.Err(failure):
		fmt.Println(failure.Error())
	case result.Ok(machine):
		match NewVMProcess(machine, 1) {
		case result.Err(failure):
			fmt.Println(failure.Error())
		case result.Ok(process):
			runtime := kernel.New(kernel.KernelConfig{})
			match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
			case result.Err(failure):
				fmt.Println(failure.Error())
			case result.Ok(_):
				match kernel.NewReductionBudget(1) {
				case result.Err(failure):
					fmt.Println(failure.Error())
				case result.Ok(budget):
					report := runtime.RunSlice(budget)
					fmt.Println(report.Run.Reductions, report.Run.Exited)
				}
			}
		}
	}
	// Output:
	// 1 1
}

// assayxport:unit gotp.erts.vm-process-laws
func TestKernelVMReductionPartitionProperty(t *testing.T) {
	property := func(rawBudget uint8) bool {
		group := int(rawBudget%3) + 1
		process, runtime, valid := scheduledVMProcess()
		if !valid {
			return false
		}
		var checked result.Result[kernel.ReductionBudget, kernel.SchedulerFailure] = kernel.NewReductionBudget(group)
		match checked {
		case result.Err(_):
			return false
		case result.Ok(budget):
			totalKernelReductions := 0
			for slices := 0; slices < 4; slices++ {
				report := runtime.RunSlice(budget)
				totalKernelReductions += report.Run.Reductions
				var state VMProcessState = process.State()
				match state {
				case VMProcessRunning:
				case VMProcessSuspended(_, _):
				case VMProcessWaiting(_, _):
					return false
				case VMProcessFailed(_, _, _):
					return false
				case VMProcessCompleted(value, reductions, _):
					return totalKernelReductions == 3 && reductions == 3 &&
						vmOperandInteger(value) == "42"
				}
			}
			return false
		}
	}
	if failure := quick.Check(property, nil); failure != nil {
		t.Fatal(failure)
	}
}

func TestVMProcessRejectsNilMachine(t *testing.T) {
	match NewVMProcess(nil, 1) {
	case result.Err(_):
	case result.Ok(_):
		t.Fatal("nil VM machine was accepted")
	}
}

func TestVMCompletionExitsNormally(t *testing.T) {
	program := []beam.Instruction{
		vmInstruction("label", vmLabel(1)),
		vmInstruction("move", vmInteger(42), vmXRegister(0)),
		vmInstruction("return"),
	}
	match vm.NewMachine(program, vm.MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match NewVMProcess(machine, 1) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(process):
			runtime := kernel.New(kernel.KernelConfig{})
			match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(pid):
				runtime.RunSlice(mustKernelBudget(t, 1))
				match runtime.ProcessInfo(pid) {
				case option.None:
					t.Fatal("completed VM process disappeared")
				case option.Some(info):
					match info.ExitReason {
					case option.None:
						t.Fatal("completed VM process has no exit reason")
					case option.Some(reason):
						match term.AtomName(reason) {
						case option.Some(name):
							if name != "normal" { t.Fatalf("exit reason = %s", name) }
						case option.None:
							t.Fatal("completion exit reason is not an atom")
						}
					}
				}
			}
		}
	}
}

func TestVMFailureBecomesStructuredProcessExit(t *testing.T) {
	program := []beam.Instruction{
		vmInstruction("label", vmLabel(1)),
		vmInstruction("send"),
	}
	match vm.NewMachine(program, vm.MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		match NewVMProcess(machine, 1) {
		case result.Err(failure):
			t.Fatal(failure.Error())
		case result.Ok(process):
			runtime := kernel.New(kernel.KernelConfig{})
			var spawned result.Result[term.PID, kernel.Failure] = runtime.Spawn(
				process.Behavior(),
				kernel.Unlinked(false),
			)
			match spawned {
			case result.Err(failure):
				t.Fatal(failure.Error())
			case result.Ok(pid):
				runtime.RunSlice(mustKernelBudget(t, 1))
				match runtime.ProcessInfo(pid) {
				case option.None:
					t.Fatal("VM process disappeared")
				case option.Some(info):
					match info.ExitReason {
					case option.None:
						t.Fatal("VM failure has no exit reason")
					case option.Some(reason):
						match term.Elements(reason) {
						case option.None:
							t.Fatal("VM failure reason is not a tuple")
						case option.Some(elements):
							if len(elements) != 2 { t.Fatalf("reason elements = %d", len(elements)) }
							match term.AtomName(elements[0]) {
							case option.Some(name):
								if name != "gotp_vm_failure" { t.Fatalf("reason tag = %s", name) }
							case option.None:
								t.Fatal("VM failure reason tag is not an atom")
							}
						}
					}
				}
			}
		}
	}
}

func scheduledVMProcess() (*VMProcess, *kernel.Kernel, bool) {
	program := []beam.Instruction{
		vmInstruction("label", vmLabel(1)),
		vmInstruction("move", vmInteger(42), vmXRegister(0)),
		vmInstruction("call", vmUnsigned(0), vmLabel(2)),
		vmInstruction("return"),
		vmInstruction("label", vmLabel(2)),
		vmInstruction("move", vmXRegister(0), vmXRegister(1)),
		vmInstruction("return"),
	}
	match vm.NewMachine(program, vm.MachineConfig{}) {
	case result.Err(_):
		return nil, nil, false
	case result.Ok(machine):
		match NewVMProcess(machine, 1) {
		case result.Err(_):
			return nil, nil, false
		case result.Ok(process):
			runtime := kernel.New(kernel.KernelConfig{})
			match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
			case result.Err(_):
				return nil, nil, false
			case result.Ok(_):
				return process, runtime, true
			}
		}
	}
}

func mustKernelBudget(t *testing.T, value int) kernel.ReductionBudget {
	t.Helper()
	match kernel.NewReductionBudget(value) {
	case result.Err(failure):
		t.Fatal(failure.Error())
		return kernel.ReductionBudget{}
	case result.Ok(budget):
		return budget
	}
}

func vmInstruction(name string, operands ...beam.Operand) beam.Instruction {
	return beam.Instruction{Opcode: beam.Opcode{Name: name, Arity: len(operands)}, Operands: operands}
}

func vmUnsigned(value int64) beam.Operand { return beam.UnsignedOperand(big.NewInt(value)) }
func vmInteger(value int64) beam.Operand { return beam.IntegerOperand(big.NewInt(value)) }
func vmLabel(value int64) beam.Operand { return beam.LabelOperand(big.NewInt(value)) }
func vmXRegister(value int64) beam.Operand { return beam.XRegisterOperand(big.NewInt(value)) }

func vmOperandInteger(value term.Term) string {
	match term.Int64(value) {
	case option.Some(integer): return fmt.Sprint(integer)
	case option.None: return ""
	}
}
