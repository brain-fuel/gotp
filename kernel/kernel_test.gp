package kernel

import (
	"reflect"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func TestMailboxSelectiveReceivePreservesOrder(t *testing.T) {
	law := func(values []uint8) bool {
		var mailbox Mailbox
		var selected []uint8
		var remaining []uint8
		for index, value := range values {
			mailbox.Push(UserSignal(
				term.PID{}, uint64(index+1), term.Integer(int64(value)),
			))
			if value%2 == 0 {
				selected = append(selected, value)
			} else {
				remaining = append(remaining, value)
			}
		}
		var received []uint8
		for {
			next := mailbox.Receive(isEvenUserSignal)
			match next {
			case option.None:
				if !reflect.DeepEqual(received, selected) {
					return false
				}
				snapshot := mailbox.Snapshot()
				if len(snapshot) != len(remaining) {
					return false
				}
				for index, signal := range snapshot {
					match signalInteger(signal) {
					case option.Some(integer):
						if uint8(integer) != remaining[index] {
							return false
						}
					case option.None:
						return false
					}
				}
				return true
			case option.Some(signal):
				match signalInteger(signal) {
				case option.Some(integer):
					received = append(received, uint8(integer))
				case option.None:
					return false
				}
			}
		}
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 1_000})) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}

func TestSchedulerRoundRobinFairness(t *testing.T) {
	runtime := New(KernelConfig{})
	var trace []int
	behavior := func(id int) Behavior {
		steps := 0
		return func(context *Context) StepResult {
			trace = append(trace, id)
			steps++
			if steps == 3 {
				return Stop(term.MustAtom("normal"))
			}
			return Yield()
		}
	}
	mustSpawn(t, runtime, behavior(1), Unlinked(false))
	mustSpawn(t, runtime, behavior(2), Unlinked(false))
	report := runtime.Run(100)
	want := []int{1, 2, 1, 2, 1, 2}
	if !reflect.DeepEqual(trace, want) {
		t.Fatalf("trace = %v, want %v", trace, want)
	}
	if report.Reductions != 6 || report.Exited != 2 {
		t.Fatalf("report = %#v", report)
	}
}

func TestTerminalProcessReleasesMailboxStorage(t *testing.T) {
	runtime := New(KernelConfig{})
	pid := mustSpawn(t, runtime, func(context *Context) StepResult {
		return Stop(term.MustAtom("normal"))
	}, Unlinked(false))
	sender := term.PID{Node: 1, Number: 999, Creation: 1}
	match runtime.Send(sender, pid, term.Integer(42)) {
	case Delivered:
	case NoProcess:
		t.Fatal("send failed")
	}
	if runtime.processes[pid].mailbox.Capacity() == 0 {
		t.Fatal("mailbox did not allocate storage")
	}
	runtime.Run(1)
	mailbox := runtime.processes[pid].mailbox
	if mailbox.Len() != 0 || mailbox.Capacity() != 0 {
		t.Fatalf("terminal mailbox len/cap = %d/%d", mailbox.Len(), mailbox.Capacity())
	}
}

func TestMonitorDeliversDownAndWakesWaiter(t *testing.T) {
	runtime := New(KernelConfig{})
	var down option.Option[Signal] = option.None[Signal]
	watcher := mustSpawn(t, runtime, func(context *Context) StepResult {
		received := context.Receive(isDownSignal)
		match received {
		case option.None:
			return Wait()
		case option.Some(signal):
			down = option.Some[Signal](signal)
			return Stop(term.MustAtom("normal"))
		}
	}, Unlinked(false))
	target := mustSpawn(t, runtime, func(context *Context) StepResult {
		return Stop(term.MustAtom("crash"))
	}, Unlinked(false))
	var reference term.Reference
	match runtime.Monitor(watcher, target) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(found):
		reference = found
	}
	runtime.Run(100)
	match down {
	case option.None:
		t.Fatal("DOWN signal was not delivered")
	case option.Some(signal):
		match signal {
		case DownSignal(_, _, reason, foundReference, foundTarget):
			if foundTarget != target || foundReference != reference {
				t.Fatalf("DOWN target/reference mismatch")
			}
			assertAtom(t, reason, "crash")
		case _:
			t.Fatal("received signal is not DOWN")
		}
	}
}

func TestTrapExitConvertsLinkedExitToSignal(t *testing.T) {
	runtime := New(KernelConfig{})
	var received option.Option[Signal] = option.None[Signal]
	trapper := mustSpawn(t, runtime, func(context *Context) StepResult {
		found := context.Receive(isExitSignal)
		match found {
		case option.None:
			return Wait()
		case option.Some(signal):
			received = option.Some[Signal](signal)
			return Stop(term.MustAtom("normal"))
		}
	}, Unlinked(true))
	target := mustSpawn(t, runtime, func(context *Context) StepResult {
		return Stop(term.MustAtom("badarg"))
	}, Unlinked(false))
	match runtime.Link(trapper, target) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(_):
	}
	runtime.Run(100)
	match received {
	case option.None:
		t.Fatal("EXIT signal was not delivered")
	case option.Some(signal):
		match signal {
		case ExitSignal(from, _, reason, _):
			if from != target {
				t.Fatalf("EXIT source = %v", from)
			}
			assertAtom(t, reason, "badarg")
		case _:
			t.Fatal("received signal is not EXIT")
		}
	}
}

func TestAbnormalLinkedExitPropagates(t *testing.T) {
	runtime := New(KernelConfig{})
	victim := mustSpawn(t, runtime, func(context *Context) StepResult {
		return Wait()
	}, Unlinked(false))
	target := mustSpawn(t, runtime, func(context *Context) StepResult {
		return Stop(term.MustAtom("boom"))
	}, Unlinked(false))
	match runtime.Link(victim, target) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(_):
	}
	runtime.Run(100)
	match runtime.ProcessInfo(victim) {
	case option.None:
		t.Fatal("victim process record is missing")
	case option.Some(info):
		match info.Status {
		case Exited:
		case _:
			t.Fatalf("victim status = %#v", info.Status)
		}
		match info.ExitReason {
		case option.Some(reason):
			assertAtom(t, reason, "boom")
		case option.None:
			t.Fatal("victim has no exit reason")
		}
	}
}

func TestPerRouteSignalSequenceIsMonotonic(t *testing.T) {
	runtime := New(KernelConfig{})
	receiver := mustSpawn(t, runtime, func(context *Context) StepResult {
		return Wait()
	}, Unlinked(false))
	sender := term.PID{Node: 1, Number: 999, Creation: 1}
	for value := int64(0); value < 100; value++ {
		match runtime.Send(sender, receiver, term.Integer(value)) {
		case Delivered:
		case NoProcess:
			t.Fatal("send failed")
		}
	}
	match runtime.ProcessInfo(receiver) {
	case option.None:
		t.Fatal("receiver process record is missing")
	case option.Some(info):
		if info.MailboxLength != 100 {
			t.Fatalf("mailbox length = %d", info.MailboxLength)
		}
	}
	current := runtime.processes[receiver]
	for index, signal := range current.mailbox.Snapshot() {
		if signalSequence(signal) != uint64(index+1) {
			t.Fatalf("sequence %d = %d", index, signalSequence(signal))
		}
	}
}

func mustSpawn(
	t *testing.T,
	runtime *Kernel,
	behavior Behavior,
	policy SpawnPolicy,
) term.PID {
	t.Helper()
	match runtime.Spawn(behavior, policy) {
	case result.Ok(pid):
		return pid
	case result.Err(failure):
		t.Fatal(failure.Error())
		return term.PID{}
	}
}

func assertAtom(t *testing.T, value term.Term, want string) {
	t.Helper()
	match value {
	case term.AtomTerm(name):
		if name != want {
			t.Fatalf("atom = %q, want %q", name, want)
		}
	case _:
		t.Fatal("term is not an atom")
	}
}

func isEvenUserSignal(signal Signal) bool {
	match signalInteger(signal) {
	case option.Some(integer):
		return integer%2 == 0
	case option.None:
		return false
	}
}

func signalInteger(signal Signal) option.Option[int64] {
	match signal {
	case UserSignal(_, _, value):
		match value {
		case term.IntegerTerm(integer):
			if integer.IsInt64() {
				return option.Some[int64](integer.Int64())
			}
			return option.None[int64]
		case _:
			return option.None[int64]
		}
	case _:
		return option.None[int64]
	}
}

func isDownSignal(signal Signal) bool {
	match signal {
	case DownSignal(_, _, _, _, _):
		return true
	case _:
		return false
	}
}

func isExitSignal(signal Signal) bool {
	match signal {
	case ExitSignal(_, _, _, _):
		return true
	case _:
		return false
	}
}
