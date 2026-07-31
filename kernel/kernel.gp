package kernel

import (
	"fmt"
	"sort"

	"goforge.dev/goplus/std/memory"
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

type ContextSpawnOutcome enum {
	ContextSpawned(PID term.PID)
	ContextSpawnRejected(Detail string)
}

type ContextMonitorOutcome enum {
	ContextMonitored(Reference term.Reference)
	ContextMonitorRejected(Detail string)
}

type ContextSpawnResult struct { PID term.PID; Detail string; Accepted bool }
type ContextMonitorResult struct { Reference term.Reference; Detail string; Accepted bool }

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
	Aliases       []term.Reference
	ExitReason    option.Option[term.Term]
	RegisteredName option.Option[string]
	GroupLeader   term.PID
	PendingRemoteUnlinks []RemoteUnlink
}

type Failure enum {
	NilBehavior()
	MissingProcess(Role string, PID term.PID)
	InvalidLink(Detail string)
	InvalidTimer(Detail string)
	InvalidMonitor(Detail string)
	InvalidRegistration(Detail string)
	InvalidGroupLeader(Detail string)
}

func (failure Failure) Error() string {
	match failure {
	case NilBehavior:
		return "gotp/kernel: behavior is nil"
	case MissingProcess(role, pid):
		return fmt.Sprintf("gotp/kernel: %s process %v does not exist", role, pid)
	case InvalidLink(detail):
		return "gotp/kernel: invalid link: " + detail
	case InvalidTimer(detail):
		return "gotp/kernel: invalid timer: " + detail
	case InvalidMonitor(detail):
		return "gotp/kernel: invalid monitor: " + detail
	case InvalidRegistration(detail):
		return "gotp/kernel: invalid registration: " + detail
	case InvalidGroupLeader(detail):
		return "gotp/kernel: invalid group leader: " + detail
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

type AliasRemoval enum {
	AliasRemoved()
	AliasAbsent()
}

type RemoteSignal enum {
	RemoteExitSignal(From term.PID, To term.PID, Reason term.Term)
	RemoteDownSignal(Source term.PID, To term.PID, Reference term.Reference, Reason term.Term)
	RemoteDownNamedSignal(Source string, To term.PID, Reference term.Reference, Reason term.Term)
}

type RemoteUnlink struct {
	ID     uint64
	Local  term.PID
	Remote term.PID
}

type RemoteUnlinkAcknowledgement enum {
	RemoteUnlinkMatched()
	RemoteUnlinkIgnored()
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
	aliases     map[term.Reference]struct{}
	exitReason  option.Option[term.Term]
	registeredName option.Option[string]
	groupLeader term.PID
	monitorNames map[term.Reference]string
	remoteUnlinks map[term.PID]uint64
	dictionary []dictionaryEntry
}

type dictionaryEntry struct { key term.Term; value term.Term }

type Kernel struct {
	config        KernelConfig
	nextPID       uint64
	nextReference uint32
	processes     map[term.PID]*process
	runQueue      memory.Buffer[term.PID]
	queued        map[term.PID]bool
	sequences     map[route]uint64
	aliases       map[term.Reference]term.PID
	wakeups       *wakeQueue
	tracer        *Tracer
	remoteSignals memory.Buffer[RemoteSignal]
	names         map[string]term.PID
	nextUnlinkID  uint64
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
		aliases:   make(map[term.Reference]term.PID),
		wakeups: newWakeQueue(),
		names: make(map[string]term.PID),
		runQueue: memory.NewBuffer[term.PID](64),
		remoteSignals: memory.NewBuffer[RemoteSignal](16),
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
		aliases: make(map[term.Reference]struct{}),
		exitReason: option.None[term.Term],
		registeredName: option.None[string],
		groupLeader: pid,
		monitorNames: make(map[term.Reference]string),
		remoteUnlinks: make(map[term.PID]uint64),
	}
	kernel.processes[pid] = current
	kernel.enqueueRunnable(pid)
	kernel.trace(ProcessSpawned(pid))
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

// assayxport:unit gotp.kernel.registered-processes
func (kernel *Kernel) Register(name string, pid term.PID) result.Result[KernelMutation, Failure] {
	if name == "" {
		return result.Err[KernelMutation, Failure](InvalidRegistration("name is empty"))
	}
	match term.Atom(name) {
	case result.Err(cause): return result.Err[KernelMutation, Failure](InvalidRegistration(cause.Error()))
	case result.Ok(_):
	}
	if _, duplicate := kernel.names[name]; duplicate {
		return result.Err[KernelMutation, Failure](InvalidRegistration("name is already registered"))
	}
	match kernel.liveProcess(pid) {
	case option.None: return result.Err[KernelMutation, Failure](MissingProcess("registration", pid))
	case option.Some(current):
		match current.registeredName {
		case option.Some(_): return result.Err[KernelMutation, Failure](InvalidRegistration("process already has a name"))
		case option.None:
		}
		kernel.names[name] = pid
		current.registeredName = option.Some[string](name)
		return result.Ok[KernelMutation, Failure](KernelMutated())
	}
}

func (kernel *Kernel) Unregister(name string) result.Result[KernelMutation, Failure] {
	pid, present := kernel.names[name]
	if !present {
		return result.Err[KernelMutation, Failure](InvalidRegistration("name is not registered"))
	}
	delete(kernel.names, name)
	match kernel.liveProcess(pid) {
	case option.None:
	case option.Some(current): current.registeredName = option.None[string]
	}
	return result.Ok[KernelMutation, Failure](KernelMutated())
}

func (kernel *Kernel) Whereis(name string) option.Option[term.PID] {
	pid, present := kernel.names[name]
	if !present { return option.None[term.PID] }
	match kernel.liveProcess(pid) {
	case option.None:
		delete(kernel.names, name)
		return option.None[term.PID]
	case option.Some(_): return option.Some[term.PID](pid)
	}
}

func (kernel *Kernel) SendRegistered(from term.PID, name string, message term.Term) Delivery {
	match kernel.Whereis(name) {
	case option.None: return NoProcess()
	case option.Some(to): return kernel.Send(from, to, message)
	}
}

func (kernel *Kernel) SetGroupLeader(
	leader term.PID,
	member term.PID,
) result.Result[KernelMutation, Failure] {
	if !leader.Valid() {
		return result.Err[KernelMutation, Failure](InvalidGroupLeader("leader pid is invalid"))
	}
	if leader.Node == kernel.config.Node {
		match kernel.liveProcess(leader) {
		case option.None: return result.Err[KernelMutation, Failure](MissingProcess("group leader", leader))
		case option.Some(_):
		}
	}
	match kernel.liveProcess(member) {
	case option.None: return result.Err[KernelMutation, Failure](MissingProcess("group member", member))
	case option.Some(current):
		current.groupLeader = leader
		return result.Ok[KernelMutation, Failure](KernelMutated())
	}
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
			kernel.trace(ProcessesLinked(left, right))
			return result.Ok[KernelMutation, Failure](KernelMutated())
		}
	}
}

// assayxport:unit gotp.kernel.remote-process-signals
func (kernel *Kernel) LinkRemote(
	remote term.PID,
	local term.PID,
) result.Result[KernelMutation, Failure] {
	if !remote.Valid() || !local.Valid() {
		return result.Err[KernelMutation, Failure](InvalidLink("remote or local pid is invalid"))
	}
	match kernel.liveProcess(local) {
	case option.None:
		return result.Err[KernelMutation, Failure](MissingProcess("local link", local))
	case option.Some(current):
		if _, outstanding := current.remoteUnlinks[remote]; outstanding {
			return result.Ok[KernelMutation, Failure](KernelMutated())
		}
		current.links[remote] = struct{}{}
		kernel.trace(ProcessesLinked(remote, local))
		return result.Ok[KernelMutation, Failure](KernelMutated())
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

func (kernel *Kernel) UnlinkRemote(remote term.PID, local term.PID) KernelMutation {
	match kernel.liveProcess(local) {
	case option.Some(current): delete(current.links, remote)
	case option.None:
	}
	return KernelMutated()
}

// assayxport:unit gotp.kernel.remote-unlink-protocol
func (kernel *Kernel) BeginRemoteUnlink(
	local term.PID,
	remote term.PID,
) result.Result[RemoteUnlink, Failure] {
	match kernel.liveProcess(local) {
	case option.None:
		return result.Err[RemoteUnlink, Failure](MissingProcess("local unlink", local))
	case option.Some(current):
		if identifier, outstanding := current.remoteUnlinks[remote]; outstanding {
			return result.Ok[RemoteUnlink, Failure](RemoteUnlink{
				ID: identifier, Local: local, Remote: remote,
			})
		}
		if _, active := current.links[remote]; !active {
			return result.Err[RemoteUnlink, Failure](InvalidLink("remote link is not active"))
		}
		delete(current.links, remote)
		kernel.nextUnlinkID++
		if kernel.nextUnlinkID == 0 { kernel.nextUnlinkID++ }
		current.remoteUnlinks[remote] = kernel.nextUnlinkID
		return result.Ok[RemoteUnlink, Failure](RemoteUnlink{
			ID: kernel.nextUnlinkID, Local: local, Remote: remote,
		})
	}
}

func (kernel *Kernel) AcknowledgeRemoteUnlink(
	local term.PID,
	remote term.PID,
	identifier uint64,
) RemoteUnlinkAcknowledgement {
	match kernel.liveProcess(local) {
	case option.None: return RemoteUnlinkIgnored()
	case option.Some(current):
		outstanding, present := current.remoteUnlinks[remote]
		if present && outstanding == identifier {
			delete(current.remoteUnlinks, remote)
			return RemoteUnlinkMatched()
		}
		return RemoteUnlinkIgnored()
	}
}

func (kernel *Kernel) Monitor(
	watcher term.PID,
	target term.PID,
) result.Result[term.Reference, Failure] {
	reference := kernel.newReference()
	match kernel.MonitorReference(watcher, target, reference) {
	case result.Err(failure): return result.Err[term.Reference, Failure](failure)
	case result.Ok(_): return result.Ok[term.Reference, Failure](reference)
	}
}

func (kernel *Kernel) MonitorAlias(
	watcher term.PID,
	target term.PID,
) result.Result[term.Reference, Failure] {
	reference := kernel.newReference()
	match kernel.MonitorReference(watcher, target, reference) {
	case result.Err(failure): return result.Err[term.Reference, Failure](failure)
	case result.Ok(_):
		match kernel.liveProcess(watcher) {
		case option.None: return result.Err[term.Reference, Failure](MissingProcess("alias owner", watcher))
		case option.Some(current):
			current.aliases[reference] = struct{}{}
			kernel.aliases[reference] = watcher
			return result.Ok[term.Reference, Failure](reference)
		}
	}
}

// assayxport:unit gotp.kernel.remote-monitor-signals
func (kernel *Kernel) MonitorReference(
	watcher term.PID,
	target term.PID,
	reference term.Reference,
) result.Result[KernelMutation, Failure] {
	if !reference.Valid() {
		return result.Err[KernelMutation, Failure](InvalidMonitor("reference is invalid"))
	}
	match kernel.liveProcess(watcher) {
	case option.None:
		return result.Err[KernelMutation, Failure](MissingProcess("watcher", watcher))
	case option.Some(watcherProcess):
		if _, duplicate := watcherProcess.monitoring[reference]; duplicate {
			return result.Err[KernelMutation, Failure](InvalidMonitor("reference is already active"))
		}
		match kernel.liveProcess(target) {
		case option.None:
			kernel.enqueueSignal(watcher, DownSignal(
				target, 0, term.MustAtom("noproc"), reference, target,
			))
		case option.Some(targetProcess):
			watcherProcess.monitoring[reference] = target
			targetProcess.monitoredBy[reference] = watcher
		}
		kernel.trace(ProcessMonitored(watcher, target, reference))
		return result.Ok[KernelMutation, Failure](KernelMutated())
	}
}

func (kernel *Kernel) MonitorRemote(
	watcher term.PID,
	target term.PID,
	reference term.Reference,
) result.Result[KernelMutation, Failure] {
	if !watcher.Valid() || !reference.Valid() {
		return result.Err[KernelMutation, Failure](InvalidMonitor("remote watcher or reference is invalid"))
	}
	match kernel.liveProcess(target) {
	case option.None:
		kernel.remoteSignals.Append(RemoteDownSignal(
			target, watcher, reference, term.MustAtom("noproc"),
		))
		return result.Ok[KernelMutation, Failure](KernelMutated())
	case option.Some(current):
		if prior, duplicate := current.monitoredBy[reference]; duplicate && prior != watcher {
			return result.Err[KernelMutation, Failure](InvalidMonitor("reference belongs to another watcher"))
		}
		current.monitoredBy[reference] = watcher
		kernel.trace(ProcessMonitored(watcher, target, reference))
		return result.Ok[KernelMutation, Failure](KernelMutated())
	}
}

func (kernel *Kernel) MonitorRemoteName(
	watcher term.PID,
	name string,
	reference term.Reference,
) result.Result[KernelMutation, Failure] {
	if !watcher.Valid() || !reference.Valid() {
		return result.Err[KernelMutation, Failure](InvalidMonitor("remote watcher or reference is invalid"))
	}
	match kernel.Whereis(name) {
	case option.None:
		kernel.remoteSignals.Append(RemoteDownNamedSignal(
			name, watcher, reference, term.MustAtom("noproc"),
		))
		return result.Ok[KernelMutation, Failure](KernelMutated())
	case option.Some(target):
		match kernel.liveProcess(target) {
		case option.None: return result.Err[KernelMutation, Failure](MissingProcess("named monitor", target))
		case option.Some(current):
			if prior, duplicate := current.monitoredBy[reference]; duplicate && prior != watcher {
				return result.Err[KernelMutation, Failure](InvalidMonitor("reference belongs to another watcher"))
			}
			current.monitoredBy[reference] = watcher
			current.monitorNames[reference] = name
			kernel.trace(ProcessMonitored(watcher, target, reference))
			return result.Ok[KernelMutation, Failure](KernelMutated())
		}
	}
}

func (kernel *Kernel) DemonitorRemote(
	watcher term.PID,
	target term.PID,
	reference term.Reference,
) MonitorRemoval {
	match kernel.liveProcess(target) {
	case option.None: return MonitorAbsent()
	case option.Some(current):
		prior, present := current.monitoredBy[reference]
		if present && prior == watcher {
			delete(current.monitoredBy, reference)
			return MonitorRemoved()
		}
		return MonitorAbsent()
	}
}

func (kernel *Kernel) DemonitorRemoteName(
	watcher term.PID,
	name string,
	reference term.Reference,
) MonitorRemoval {
	for _, current := range kernel.processes {
		match current.status { case Exited: continue; case _: }
		prior, present := current.monitoredBy[reference]
		registered, named := current.monitorNames[reference]
		if present && named && prior == watcher && registered == name {
			delete(current.monitoredBy, reference)
			delete(current.monitorNames, reference)
			return MonitorRemoved()
		}
	}
	return MonitorAbsent()
}

func (kernel *Kernel) DrainRemoteSignals() []RemoteSignal {
	drained := make([]RemoteSignal, kernel.remoteSignals.Len())
	for index := 0; index < kernel.remoteSignals.Len(); index++ { var signal RemoteSignal; match kernel.remoteSignals.At(index) { case option.None: continue; case option.Some(found): signal = found }
		match signal {
		case RemoteExitSignal(from, to, reason):
			drained[index] = RemoteExitSignal(from, to, reason.Clone())
		case RemoteDownSignal(source, to, reference, reason):
			drained[index] = RemoteDownSignal(source, to, reference, reason.Clone())
		case RemoteDownNamedSignal(source, to, reference, reason):
			drained[index] = RemoteDownNamedSignal(source, to, reference, reason.Clone())
		}
	}
	kernel.remoteSignals.Reset()
	return drained
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
			if _, aliased := watcherProcess.aliases[reference]; aliased {
				delete(watcherProcess.aliases, reference)
				delete(kernel.aliases, reference)
			}
			match kernel.liveProcess(target) {
			case option.Some(targetProcess):
				delete(targetProcess.monitoredBy, reference)
				delete(targetProcess.monitorNames, reference)
			case option.None:
			}
		}
		if flush {
			watcherProcess.mailbox.Remove(func(signal Signal) bool {
				match signal {
				case DownSignal(_, _, _, found, _):
					return found == reference
				case DownNamedSignal(_, _, _, found, _):
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

// assayxport:unit gotp.kernel.process-aliases
func (kernel *Kernel) Alias(owner term.PID) result.Result[term.Reference, Failure] {
	match kernel.liveProcess(owner) {
	case option.None:
		return result.Err[term.Reference, Failure](MissingProcess("alias owner", owner))
	case option.Some(current):
		reference := kernel.newReference()
		current.aliases[reference] = struct{}{}
		kernel.aliases[reference] = owner
		return result.Ok[term.Reference, Failure](reference)
	}
}

func (kernel *Kernel) Unalias(owner term.PID, reference term.Reference) AliasRemoval {
	match kernel.liveProcess(owner) {
	case option.None:
		return AliasAbsent()
	case option.Some(current):
		_, owned := current.aliases[reference]
		if !owned {
			return AliasAbsent()
		}
		delete(current.aliases, reference)
		delete(kernel.aliases, reference)
		return AliasRemoved()
	}
}

func (kernel *Kernel) SendAlias(
	from term.PID,
	reference term.Reference,
	message term.Term,
) Delivery {
	owner, present := kernel.aliases[reference]
	match option.Of(owner, present) {
	case option.None:
		return NoProcess()
	case option.Some(target):
		return kernel.enqueueSignal(target, UserSignal(from, 0, message.Clone()))
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

// assayxport:unit gotp.kernel.process-signals
func (kernel *Kernel) SendExit(
	from term.PID,
	to term.PID,
	reason term.Term,
) Delivery {
	match kernel.liveProcess(to) {
	case option.None:
		return NoProcess()
	case option.Some(target):
		if isAtom(reason, "kill") {
			kernel.terminate(target, term.MustAtom("killed"))
			return Delivered()
		}
		if target.trapExit {
			return kernel.enqueueSignal(to, ExitSignal(from, 0, reason.Clone(), to))
		}
		if isAtom(reason, "normal") && from != to {
			return Delivered()
		}
		kernel.terminate(target, reason)
		return Delivered()
	}
}

func (kernel *Kernel) SendDown(
	source term.PID,
	to term.PID,
	reference term.Reference,
	reason term.Term,
) Delivery {
	return kernel.enqueueSignal(to, DownSignal(
		source, 0, reason.Clone(), reference, source,
	))
}

func (kernel *Kernel) SendDownNamed(
	name string,
	to term.PID,
	reference term.Reference,
	reason term.Term,
) Delivery {
	return kernel.enqueueSignal(to, DownNamedSignal(
		term.PID{}, 0, reason.Clone(), reference, name,
	))
}

func (kernel *Kernel) Run(maxReductions int) RunReport {
	if maxReductions <= 0 {
		maxReductions = 1_000_000
	}
	kernel.drainWakeups()
	reductions := 0
	for kernel.runQueue.Len() > 0 && reductions < maxReductions {
		var pid term.PID; match kernel.runQueue.Remove(0) { case option.None: continue; case option.Some(found): pid = found }
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
			kernel.trace(ProcessScheduled(pid))
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
		aliases := make([]term.Reference, 0, len(found.aliases))
		for reference := range found.aliases {
			aliases = append(aliases, reference)
		}
		sort.Slice(aliases, func(left, right int) bool {
			return aliases[left].Less(aliases[right])
		})
		var exitReason option.Option[term.Term] = option.None[term.Term]
		match found.exitReason {
		case option.Some(reason):
			exitReason = option.Some[term.Term](reason.Clone())
		case option.None:
		}
		pending := make([]RemoteUnlink, 0, len(found.remoteUnlinks))
		for remote, identifier := range found.remoteUnlinks {
			pending = append(pending, RemoteUnlink{ID: identifier, Local: found.pid, Remote: remote})
		}
		sort.Slice(pending, func(left, right int) bool {
			return pending[left].Remote.Less(pending[right].Remote)
		})
		return option.Some[ProcessInfo](ProcessInfo{
			PID: found.pid, Status: found.status, TrapExit: found.trapExit,
			MailboxLength: found.mailbox.Len(), Links: links, Aliases: aliases,
			ExitReason: exitReason,
			RegisteredName: found.registeredName,
			GroupLeader: found.groupLeader,
			PendingRemoteUnlinks: pending,
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
		kernel.runQueue.Append(pid)
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
		queuedSignal := withSequence(signal, kernel.sequences[key])
		current.mailbox.Push(queuedSignal)
		kernel.traceSignal(to, queuedSignal)
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
	kernel.trace(ProcessExited(current.pid, reason))
	match current.registeredName {
	case option.Some(name): delete(kernel.names, name)
	case option.None:
	}
	current.registeredName = option.None[string]

	links := make([]term.PID, 0, len(current.links))
	for linked := range current.links {
		links = append(links, linked)
	}
	sort.Slice(links, func(left, right int) bool {
		return links[left].Less(links[right])
	})
	current.links = make(map[term.PID]struct{})
	current.remoteUnlinks = make(map[term.PID]uint64)
	for _, linkedPID := range links {
		match kernel.liveProcess(linkedPID) {
		case option.None:
			if linkedPID.Node != kernel.config.Node {
				kernel.remoteSignals.Append(RemoteExitSignal(
					current.pid, linkedPID, reason.Clone(),
				))
			}
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
			if watcher.Node != kernel.config.Node {
				name, named := current.monitorNames[reference]
				if named {
					kernel.remoteSignals.Append(RemoteDownNamedSignal(
						name, watcher, reference, reason.Clone(),
					))
				} else {
					kernel.remoteSignals.Append(RemoteDownSignal(
						current.pid, watcher, reference, reason.Clone(),
					))
				}
			}
		case option.Some(watcherProcess):
			delete(watcherProcess.monitoring, reference)
			name, named := current.monitorNames[reference]
			if named {
				kernel.enqueueSignal(watcher, DownNamedSignal(
					current.pid, 0, reason.Clone(), reference, name,
				))
			} else {
				kernel.enqueueSignal(watcher, DownSignal(
					current.pid, 0, reason.Clone(), reference, current.pid,
				))
			}
		}
	}
	current.monitoredBy = make(map[term.Reference]term.PID)
	current.monitorNames = make(map[term.Reference]string)

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
	for reference := range current.aliases {
		delete(kernel.aliases, reference)
	}
	current.aliases = make(map[term.Reference]struct{})
	current.mailbox.Release()
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
	return isAtom(reason, "normal")
}

func isAtom(value term.Term, expected string) bool {
	match term.AtomName(value) {
	case option.Some(name):
		return name == expected
	case option.None:
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

func (context *Context) NodeID() uint32 { return context.kernel.config.Node }
func (context *Context) NodeName() string { return "nonode@nohost" }

func (context *Context) Send(to term.PID, message term.Term) Delivery {
	return context.kernel.Send(context.process.pid, to, message)
}

func (context *Context) SendRegistered(name string, message term.Term) Delivery {
	return context.kernel.SendRegistered(context.process.pid, name, message)
}

func (context *Context) Register(name string, pid term.PID) result.Result[KernelMutation, Failure] {
	return context.kernel.Register(name, pid)
}

func (context *Context) Unregister(name string) result.Result[KernelMutation, Failure] {
	return context.kernel.Unregister(name)
}

func (context *Context) Whereis(name string) option.Option[term.PID] {
	return context.kernel.Whereis(name)
}

func (context *Context) ProcessInfo(pid term.PID, item string) option.Option[term.Term] {
	current, present := context.kernel.processes[pid]
	if !present { return option.None[term.Term]() }
	match current.status { case Exited: return option.None[term.Term](); case _: }
	switch item {
	case "registered_name":
		match current.registeredName { case option.None: return option.Some[term.Term](term.Tuple(term.MustAtom("registered_name"), term.List())); case option.Some(name): return option.Some[term.Term](term.Tuple(term.MustAtom("registered_name"), term.MustAtom(name))) }
	case "trap_exit":
		value := "false"; if current.trapExit { value = "true" }
		return option.Some[term.Term](term.Tuple(term.MustAtom("trap_exit"), term.MustAtom(value)))
	case "links":
		links := make([]term.Term, 0, len(current.links)); for linked := range current.links { links = append(links, term.PIDValue(linked)) }
		return option.Some[term.Term](term.Tuple(term.MustAtom("links"), term.List(links...)))
	case "dictionary":
		values := make([]term.Term, 0, len(current.dictionary)); for _, entry := range current.dictionary { values = append(values, term.Tuple(term.Clone(entry.key), term.Clone(entry.value))) }
		return option.Some[term.Term](term.Tuple(term.MustAtom("dictionary"), term.List(values...)))
	case "message_queue_len": return option.Some[term.Term](term.Tuple(term.MustAtom("message_queue_len"), term.Integer(int64(current.mailbox.Len()))))
	case "status": return option.Some[term.Term](term.Tuple(term.MustAtom("status"), term.MustAtom("waiting")))
	default: return option.Some[term.Term](term.Tuple(term.MustAtom(item), term.List()))
	}
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
		match signalMessage(signal) {
		case option.None:
			return false
		case option.Some(envelope):
			return accept == nil || accept(envelope.Message)
		}
	})
	match received {
	case option.None:
		return option.None[MessageEnvelope]
	case option.Some(signal):
		return signalMessage(signal)
	}
}

func signalMessage(signal Signal) option.Option[MessageEnvelope] {
	match signal {
	case UserSignal(_, _, message):
		return option.Some[MessageEnvelope](MessageEnvelope{Message: message, From: signalFrom(signal)})
	case ExitSignal(from, _, reason, _):
		return option.Some[MessageEnvelope](MessageEnvelope{
			Message: term.Tuple(term.MustAtom("EXIT"), term.PIDTerm(from), reason),
			From: from,
		})
	case DownSignal(from, _, reason, reference, target):
		return option.Some[MessageEnvelope](MessageEnvelope{
			Message: term.Tuple(
				term.MustAtom("DOWN"),
				term.ReferenceTerm(reference),
				term.MustAtom("process"),
				term.PIDTerm(target),
				reason,
			),
			From: from,
		})
	case DownNamedSignal(from, _, reason, reference, target):
		return option.Some[MessageEnvelope](MessageEnvelope{
			Message: term.Tuple(
				term.MustAtom("DOWN"),
				term.ReferenceTerm(reference),
				term.MustAtom("process"),
				term.MustAtom(target),
				reason,
			),
			From: from,
		})
	}
}

func (context *Context) Spawn(
	behavior Behavior,
	policy SpawnPolicy,
) result.Result[term.PID, Failure] {
	return context.kernel.Spawn(behavior, policy)
}

func (context *Context) SpawnOutcome(behavior Behavior, policy SpawnPolicy) ContextSpawnOutcome {
	match context.Spawn(behavior, policy) { case result.Err(failure): return ContextSpawnRejected(failure.Error()); case result.Ok(pid): return ContextSpawned(pid) }
}

func (context *Context) SpawnResult(behavior Behavior, policy SpawnPolicy) ContextSpawnResult {
	match context.Spawn(behavior, policy) { case result.Err(failure): return ContextSpawnResult{Detail: failure.Error()}; case result.Ok(pid): return ContextSpawnResult{PID: pid, Accepted: true} }
}

func (context *Context) Link(
	other term.PID,
) result.Result[KernelMutation, Failure] {
	return context.kernel.Link(context.process.pid, other)
}

func (context *Context) Unlink(other term.PID) KernelMutation {
	return context.kernel.Unlink(context.process.pid, other)
}

func (context *Context) DictionaryGet(key term.Term) option.Option[term.Term] {
	for _, entry := range context.process.dictionary { if entry.key.Equal(key) { return option.Some(term.Clone(entry.value)) } }
	return option.None[term.Term]()
}

func (context *Context) DictionaryPut(key term.Term, value term.Term) option.Option[term.Term] {
	for index := range context.process.dictionary {
		if context.process.dictionary[index].key.Equal(key) {
			prior := term.Clone(context.process.dictionary[index].value)
			context.process.dictionary[index].value = term.Clone(value)
			return option.Some(prior)
		}
	}
	context.process.dictionary = append(context.process.dictionary, dictionaryEntry{key: term.Clone(key), value: term.Clone(value)})
	return option.None[term.Term]()
}

func (context *Context) DictionaryErase(key term.Term) option.Option[term.Term] {
	for index := range context.process.dictionary {
		if context.process.dictionary[index].key.Equal(key) {
			prior := term.Clone(context.process.dictionary[index].value)
			context.process.dictionary = append(context.process.dictionary[:index], context.process.dictionary[index+1:]...)
			return option.Some(prior)
		}
	}
	return option.None[term.Term]()
}

func (context *Context) Monitor(
	other term.PID,
) result.Result[term.Reference, Failure] {
	return context.kernel.Monitor(context.process.pid, other)
}

func (context *Context) MonitorOutcome(other term.PID) ContextMonitorOutcome {
	match context.Monitor(other) { case result.Err(failure): return ContextMonitorRejected(failure.Error()); case result.Ok(reference): return ContextMonitored(reference) }
}

func (context *Context) MonitorResult(other term.PID) ContextMonitorResult {
	match context.Monitor(other) { case result.Err(failure): return ContextMonitorResult{Detail: failure.Error()}; case result.Ok(reference): return ContextMonitorResult{Reference: reference, Accepted: true} }
}

func (context *Context) MonitorAliasResult(other term.PID) ContextMonitorResult {
	match context.kernel.MonitorAlias(context.process.pid, other) { case result.Err(failure): return ContextMonitorResult{Detail: failure.Error()}; case result.Ok(reference): return ContextMonitorResult{Reference: reference, Accepted: true} }
}

func (context *Context) Demonitor(
	reference term.Reference,
	flush bool,
) MonitorRemoval {
	return context.kernel.Demonitor(context.process.pid, reference, flush)
}

func (context *Context) Alias() result.Result[term.Reference, Failure] {
	return context.kernel.Alias(context.process.pid)
}

func (context *Context) MakeReference() term.Reference { return context.kernel.newReference() }

func (context *Context) Unalias(reference term.Reference) AliasRemoval {
	return context.kernel.Unalias(context.process.pid, reference)
}

func (context *Context) SendAlias(reference term.Reference, message term.Term) Delivery {
	return context.kernel.SendAlias(context.process.pid, reference, message)
}

func (context *Context) SetTrapExit(enabled bool) KernelMutation {
	context.process.trapExit = enabled
	return KernelMutated()
}

func (context *Context) Exit(other term.PID, reason term.Term) Delivery {
	return context.kernel.SendExit(context.process.pid, other, reason)
}

// Terminate is the capability held by a running behavior. Supervisor APIs
// expose it through Context rather than through global process state.
func (context *Context) Terminate(other term.PID, reason term.Term) Delivery {
	return context.kernel.Exit(other, reason)
}
