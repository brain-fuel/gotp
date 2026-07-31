package erts

import (
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/distribution"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

// assayxport:unit gotp.erts.distribution-outbound-laws
func TestLocalUnlinkAndIncomingAcknowledgementQueueAtRequiredPriorities(t *testing.T) {
	runtime := kernel.New(kernel.KernelConfig{Node: 1, Creation: 1})
	local := distributionSpawn(t, runtime)
	remote := term.PID{Node: 2, Number: 70, Creation: 1}
	match runtime.LinkRemote(remote, local) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(_): }
	queue := distribution.NewOutboundQueue()
	ordinary := distributionControl(t, distribution.LinkCode(), term.PIDValue(local), term.PIDValue(remote))
	match queue.Enqueue(distribution.OrdinaryOutput(), remote, ordinary, option.None[term.Term]) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(_):
	}
	match runtime.BeginRemoteUnlink(local, remote) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(unlink):
		match QueueRemoteUnlink(queue, unlink) {
		case result.Err(failure): t.Fatal(failure.Error())
		case result.Ok(_):
		}
	}
	incoming := distributionControl(t, distribution.UnlinkIDCode(),
		term.Integer(800), term.PIDValue(remote), term.PIDValue(local),
	)
	outcome := dispatchSignal(t, runtime, incoming, option.None[term.Term])
	match QueueDistributionReply(queue, outcome) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(_):
	}
	match queue.Next() {
	case option.None: t.Fatal("queue is empty")
	case option.Some(message):
		if message.Control.Number() != 36 { t.Fatal("acknowledgement did not receive priority") }
	}
	match queue.Next() {
	case option.None: t.Fatal("ordinary output is missing")
	case option.Some(message): if message.Control.Number() != 1 { t.Fatal("ordinary FIFO changed") }
	}
	match queue.Next() {
	case option.None: t.Fatal("local unlink output is missing")
	case option.Some(message): if message.Control.Number() != 35 { t.Fatal("local unlink was encoded incorrectly") }
	}
}
