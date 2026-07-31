package kernel

import (
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func waitingProcess(_ *Context) StepResult {
	return Wait()
}

func exitReason(t *testing.T, runtime *Kernel, pid term.PID) option.Option[term.Term] {
	match runtime.ProcessInfo(pid) {
	case option.None:
		t.Fatal("process record is missing")
	case option.Some(info):
		return info.ExitReason
	}
	panic("unreachable")
}

// assayxport:law gotp.kernel.process-signal-laws
func TestKillIsUntrappableAndBecomesKilled(t *testing.T) {
	runtime := New(KernelConfig{})
	sender := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	target := mustSpawn(t, runtime, waitingProcess, Unlinked(true))
	match runtime.SendExit(sender, target, term.MustAtom("kill")) {
	case Delivered:
	case NoProcess:
		t.Fatal("kill target was missing")
	}
	match exitReason(t, runtime, target) {
	case option.None:
		t.Fatal("kill did not terminate target")
	case option.Some(reason):
		if !term.Equal(reason, term.MustAtom("killed")) {
			t.Fatalf("kill reason = %v", reason)
		}
	}
}

func TestNormalExitFromAnotherProcessIsIgnored(t *testing.T) {
	runtime := New(KernelConfig{})
	sender := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	target := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	runtime.SendExit(sender, target, term.MustAtom("normal"))
	match exitReason(t, runtime, target) {
	case option.None:
	case option.Some(reason):
		t.Fatalf("normal exit terminated target: %v", reason)
	}
}

func TestTrappedExitIsOrdinaryMailboxTuple(t *testing.T) {
	runtime := New(KernelConfig{})
	sender := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	var received option.Option[term.Term] = option.None[term.Term]
	target := mustSpawn(t, runtime, func(context *Context) StepResult {
		match context.ReceiveMessage(nil) {
		case option.None:
			return Wait()
		case option.Some(envelope):
			received = option.Some[term.Term](envelope.Message)
			return Stop(term.MustAtom("normal"))
		}
	}, Unlinked(true))
	runtime.SendExit(sender, target, term.MustAtom("shutdown"))
	runtime.Run(10)
	want := term.Tuple(term.MustAtom("EXIT"), term.PIDTerm(sender), term.MustAtom("shutdown"))
	match received {
	case option.None:
		t.Fatal("trapped exit was not received")
	case option.Some(message):
		if !term.Equal(message, want) {
			t.Fatalf("trapped exit = %v, want %v", message, want)
		}
	}
}

func TestMonitorDownIsOrdinaryMailboxTuple(t *testing.T) {
	runtime := New(KernelConfig{})
	var received option.Option[term.Term] = option.None[term.Term]
	watcher := mustSpawn(t, runtime, func(context *Context) StepResult {
		match context.ReceiveMessage(nil) {
		case option.None:
			return Wait()
		case option.Some(envelope):
			received = option.Some[term.Term](envelope.Message)
			return Stop(term.MustAtom("normal"))
		}
	}, Unlinked(false))
	target := mustSpawn(t, runtime, func(_ *Context) StepResult {
		return Stop(term.MustAtom("boom"))
	}, Unlinked(false))
	var monitored term.Reference
	match runtime.Monitor(watcher, target) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(found):
		monitored = found
	}
	runtime.Run(10)
	want := term.Tuple(
		term.MustAtom("DOWN"), term.ReferenceTerm(monitored), term.MustAtom("process"),
		term.PIDTerm(target), term.MustAtom("boom"),
	)
	match received {
	case option.None:
		t.Fatal("DOWN was not received")
	case option.Some(message):
		if !term.Equal(message, want) {
			t.Fatalf("DOWN = %v, want %v", message, want)
		}
	}
}
