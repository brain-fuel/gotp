package erts

import (
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/distribution"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

func distributionWait(*kernel.Context) kernel.StepResult { return kernel.Wait() }

func distributionSpawn(t *testing.T, runtime *kernel.Kernel) term.PID {
	match runtime.Spawn(distributionWait, kernel.Unlinked(false)) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(pid): return pid
	}
	panic("unreachable")
}

func distributionControl(t *testing.T, code distribution.ControlCode, fields ...term.Term) distribution.Control {
	match distribution.NewControl(code, fields...) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(control): return control
	}
	panic("unreachable")
}

func dispatchSignal(
	t *testing.T,
	runtime *kernel.Kernel,
	control distribution.Control,
	payload option.Option[term.Term],
) DistributionDispatch {
	frame := distribution.TypedSignal(control, payload)
	match DispatchDistribution(runtime, frame) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(outcome): return outcome
	}
	panic("unreachable")
}

func distributionInfo(t *testing.T, runtime *kernel.Kernel, pid term.PID) kernel.ProcessInfo {
	match runtime.ProcessInfo(pid) {
	case option.None: t.Fatalf("process %v is absent", pid)
	case option.Some(info): return info
	}
	panic("unreachable")
}

// assayxport:unit gotp.erts.distribution-dispatch-laws
func TestDistributionDispatchMutatesSendLinkAndExitState(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{Node: 1, Creation: 1})
	from := term.PID{Node: 2, Number: 1, Creation: 1}
	to := distributionSpawn(t, runtime)
	link := distributionControl(t, distribution.LinkCode(), term.PIDValue(from), term.PIDValue(to))
	dispatchSignal(t, runtime, link, option.None[term.Term])
	if len(distributionInfo(t, runtime, to).Links) != 1 { t.Fatal("remote link was not installed") }
	send := distributionControl(t, distribution.SendSenderCode(), term.PIDValue(from), term.PIDValue(to))
	dispatchSignal(t, runtime, send, option.Some[term.Term](term.MustAtom("hello")))
	if distributionInfo(t, runtime, to).MailboxLength != 1 { t.Fatal("message was not delivered") }
	exit := distributionControl(t, distribution.PayloadExit2Code(), term.PIDValue(from), term.PIDValue(to))
	dispatchSignal(t, runtime, exit, option.Some[term.Term](term.MustAtom("shutdown")))
	match distributionInfo(t, runtime, to).Status {
	case kernel.Exited:
	case _: t.Fatal("exit signal did not terminate target")
	}
	signals := runtime.DrainRemoteSignals()
	if len(signals) != 1 { t.Fatalf("remote signals = %#v", signals) }
	match signals[0] {
	case kernel.RemoteExitSignal(source, target, reason):
		if source != to || target != from || !reason.Equal(term.MustAtom("shutdown")) {
			t.Fatalf("remote EXIT = %#v", signals[0])
		}
	case _: t.Fatalf("signal = %#v", signals[0])
	}
}

func TestDistributionDispatchInstallsProvidedMonitorReference(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{Node: 1, Creation: 1})
	watcher := term.PID{Node: 2, Number: 9, Creation: 1}
	target := distributionSpawn(t, runtime)
	reference := term.Reference{Node: 2, Creation: 9, Words: [5]uint32{77}, Length: 1}
	monitor := distributionControl(t, distribution.MonitorCode(),
		term.PIDValue(watcher), term.PIDValue(target), term.ReferenceValue(reference),
	)
	dispatchSignal(t, runtime, monitor, option.None[term.Term])
	runtime.Exit(target, term.MustAtom("gone"))
	signals := runtime.DrainRemoteSignals()
	if len(signals) != 1 {
		t.Fatal("provided monitor reference did not produce remote DOWN")
	}
	match signals[0] {
	case kernel.RemoteDownSignal(source, to, found, reason):
		if source != target || to != watcher || found != reference || !reason.Equal(term.MustAtom("gone")) {
			t.Fatalf("DOWN = %#v", signals[0])
		}
	case _: t.Fatalf("signal = %#v", signals[0])
	}
}

func TestDistributionDispatchDeliversRemoteDownAndAliasMessages(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{Node: 1, Creation: 1})
	from := term.PID{Node: 2, Number: 1, Creation: 1}
	to := distributionSpawn(t, runtime)
	reference := term.Reference{Node: 2, Creation: 1, Words: [5]uint32{8}, Length: 1}
	down := distributionControl(t, distribution.PayloadMonitorExitCode(),
		term.PIDValue(from), term.PIDValue(to), term.ReferenceValue(reference),
	)
	dispatchSignal(t, runtime, down, option.Some[term.Term](term.MustAtom("noproc")))
	if distributionInfo(t, runtime, to).MailboxLength != 1 { t.Fatal("DOWN was not delivered") }
	match runtime.Alias(to) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(alias):
		send := distributionControl(t, distribution.AliasSendCode(),
			term.PIDValue(from), term.ReferenceValue(alias),
		)
		dispatchSignal(t, runtime, send, option.Some[term.Term](term.MustAtom("alias")))
		if distributionInfo(t, runtime, to).MailboxLength != 2 { t.Fatal("alias message was not delivered") }
	}
}

func TestDistributionUnlinkReturnsReversedAcknowledgement(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{Node: 1, Creation: 1})
	from := term.PID{Node: 2, Number: 1, Creation: 1}
	to := distributionSpawn(t, runtime)
	match runtime.LinkRemote(from, to) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	unlink := distributionControl(t, distribution.UnlinkIDCode(),
		term.Integer(42), term.PIDValue(from), term.PIDValue(to),
	)
	match dispatchSignal(t, runtime, unlink, option.None[term.Term]) {
	case DistributionUnlinkAcknowledgement(identifier, ackFrom, ackTo):
		if !identifier.Equal(term.Integer(42)) || ackFrom != to || ackTo != from {
			t.Fatalf("ack = %#v, %v, %v", identifier, ackFrom, ackTo)
		}
	case _: t.Fatal("unlink did not return acknowledgement")
	}
	if len(distributionInfo(t, runtime, to).Links) != 0 { t.Fatal("link remained active") }
}

func TestDistributionDispatchSurfacesMissingAndDeferredOperations(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{Node: 1, Creation: 1})
	from := term.PID{Node: 2, Number: 1, Creation: 1}
	registeredTarget := distributionSpawn(t, runtime)
	match runtime.Register("server", registeredTarget) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	missing := term.PID{Node: 1, Number: 999, Creation: 1}
	send := distributionControl(t, distribution.SendSenderCode(), term.PIDValue(from), term.PIDValue(missing))
	match dispatchSignal(t, runtime, send, option.Some[term.Term](term.Integer(1))) {
	case DistributionDestinationMissing:
	case _: t.Fatal("missing destination was not surfaced")
	}
	registered := distributionControl(t, distribution.RegisteredSendCode(),
		term.PIDValue(from), term.List(), term.MustAtom("server"),
	)
	match dispatchSignal(t, runtime, registered, option.Some[term.Term](term.Integer(1))) {
	case DistributionApplied:
	case _: t.Fatal("registered send was not applied")
	}
	if distributionInfo(t, runtime, registeredTarget).MailboxLength != 1 { t.Fatal("registered message was not delivered") }
	traced := distributionControl(t, distribution.RegisteredSendTraceCode(),
		term.PIDValue(from), term.List(), term.MustAtom("server"), term.MustAtom("token"),
	)
	match dispatchSignal(t, runtime, traced, option.Some[term.Term](term.Integer(2))) {
	case DistributionDeferred(opcode): if opcode != 16 { t.Fatal("wrong deferred code") }
	case _: t.Fatal("seq-trace registered send was approximated")
	}
}

func TestDistributionNamesNamedMonitorsAndGroupLeaders(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{Node: 1, Creation: 1})
	remote := term.PID{Node: 2, Number: 10, Creation: 1}
	target := distributionSpawn(t, runtime)
	member := distributionSpawn(t, runtime)
	match runtime.Register("worker", target) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(_):
	}
	match runtime.Register("worker", member) {
	case result.Err(_):
	case result.Ok(_): t.Fatal("duplicate registered name was accepted")
	}
	reference := term.Reference{Node: 2, Creation: 1, Words: [5]uint32{91}, Length: 1}
	monitor := distributionControl(t, distribution.MonitorCode(),
		term.PIDValue(remote), term.MustAtom("worker"), term.ReferenceValue(reference),
	)
	dispatchSignal(t, runtime, monitor, option.None[term.Term])
	group := distributionControl(t, distribution.GroupLeaderCode(), term.PIDValue(remote), term.PIDValue(member))
	dispatchSignal(t, runtime, group, option.None[term.Term])
	if distributionInfo(t, runtime, member).GroupLeader != remote { t.Fatal("remote group leader was not installed") }
	runtime.Exit(target, term.MustAtom("finished"))
	signals := runtime.DrainRemoteSignals()
	if len(signals) != 1 { t.Fatalf("signals = %#v", signals) }
	match signals[0] {
	case kernel.RemoteDownNamedSignal(source, to, found, reason):
		if source != "worker" || to != remote || found != reference || !reason.Equal(term.MustAtom("finished")) {
			t.Fatalf("named DOWN = %#v", signals[0])
		}
	case _: t.Fatalf("signal = %#v", signals[0])
	}
	match runtime.Register("worker", member) {
	case result.Err(failure): t.Fatal("exit did not release name: " + failure.Error())
	case result.Ok(_):
	}
}

func TestMissingNamedMonitorReturnsImmediateNamedDown(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{Node: 1, Creation: 1})
	remote := term.PID{Node: 2, Number: 10, Creation: 1}
	reference := term.Reference{Node: 2, Creation: 1, Words: [5]uint32{92}, Length: 1}
	monitor := distributionControl(t, distribution.MonitorCode(),
		term.PIDValue(remote), term.MustAtom("absent"), term.ReferenceValue(reference),
	)
	dispatchSignal(t, runtime, monitor, option.None[term.Term])
	signals := runtime.DrainRemoteSignals()
	if len(signals) != 1 { t.Fatalf("signals = %#v", signals) }
	match signals[0] {
	case kernel.RemoteDownNamedSignal(source, to, found, reason):
		if source != "absent" || to != remote || found != reference || !reason.Equal(term.MustAtom("noproc")) {
			t.Fatalf("named DOWN = %#v", signals[0])
		}
	case _: t.Fatalf("signal = %#v", signals[0])
	}
}

func TestRemoteUnlinkAcknowledgementStateMachine(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{Node: 1, Creation: 1})
	local := distributionSpawn(t, runtime)
	remote := term.PID{Node: 2, Number: 44, Creation: 1}
	match runtime.LinkRemote(remote, local) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(_):
	}
	var unlink kernel.RemoteUnlink
	match runtime.BeginRemoteUnlink(local, remote) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(started): unlink = started
	}
	match runtime.BeginRemoteUnlink(local, remote) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(repeated):
		if repeated.ID != unlink.ID { t.Fatal("duplicate begin changed unlink id") }
	}
	link := distributionControl(t, distribution.LinkCode(), term.PIDValue(remote), term.PIDValue(local))
	dispatchSignal(t, runtime, link, option.None[term.Term])
	info := distributionInfo(t, runtime, local)
	if len(info.Links) != 0 || len(info.PendingRemoteUnlinks) != 1 {
		t.Fatalf("crossed LINK changed inactive state: %#v", info)
	}
	stale := distributionControl(t, distribution.UnlinkIDAckCode(),
		term.Integer(int64(unlink.ID+1)), term.PIDValue(remote), term.PIDValue(local),
	)
	dispatchSignal(t, runtime, stale, option.None[term.Term])
	if len(distributionInfo(t, runtime, local).PendingRemoteUnlinks) != 1 {
		t.Fatal("stale acknowledgement cleared outstanding unlink")
	}
	matching := distributionControl(t, distribution.UnlinkIDAckCode(),
		term.Integer(int64(unlink.ID)), term.PIDValue(remote), term.PIDValue(local),
	)
	dispatchSignal(t, runtime, matching, option.None[term.Term])
	if len(distributionInfo(t, runtime, local).PendingRemoteUnlinks) != 0 {
		t.Fatal("matching acknowledgement did not clear outstanding unlink")
	}
	dispatchSignal(t, runtime, matching, option.None[term.Term])
}

func TestCrossedRemoteUnlinkPreservesLocalOutstandingOperation(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{Node: 1, Creation: 1})
	local := distributionSpawn(t, runtime)
	remote := term.PID{Node: 2, Number: 45, Creation: 1}
	match runtime.LinkRemote(remote, local) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	match runtime.BeginRemoteUnlink(local, remote) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	incoming := distributionControl(t, distribution.UnlinkIDCode(),
		term.Integer(700), term.PIDValue(remote), term.PIDValue(local),
	)
	match dispatchSignal(t, runtime, incoming, option.None[term.Term]) {
	case DistributionUnlinkAcknowledgement(identifier, from, to):
		if !identifier.Equal(term.Integer(700)) || from != local || to != remote {
			t.Fatal("crossed unlink acknowledgement is incorrect")
		}
	case _: t.Fatal("crossed unlink did not produce acknowledgement")
	}
	if len(distributionInfo(t, runtime, local).PendingRemoteUnlinks) != 1 {
		t.Fatal("incoming unlink cleared local outstanding operation")
	}
}
