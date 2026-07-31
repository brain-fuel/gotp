package kernel

import (
	"fmt"
	"sort"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type ProcessStatus enum {
	Runnable()
	Waiting()
	Exited()
}

type StepResult enum {
	Yield()
	Wait()
	Stop(Reason term.Term)
}

type Behavior func(*Context) StepResult

type SpawnPolicy enum {
	Unlinked(TrapExit bool)
	Linked(To term.PID, TrapExit bool)
}

type KernelConfig struct {
	Node     uint32
	Creation uint32
}

type RunReport struct {
	Reductions int
	Runnable   int
	Waiting    int
	Exited     int
}

type ProcessInfo struct {
	PID           term.PID
	Status        ProcessStatus
	TrapExit      bool
	MailboxLength int
	Links         []term.PID
	ExitReason    option.Option[term.Term]
}

type Failure enum {
	NilBehavior()
	MissingProcess(Role string, PID term.PID)
	InvalidLink(Detail string)
}

func (failure Failure) Error() string {
	match failure {
	case NilBehavior:
		return "gotp/kernel: behavior is nil"
	case MissingProcess(role, pid):
		return fmt.Sprintf("gotp/kernel: %s process %v does not exist", role, pid)
	case InvalidLink(detail):
		return "gotp/kernel: invalid link: " + detail
	}
}

type Delivery enum {
	Delivered()
	NoProcess()
}

type KernelMutation enum {
	KernelMutated()
}

type MonitorRemoval enum {
	MonitorRemoved()
	MonitorAbsent()
}

type route struct {
	from term.PID
	to   term.PID
}

type process struct {
	pid         term.PID
	behavior    Behavior
	status      ProcessStatus
	mailbox     Mailbox
	trapExit    bool
	links       map[term.PID]struct{}
	monitoring  map[term.Reference]term.PID
	monitoredBy map[term.Reference]term.PID
	exitReason  option.Option[term.Term]
}

type Kernel struct {
	config        KernelConfig
	nextPID       uint64
	nextReference uint32
	processes     map[term.PID]*process
	runQueue      []term.PID
	queued        map[term.PID]bool
	sequences     map[route]uint64
}

func New(config KernelConfig) *Kernel {
	if config.Node == 0 {
		config.Node = 1
	}
	if config.Creation == 0 {
		config.Creation = 1
	}
	return &Kernel{
		config:    config,
		processes: make(map[term.PID]*process),
		queued:    make(map[term.PID]bool),
		sequences: make(map[route]uint64),
	}
}

func (kernel *Kernel) Spawn(
	behavior Behavior,
	policy SpawnPolicy,
) result.Result[term.PID, Failure] {
	if behavior == nil {
		return result.Err[term.PID, Failure](NilBehavior())
	}
	var link option.Option[term.PID] = option.None[term.PID]
	trapExit := false
	match policy {
	case Unlinked(trap):
		trapExit = trap
	case Linked(target, trap):
		match kernel.liveProcess(target) {
		case option.None:
			return result.Err[term.PID, Failure](MissingProcess("link target", target))
		case option.Some(_):
			link = option.Some[term.PID](target)
			trapExit = trap
		}
	}
	kernel.nextPID++
	pid := term.PID{
		Node: kernel.config.Node, Number: kernel.nextPID, Creation: kernel.config.Creation,
	}
	current := &process{
		pid: pid, behavior: behavior, status: Runnable(), trapExit: trapExit,
		links: make(map[term.PID]struct{}),
		monitoring: make(map[term.Reference]term.PID),
		monitoredBy: make(map[term.Reference]term.PID),
		exitReason: option.None[term.Term],
	}
	kernel.processes[pid] = current
	kernel.enqueueRunnable(pid)
	match link {
	case option.None:
	case option.Some(target):
		match kernel.Link(pid, target) {
		case result.Ok(_):
		case result.Err(failure):
			return result.Err[term.PID, Failure](failure)
		}
	}
	return result.Ok[term.PID, Failure](pid)
}

func (kernel *Kernel) Send(
	from term.PID,
	to term.PID,
	message term.Term,
) Delivery {
	return kernel.enqueueSignal(to, UserSignal(from, 0, message.Clone()))
}

func (kernel *Kernel) Link(
	left term.PID,
	right term.PID,
) result.Result[KernelMutation, Failure] {
	if left == right {
		return result.Ok[KernelMutation, Failure](KernelMutated())
	}
	match kernel.liveProcess(left) {
	case option.None:
		return result.Err[KernelMutation, Failure](MissingProcess("left link", left))
	case option.Some(leftProcess):
		match kernel.liveProcess(right) {
		case option.None:
			return result.Err[KernelMutation, Failure](MissingProcess("right link", right))
		case option.Some(rightProcess):
			leftProcess.links[right] = struct{}{}
			rightProcess.links[left] = struct{}{}
			return result.Ok[KernelMutation, Failure](KernelMutated())
		}
	}
}

func (kernel *Kernel) Unlink(left term.PID, right term.PID) KernelMutation {
	match kernel.liveProcess(left) {
	case option.Some(leftProcess):
		delete(leftProcess.links, right)
	case option.None:
	}
	match kernel.liveProcess(right) {
	case option.Some(rightProcess):
		delete(rightProcess.links, left)
	case option.None:
	}
	return KernelMutated()
}

func (kernel *Kernel) Monitor(
	watcher term.PID,
	target term.PID,
) result.Result[term.Reference, Failure] {
	match kernel.liveProcess(watcher) {
	case option.None:
		return result.Err[term.Reference, Failure](MissingProcess("watcher", watcher))
	case option.Some(watcherProcess):
		reference := kernel.newReference()
		match kernel.liveProcess(target) {
		case option.None:
			kernel.enqueueSignal(watcher, DownSignal(
				target, 0, term.MustAtom("noproc"), reference, target,
			))
		case option.Some(targetProcess):
			watcherProcess.monitoring[reference] = target
			targetProcess.monitoredBy[reference] = watcher
		}
		return result.Ok[term.Reference, Failure](reference)
	}
}

func (kernel *Kernel) Demonitor(
	watcher term.PID,
	reference term.Reference,
	flush bool,
) MonitorRemoval {
	match kernel.liveProcess(watcher) {
	case option.None:
		return MonitorAbsent()
	case option.Some(watcherProcess):
		target, exists := watcherProcess.monitoring[reference]
		if exists {
			delete(watcherProcess.monitoring, reference)
			match kernel.liveProcess(target) {
			case option.Some(targetProcess):
				delete(targetProcess.monitoredBy, reference)
			case option.None:
			}
		}
		if flush {
			watcherProcess.mailbox.Remove(func(signal Signal) bool {
				match signal {
				case DownSignal(_, _, _, found, _):
					return found == reference
				case _:
					return false
				}
			})
		}
		if exists {
			return MonitorRemoved()
		}
		return MonitorAbsent()
	}
}

func (kernel *Kernel) SetTrapExit(
	pid term.PID,
	enabled bool,
) result.Result[KernelMutation, Failure] {
	match kernel.liveProcess(pid) {
	case option.None:
		return result.Err[KernelMutation, Failure](MissingProcess("trap-exit target", pid))
	case option.Some(current):
		current.trapExit = enabled
		return result.Ok[KernelMutation, Failure](KernelMutated())
	}
}

func (kernel *Kernel) Exit(pid term.PID, reason term.Term) Delivery {
	match kernel.liveProcess(pid) {
	case option.None:
		return NoProcess()
	case option.Some(current):
		kernel.terminate(current, reason)
		return Delivered()
	}
}

func (kernel *Kernel) Run(maxReductions int) RunReport {
	if maxReductions <= 0 {
		maxReductions = 1_000_000
	}
	reductions := 0
	for len(kernel.runQueue) > 0 && reductions < maxReductions {
		pid := kernel.runQueue[0]
		copy(kernel.runQueue, kernel.runQueue[1:])
		kernel.runQueue = kernel.runQueue[:len(kernel.runQueue)-1]
		kernel.queued[pid] = false

		match kernel.liveProcess(pid) {
		case option.None:
			continue
		case option.Some(current):
			match current.status {
			case Runnable:
			case _:
				continue
			}
			context := &Context{kernel: kernel, process: current}
			step := current.behavior(context)
			reductions++
			match current.status {
			case Exited:
				continue
			case _:
			}
			match step {
			case Yield:
				kernel.enqueueRunnable(pid)
			case Wait:
				current.status = Waiting()
			case Stop(reason):
				kernel.terminate(current, reason)
			}
		}
	}
	return kernel.report(reductions)
}

func (kernel *Kernel) ProcessInfo(pid term.PID) option.Option[ProcessInfo] {
	current, present := kernel.processes[pid]
	match option.Of(current, present) {
	case option.None:
		return option.None[ProcessInfo]
	case option.Some(found):
		links := make([]term.PID, 0, len(found.links))
		for linked := range found.links {
			links = append(links, linked)
		}
		sort.Slice(links, func(left, right int) bool {
			return links[left].Less(links[right])
		})
		var exitReason option.Option[term.Term] = option.None[term.Term]
		match found.exitReason {
		case option.Some(reason):
			exitReason = option.Some[term.Term](reason.Clone())
		case option.None:
		}
		return option.Some[ProcessInfo](ProcessInfo{
			PID: found.pid, Status: found.status, TrapExit: found.trapExit,
			MailboxLength: found.mailbox.Len(), Links: links, ExitReason: exitReason,
		})
	}
}

func (kernel *Kernel) liveProcess(pid term.PID) option.Option[*process] {
	current, present := kernel.processes[pid]
	if !present {
		return option.None[*process]
	}
	match current.status {
	case Exited:
		return option.None[*process]
	case _:
		return option.Some[*process](current)
	}
}

func (kernel *Kernel) enqueueRunnable(pid term.PID) {
	match kernel.liveProcess(pid) {
	case option.None:
	case option.Some(current):
		if kernel.queued[pid] {
			return
		}
		current.status = Runnable()
		kernel.runQueue = append(kernel.runQueue, pid)
		kernel.queued[pid] = true
	}
}

func (kernel *Kernel) enqueueSignal(to term.PID, signal Signal) Delivery {
	match kernel.liveProcess(to) {
	case option.None:
		return NoProcess()
	case option.Some(current):
		key := route{from: signalFrom(signal), to: to}
		kernel.sequences[key]++
		current.mailbox.Push(withSequence(signal, kernel.sequences[key]))
		match current.status {
		case Waiting:
			kernel.enqueueRunnable(to)
		case _:
		}
		return Delivered()
	}
}

func (kernel *Kernel) newReference() term.Reference {
	kernel.nextReference++
	return term.Reference{
		Node: kernel.config.Node, Creation: kernel.config.Creation,
		Words: [5]uint32{kernel.nextReference}, Length: 1,
	}
}

func (kernel *Kernel) terminate(current *process, reason term.Term) {
	match current.status {
	case Exited:
		return
	case _:
	}
	current.status = Exited()
	current.exitReason = option.Some[term.Term](reason.Clone())

	links := make([]term.PID, 0, len(current.links))
	for linked := range current.links {
		links = append(links, linked)
	}
	sort.Slice(links, func(left, right int) bool {
		return links[left].Less(links[right])
	})
	current.links = make(map[term.PID]struct{})
	for _, linkedPID := range links {
		match kernel.liveProcess(linkedPID) {
		case option.None:
		case option.Some(linked):
			delete(linked.links, current.pid)
			if linked.trapExit {
				kernel.enqueueSignal(linkedPID, ExitSignal(
					current.pid, 0, reason.Clone(), current.pid,
				))
				continue
			}
			if !isNormal(reason) {
				kernel.terminate(linked, reason)
			}
		}
	}

	references := make([]term.Reference, 0, len(current.monitoredBy))
	for reference := range current.monitoredBy {
		references = append(references, reference)
	}
	sort.Slice(references, func(left, right int) bool {
		return references[left].Less(references[right])
	})
	for _, reference := range references {
		watcher := current.monitoredBy[reference]
		match kernel.liveProcess(watcher) {
		case option.None:
		case option.Some(watcherProcess):
			delete(watcherProcess.monitoring, reference)
			kernel.enqueueSignal(watcher, DownSignal(
				current.pid, 0, reason.Clone(), reference, current.pid,
			))
		}
	}
	current.monitoredBy = make(map[term.Reference]term.PID)

	outgoing := make([]term.Reference, 0, len(current.monitoring))
	for reference := range current.monitoring {
		outgoing = append(outgoing, reference)
	}
	sort.Slice(outgoing, func(left, right int) bool {
		return outgoing[left].Less(outgoing[right])
	})
	for _, reference := range outgoing {
		target := current.monitoring[reference]
		match kernel.liveProcess(target) {
		case option.Some(targetProcess):
			delete(targetProcess.monitoredBy, reference)
		case option.None:
		}
	}
	current.monitoring = make(map[term.Reference]term.PID)
}

func (kernel *Kernel) report(reductions int) RunReport {
	report := RunReport{Reductions: reductions}
	for _, current := range kernel.processes {
		match current.status {
		case Runnable:
			report.Runnable++
		case Waiting:
			report.Waiting++
		case Exited:
			report.Exited++
		}
	}
	return report
}

func isNormal(reason term.Term) bool {
	match reason {
	case term.AtomTerm(name):
		return name == "normal"
	case _:
		return false
	}
}

type MessageEnvelope struct {
	Message term.Term
	From    term.PID
}

type Context struct {
	kernel  *Kernel
	process *process
}

func (context *Context) Self() term.PID {
	return context.process.pid
}

func (context *Context) Send(to term.PID, message term.Term) Delivery {
	return context.kernel.Send(context.process.pid, to, message)
}

func (context *Context) Receive(
	accept func(Signal) bool,
) option.Option[Signal] {
	return context.process.mailbox.Receive(accept)
}

func (context *Context) ReceiveMessage(
	accept func(term.Term) bool,
) option.Option[MessageEnvelope] {
	received := context.process.mailbox.Receive(func(signal Signal) bool {
		return acceptsMessage(signal, accept)
	})
	match received {
	case option.None:
		return option.None[MessageEnvelope]
	case option.Some(signal):
		match signal {
		case UserSignal(from, _, message):
			return option.Some[MessageEnvelope](MessageEnvelope{Message: message, From: from})
		case _:
			return option.None[MessageEnvelope]
		}
	}
}

func acceptsMessage(signal Signal, accept func(term.Term) bool) bool {
	match signal {
	case UserSignal(_, _, message):
		return accept == nil || accept(message)
	case _:
		return false
	}
}

func (context *Context) Spawn(
	behavior Behavior,
	policy SpawnPolicy,
) result.Result[term.PID, Failure] {
	return context.kernel.Spawn(behavior, policy)
}

func (context *Context) Link(
	other term.PID,
) result.Result[KernelMutation, Failure] {
	return context.kernel.Link(context.process.pid, other)
}

func (context *Context) Monitor(
	other term.PID,
) result.Result[term.Reference, Failure] {
	return context.kernel.Monitor(context.process.pid, other)
}

func (context *Context) Demonitor(
	reference term.Reference,
	flush bool,
) MonitorRemoval {
	return context.kernel.Demonitor(context.process.pid, reference, flush)
}

func (context *Context) SetTrapExit(enabled bool) KernelMutation {
	context.process.trapExit = enabled
	return KernelMutated()
}

// Terminate is the capability held by a running behavior. Supervisor APIs
// expose it through Context rather than through global process state.
func (context *Context) Terminate(other term.PID, reason term.Term) Delivery {
	return context.kernel.Exit(other, reason)
}
