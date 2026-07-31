package vm

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

// assayxport:unit gotp.vm.host-effect-laws
func TestSendEffectProperty(t *testing.T) {
	property := func(message int64) bool {
		program := []beam.Instruction{
			instruction("label", label(1)),
			instruction("send"),
			instruction("return"),
		}
		match NewMachine(program, MachineConfig{}) {
		case result.Err(_):
			return false
		case result.Ok(machine):
			destination := term.PIDValue(term.PID{Node: 1, Number: 2, Creation: 1})
			if !setRuntimeRegister(machine, 0, destination) ||
				!setRuntimeRegister(machine, 1, term.Integer(message)) {
				return false
			}
			var started result.Result[*Continuation, Failure] = machine.Start(1)
			match started {
			case result.Err(_):
				return false
			case result.Ok(continuation):
				observed := term.InvalidValue()
				var hostResult result.Result[HostCapabilities, Failure] = HostWithSend(
					func(to term.Term, value term.Term) SendOutcome {
						if !term.Equal(to, destination) { return SendRejected("wrong destination") }
						observed = term.Clone(value)
						return MessageSent(value)
					},
				)
				var budgetResult result.Result[VMReductionBudget, Failure] = NewVMReductionBudget(1)
				match hostResult {
				case result.Err(_):
					return false
				case result.Ok(host):
					match budgetResult {
					case result.Err(_):
						return false
					case result.Ok(budget):
						match continuation.ResumeWithHost(budget, host) {
						case result.Err(_):
							return false
						case result.Ok(_):
							match machine.X(0) {
							case result.Err(_):
								return false
							case result.Ok(value):
								match term.Int64(value) {
								case option.None:
									return false
								case option.Some(found):
									return found == message && term.Equal(observed, value)
								}
							}
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

func TestSendRequiresCapability(t *testing.T) {
	program := []beam.Instruction{
		instruction("label", label(1)),
		instruction("send"),
	}
	match NewMachine(program, MachineConfig{}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(machine):
		setRuntimeRegister(machine, 0, term.PIDValue(term.PID{Node: 1, Number: 2, Creation: 1}))
		setRuntimeRegister(machine, 1, term.MustAtom("hello"))
		match machine.Run(1) {
		case result.Err(_):
		case result.Ok(_):
			t.Fatal("send executed without host capability")
		}
	}
}

func setRuntimeRegister(machine *Machine, index int, value term.Term) bool {
	match machine.SetX(index, value) {
	case result.Err(_): return false
	case result.Ok(_): return true
	}
}
