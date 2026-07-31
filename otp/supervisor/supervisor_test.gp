package supervisor

import (
	"reflect"
	"testing"
	"testing/quick"
	"time"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

type fixedClock struct {
	now time.Time
}

func (clock *fixedClock) Now() time.Time {
	return clock.now
}

func TestRestartIndexLaws(t *testing.T) {
	law := func(rawCount uint8, rawFailed uint8) bool {
		count := int(rawCount%32) + 1
		failed := int(rawFailed) % count
		one := restartIndexes(OneForOne(), failed, count)
		all := restartIndexes(OneForAll(), failed, count)
		rest := restartIndexes(RestForOne(), failed, count)
		if !reflect.DeepEqual(one, []int{failed}) ||
			len(all) != count ||
			len(rest) != count-failed {
			return false
		}
		for index := range all {
			if all[index] != index {
				return false
			}
		}
		for index := range rest {
			if rest[index] != failed+index {
				return false
			}
		}
		return true
	}
	match result.Of(true, quick.Check(law, nil)) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}

func TestOneForOneRestartsOnlyFailedChild(t *testing.T) {
	starts := []int{0, 0}
	specs := []ChildSpec{
		crashOnceSpec("a", 0, starts),
		waitSpec("b", 1, starts, Permanent()),
	}
	runtime, supervisor, supervisorPID := startSupervisor(t, OneForOne(), specs, 10)
	runtime.Run(100)
	if !reflect.DeepEqual(starts, []int{2, 1}) {
		t.Fatalf("starts = %v", starts)
	}
	assertRunningChildren(t, runtime, supervisor, supervisorPID, 2)
}

func TestOneForAllDoesNotRestartTemporarySibling(t *testing.T) {
	starts := []int{0, 0}
	specs := []ChildSpec{
		crashOnceSpec("a", 0, starts),
		waitSpec("temporary", 1, starts, Temporary()),
	}
	runtime, supervisor, _ := startSupervisor(t, OneForAll(), specs, 10)
	runtime.Run(100)
	if !reflect.DeepEqual(starts, []int{2, 1}) {
		t.Fatalf("starts = %v", starts)
	}
	match supervisor.Children()[1].State {
	case Inactive:
	case _:
		t.Fatalf("temporary child = %#v", supervisor.Children()[1])
	}
}

func TestRestForOneRestartsFailedChildAndFollowingChildren(t *testing.T) {
	starts := []int{0, 0, 0}
	specs := []ChildSpec{
		waitSpec("a", 0, starts, Permanent()),
		crashOnceSpec("b", 1, starts),
		waitSpec("c", 2, starts, Permanent()),
	}
	runtime, supervisor, _ := startSupervisor(t, RestForOne(), specs, 10)
	runtime.Run(200)
	if !reflect.DeepEqual(starts, []int{1, 2, 2}) {
		t.Fatalf("starts = %v", starts)
	}
	for _, child := range supervisor.Children() {
		match child.State {
		case Running(_):
		case _:
			t.Fatalf("child = %#v", child)
		}
	}
}

func TestTransientNormalExitIsNotRestarted(t *testing.T) {
	starts := 0
	spec := ChildSpec{
		ID: "transient", Restart: Transient(),
		Start: func(context *kernel.Context) result.Result[term.PID, Failure] {
			starts++
			return SpawnChild(context, func(context *kernel.Context) kernel.StepResult {
				return kernel.Stop(term.MustAtom("normal"))
			})
		},
	}
	runtime, supervisor, _ := startSupervisor(t, OneForOne(), []ChildSpec{spec}, 10)
	runtime.Run(100)
	if starts != 1 {
		t.Fatalf("starts = %d", starts)
	}
	match supervisor.Children()[0].State {
	case Pending:
	case _:
		t.Fatalf("transient child = %#v", supervisor.Children()[0])
	}
}

func TestRestartIntensityStopsSupervisor(t *testing.T) {
	starts := 0
	spec := ChildSpec{
		ID: "loop", Restart: Permanent(),
		Start: func(context *kernel.Context) result.Result[term.PID, Failure] {
			starts++
			return SpawnChild(context, func(context *kernel.Context) kernel.StepResult {
				return kernel.Stop(term.MustAtom("crash"))
			})
		},
	}
	runtime, _, supervisorPID := startSupervisor(t, OneForOne(), []ChildSpec{spec}, 2)
	runtime.Run(100)
	match runtime.ProcessInfo(supervisorPID) {
	case option.None:
		t.Fatal("supervisor process record is missing")
	case option.Some(info):
		match info.Status {
		case kernel.Exited:
		case _:
			t.Fatalf("supervisor = %#v", info)
		}
		match info.ExitReason {
		case option.Some(reason):
			assertAtom(t, reason, "shutdown")
		case option.None:
			t.Fatal("supervisor has no exit reason")
		}
	}
	if starts != 3 {
		t.Fatalf("starts = %d, want 3", starts)
	}
}

func startSupervisor(
	t *testing.T,
	strategy Strategy,
	specs []ChildSpec,
	maxRestarts int,
) (*kernel.Kernel, *Supervisor, term.PID) {
	t.Helper()
	var supervisor *Supervisor
	match New(Config{
		Strategy: strategy, MaxRestarts: maxRestarts, Period: time.Minute,
		Clock: &fixedClock{now: time.Unix(1_000, 0)}, Children: specs,
	}) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(found):
		supervisor = found
	}
	runtime := kernel.New(kernel.KernelConfig{})
	var pid term.PID
	match runtime.Spawn(supervisor.Behavior(), kernel.Unlinked(false)) {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(found):
		pid = found
	}
	return runtime, supervisor, pid
}

func crashOnceSpec(id string, index int, starts []int) ChildSpec {
	return ChildSpec{
		ID: id, Restart: Permanent(),
		Start: func(context *kernel.Context) result.Result[term.PID, Failure] {
			starts[index]++
			incarnation := starts[index]
			return SpawnChild(context, func(context *kernel.Context) kernel.StepResult {
				if incarnation == 1 {
					return kernel.Stop(term.MustAtom("crash"))
				}
				return kernel.Wait()
			})
		},
	}
}

func waitSpec(
	id string,
	index int,
	starts []int,
	policy RestartPolicy,
) ChildSpec {
	return ChildSpec{
		ID: id, Restart: policy,
		Start: func(context *kernel.Context) result.Result[term.PID, Failure] {
			starts[index]++
			return SpawnChild(context, func(context *kernel.Context) kernel.StepResult {
				return kernel.Wait()
			})
		},
	}
}

func assertRunningChildren(
	t *testing.T,
	runtime *kernel.Kernel,
	supervisor *Supervisor,
	supervisorPID term.PID,
	count int,
) {
	t.Helper()
	match runtime.ProcessInfo(supervisorPID) {
	case option.None:
		t.Fatal("supervisor process record is missing")
	case option.Some(info):
		match info.Status {
		case kernel.Waiting:
		case _:
			t.Fatalf("supervisor = %#v", info)
		}
	}
	children := supervisor.Children()
	if len(children) != count {
		t.Fatalf("children = %d", len(children))
	}
	for _, child := range children {
		match child.State {
		case Running(_):
		case _:
			t.Fatalf("child = %#v", child)
		}
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
