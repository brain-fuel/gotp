package supervisor

import (
	"fmt"
	"sort"
	"time"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

type Strategy enum {
	OneForOne()
	OneForAll()
	RestForOne()
}

type RestartPolicy enum {
	Permanent()
	Transient()
	Temporary()
}

type Clock interface {
	Now() time.Time
}

type RealClock struct{}

func (RealClock) Now() time.Time {
	return time.Now()
}

type Failure enum {
	InvalidConfiguration(Detail string)
	ChildStartFailed(ID string, Detail string)
	KernelFailure(Cause kernel.Failure)
}

func (failure Failure) Error() string {
	match failure {
	case InvalidConfiguration(detail):
		return "gotp/supervisor: invalid configuration: " + detail
	case ChildStartFailed(id, detail):
		return fmt.Sprintf("gotp/supervisor: child %q failed to start: %s", id, detail)
	case KernelFailure(cause):
		return "gotp/supervisor: " + cause.Error()
	}
}

type StartChild func(*kernel.Context) result.Result[term.PID, Failure]

type ChildSpec struct {
	ID      string
	Start   StartChild
	Restart RestartPolicy
}

type Config struct {
	Strategy    Strategy
	MaxRestarts int
	Period      time.Duration
	Clock       Clock
	Children    []ChildSpec
}

type ChildLifecycle enum {
	Pending()
	Running(PID term.PID)
	Inactive()
}

type ChildInfo struct {
	ID      string
	Restart RestartPolicy
	State   ChildLifecycle
}

type childState struct {
	spec  ChildSpec
	state ChildLifecycle
}

type Initialization enum {
	Starting()
	Initialized()
}

type Supervisor struct {
	strategy     Strategy
	maxRestarts  int
	period       time.Duration
	clock        Clock
	children     []childState
	byPID        map[term.PID]int
	suppressed   map[term.PID]bool
	restartTimes []time.Time
	startQueue   []int
	initializing Initialization
}

func New(config Config) result.Result[*Supervisor, Failure] {
	if config.MaxRestarts < 0 {
		return result.Err[*Supervisor, Failure](InvalidConfiguration("max restarts cannot be negative"))
	}
	if config.Period <= 0 {
		config.Period = 5 * time.Second
	}
	if config.Clock == nil {
		return result.Err[*Supervisor, Failure](InvalidConfiguration("an explicit clock capability is required"))
	}
	children := make([]childState, len(config.Children))
	ids := make(map[string]bool)
	for index, spec := range config.Children {
		if spec.ID == "" {
			return result.Err[*Supervisor, Failure](InvalidConfiguration(fmt.Sprintf(
				"child %d has an empty ID",
				index,
			)))
		}
		if ids[spec.ID] {
			return result.Err[*Supervisor, Failure](InvalidConfiguration(fmt.Sprintf(
				"duplicate child ID %q",
				spec.ID,
			)))
		}
		if spec.Start == nil {
			return result.Err[*Supervisor, Failure](InvalidConfiguration(fmt.Sprintf(
				"child %q has no start function",
				spec.ID,
			)))
		}
		ids[spec.ID] = true
		children[index] = childState{spec: spec, state: Pending()}
	}
	startQueue := make([]int, len(children))
	for index := range startQueue {
		startQueue[index] = index
	}
	return result.Ok[*Supervisor, Failure](&Supervisor{
		strategy: config.Strategy, maxRestarts: config.MaxRestarts,
		period: config.Period, clock: config.Clock, children: children,
		byPID: make(map[term.PID]int), suppressed: make(map[term.PID]bool),
		startQueue: startQueue, initializing: Starting(),
	})
}

func (supervisor *Supervisor) Behavior() kernel.Behavior {
	first := true
	return func(context *kernel.Context) kernel.StepResult {
		if first {
			context.SetTrapExit(true)
			first = false
		}
		if len(supervisor.startQueue) > 0 {
			index := supervisor.startQueue[0]
			supervisor.startQueue = supervisor.startQueue[1:]
			match supervisor.startChild(context, index) {
			case result.Err(failure):
				supervisor.shutdownChildren(context)
				return kernel.Stop(startFailure(supervisor.children[index].spec.ID, failure))
			case result.Ok(_):
			}
			if len(supervisor.startQueue) == 0 {
				supervisor.initializing = Initialized()
			}
			return kernel.Yield()
		}

		received := context.Receive(isExitSignal)
		match received {
		case option.None:
			return kernel.Wait()
		case option.Some(signal):
			match signal {
			case kernel.ExitSignal(from, _, reason, _):
				return supervisor.childExit(context, from, reason)
			case _:
				return kernel.Yield()
			}
		}
	}
}

func (supervisor *Supervisor) childExit(
	context *kernel.Context,
	from term.PID,
	reason term.Term,
) kernel.StepResult {
	if supervisor.suppressed[from] {
		delete(supervisor.suppressed, from)
		return kernel.Yield()
	}
	index, child := supervisor.byPID[from]
	if !child {
		return kernel.Yield()
	}
	delete(supervisor.byPID, from)
	supervisor.children[index].state = Pending()

	if !shouldRestart(supervisor.children[index].spec.Restart, reason) {
		match supervisor.children[index].spec.Restart {
		case Temporary:
			supervisor.children[index].state = Inactive()
		case _:
		}
		return kernel.Yield()
	}
	if supervisor.restartIntensityExceeded() {
		supervisor.shutdownChildren(context)
		return kernel.Stop(term.MustAtom("shutdown"))
	}

	affected := restartIndexes(supervisor.strategy, index, len(supervisor.children))
	supervisor.stopAffected(context, affected, from)
	supervisor.startQueue = supervisor.startQueue[:0]
	for _, childIndex := range affected {
		child := &supervisor.children[childIndex]
		match child.state {
		case Inactive:
		case _:
			match child.spec.Restart {
			case Temporary:
				child.state = Inactive()
			case _:
				child.state = Pending()
				supervisor.startQueue = append(supervisor.startQueue, childIndex)
			}
		}
	}
	return kernel.Yield()
}

func (supervisor *Supervisor) Children() []ChildInfo {
	children := make([]ChildInfo, len(supervisor.children))
	for index, child := range supervisor.children {
		children[index] = ChildInfo{
			ID: child.spec.ID, Restart: child.spec.Restart, State: child.state,
		}
	}
	return children
}

type SupervisorMutation enum {
	SupervisorMutated()
}

func (supervisor *Supervisor) startChild(
	context *kernel.Context,
	index int,
) result.Result[SupervisorMutation, Failure] {
	child := &supervisor.children[index]
	match child.state {
	case Inactive:
		return result.Ok[SupervisorMutation, Failure](SupervisorMutated())
	case _:
	}
	match child.spec.Start(context) {
	case result.Err(failure):
		return result.Err[SupervisorMutation, Failure](ChildStartFailed(
			child.spec.ID,
			failure.Error(),
		))
	case result.Ok(pid):
		if !pid.Valid() {
			return result.Err[SupervisorMutation, Failure](ChildStartFailed(
				child.spec.ID,
				"start returned an invalid PID",
			))
		}
		_, duplicate := supervisor.byPID[pid]
		if duplicate {
			return result.Err[SupervisorMutation, Failure](ChildStartFailed(
				child.spec.ID,
				"start returned a PID owned by another child",
			))
		}
		match context.Link(pid) {
		case result.Err(cause):
			return result.Err[SupervisorMutation, Failure](KernelFailure(cause))
		case result.Ok(_):
			child.state = Running(pid)
			supervisor.byPID[pid] = index
			return result.Ok[SupervisorMutation, Failure](SupervisorMutated())
		}
	}
}

func (supervisor *Supervisor) restartIntensityExceeded() bool {
	now := supervisor.clock.Now()
	cutoff := now.Add(-supervisor.period)
	kept := supervisor.restartTimes[:0]
	for _, prior := range supervisor.restartTimes {
		if !prior.Before(cutoff) && !prior.After(now) {
			kept = append(kept, prior)
		}
	}
	supervisor.restartTimes = append(kept, now)
	return len(supervisor.restartTimes) > supervisor.maxRestarts
}

func (supervisor *Supervisor) stopAffected(
	context *kernel.Context,
	affected []int,
	alreadyExited term.PID,
) {
	for position := len(affected) - 1; position >= 0; position-- {
		child := &supervisor.children[affected[position]]
		match child.state {
		case Running(pid):
			if pid != alreadyExited {
				supervisor.suppressed[pid] = true
				delete(supervisor.byPID, pid)
				context.Terminate(pid, term.MustAtom("shutdown"))
			}
			child.state = Pending()
		case _:
		}
	}
}

func (supervisor *Supervisor) shutdownChildren(context *kernel.Context) {
	indexes := make([]int, len(supervisor.children))
	for index := range indexes {
		indexes[index] = index
	}
	supervisor.stopAffected(context, indexes, term.PID{})
}

func shouldRestart(policy RestartPolicy, reason term.Term) bool {
	match policy {
	case Permanent:
		return true
	case Temporary:
		return false
	case Transient:
		return !isNormalShutdown(reason)
	}
}

func isNormalShutdown(reason term.Term) bool {
	match reason {
	case term.AtomTerm(name):
		return name == "normal" || name == "shutdown"
	case term.TupleTerm(values):
		if len(values) != 2 {
			return false
		}
		match values[0] {
		case term.AtomTerm(name):
			return name == "shutdown"
		case _:
			return false
		}
	case _:
		return false
	}
}

func restartIndexes(strategy Strategy, failed int, count int) []int {
	var indexes []int
	match strategy {
	case OneForOne:
		indexes = []int{failed}
	case OneForAll:
		indexes = make([]int, count)
		for index := range indexes {
			indexes[index] = index
		}
	case RestForOne:
		indexes = make([]int, count-failed)
		for index := range indexes {
			indexes[index] = failed + index
		}
	}
	sort.Ints(indexes)
	return indexes
}

func startFailure(id string, failure Failure) term.Term {
	return term.Tuple(
		term.MustAtom("start_error"),
		term.Binary([]byte(id)),
		term.Binary([]byte(failure.Error())),
	)
}

func isExitSignal(signal kernel.Signal) bool {
	match signal {
	case kernel.ExitSignal(_, _, _, _):
		return true
	case _:
		return false
	}
}

func SpawnChild(
	context *kernel.Context,
	behavior kernel.Behavior,
) result.Result[term.PID, Failure] {
	match context.Spawn(behavior, kernel.Unlinked(false)) {
	case result.Ok(pid):
		return result.Ok[term.PID, Failure](pid)
	case result.Err(cause):
		return result.Err[term.PID, Failure](KernelFailure(cause))
	}
}
