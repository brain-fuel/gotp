package kernel

import (
	"goforge.dev/goplus/std/option"
	"goforge.dev/gotp/term"
)

type Signal enum {
	UserSignal(From term.PID, Sequence uint64, Message term.Term)
	ExitSignal(From term.PID, Sequence uint64, Reason term.Term, Target term.PID)
	DownSignal(From term.PID, Sequence uint64, Reason term.Term, Reference term.Reference, Target term.PID)
}

type MailboxMutation enum {
	SignalQueued()
}

type Mailbox struct {
	queue []Signal
}

func (mailbox *Mailbox) Push(signal Signal) MailboxMutation {
	mailbox.queue = append(mailbox.queue, signal)
	return SignalQueued()
}

func (mailbox *Mailbox) Receive(
	accept func(Signal) bool,
) option.Option[Signal] {
	for index, signal := range mailbox.queue {
		if accept != nil && !accept(signal) {
			continue
		}
		copy(mailbox.queue[index:], mailbox.queue[index+1:])
		mailbox.queue = mailbox.queue[:len(mailbox.queue)-1]
		return option.Some[Signal](signal)
	}
	return option.None[Signal]
}

func (mailbox *Mailbox) Remove(match func(Signal) bool) int {
	if match == nil {
		removed := len(mailbox.queue)
		mailbox.queue = mailbox.queue[:0]
		return removed
	}
	kept := mailbox.queue[:0]
	removed := 0
	for _, signal := range mailbox.queue {
		if match(signal) {
			removed++
			continue
		}
		kept = append(kept, signal)
	}
	mailbox.queue = kept
	return removed
}

func (mailbox *Mailbox) Len() int {
	return len(mailbox.queue)
}

func (mailbox *Mailbox) Snapshot() []Signal {
	return append([]Signal(nil), mailbox.queue...)
}

func signalFrom(signal Signal) term.PID {
	match signal {
	case UserSignal(from, _, _):
		return from
	case ExitSignal(from, _, _, _):
		return from
	case DownSignal(from, _, _, _, _):
		return from
	}
}

func signalSequence(signal Signal) uint64 {
	match signal {
	case UserSignal(_, sequence, _):
		return sequence
	case ExitSignal(_, sequence, _, _):
		return sequence
	case DownSignal(_, sequence, _, _, _):
		return sequence
	}
}

func withSequence(signal Signal, sequence uint64) Signal {
	match signal {
	case UserSignal(from, _, message):
		return UserSignal(from, sequence, message)
	case ExitSignal(from, _, reason, target):
		return ExitSignal(from, sequence, reason, target)
	case DownSignal(from, _, reason, reference, target):
		return DownSignal(from, sequence, reason, reference, target)
	}
}
