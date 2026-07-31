package kernel

import (
	"goforge.dev/goplus/std/memory"
	"goforge.dev/goplus/std/option"
	"goforge.dev/gotp/term"
)

type Signal enum {
	UserSignal(From term.PID, Sequence uint64, Message term.Term)
	ExitSignal(From term.PID, Sequence uint64, Reason term.Term, Target term.PID)
	DownSignal(From term.PID, Sequence uint64, Reason term.Term, Reference term.Reference, Target term.PID)
	DownNamedSignal(From term.PID, Sequence uint64, Reason term.Term, Reference term.Reference, Target string)
}

type MailboxMutation enum {
	SignalQueued()
}

type Mailbox struct {
	queue memory.Buffer[Signal]
}

func (mailbox *Mailbox) Push(signal Signal) MailboxMutation {
	mailbox.queue.Append(signal)
	return SignalQueued()
}

func (mailbox *Mailbox) Receive(
	accept func(Signal) bool,
) option.Option[Signal] {
	for index := 0; index < mailbox.queue.Len(); index++ { var signal Signal; match mailbox.queue.At(index) { case option.None: continue; case option.Some(found): signal = found }
		if accept != nil && !accept(signal) {
			continue
		}
		mailbox.queue.Remove(index)
		return option.Some[Signal](signal)
	}
	return option.None[Signal]
}

func (mailbox *Mailbox) Remove(match func(Signal) bool) int {
	if match == nil {
		removed := mailbox.queue.Len()
		mailbox.queue.Reset()
		return removed
	}
	write := 0; removed := 0
	for index := 0; index < mailbox.queue.Len(); index++ { var signal Signal; match mailbox.queue.At(index) { case option.None: continue; case option.Some(found): signal = found }
		if match(signal) {
			removed++
			continue
		}
		mailbox.queue.Set(write, signal); write++
	}
	mailbox.queue.Truncate(write)
	return removed
}

func (mailbox *Mailbox) Len() int {
	return mailbox.queue.Len()
}

func (mailbox *Mailbox) Snapshot() []Signal {
	snapshot := make([]Signal, 0, mailbox.queue.Len()); for index := 0; index < mailbox.queue.Len(); index++ { match mailbox.queue.At(index) { case option.None: case option.Some(signal): snapshot = append(snapshot, signal) } }; return snapshot
}

func (mailbox *Mailbox) Release() { mailbox.queue.Release() }
func (mailbox *Mailbox) Capacity() int { return mailbox.queue.Cap() }

func signalFrom(signal Signal) term.PID {
	match signal {
	case UserSignal(from, _, _):
		return from
	case ExitSignal(from, _, _, _):
		return from
	case DownSignal(from, _, _, _, _):
		return from
	case DownNamedSignal(from, _, _, _, _):
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
	case DownNamedSignal(_, sequence, _, _, _):
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
	case DownNamedSignal(from, _, reason, reference, target):
		return DownNamedSignal(from, sequence, reason, reference, target)
	}
}
