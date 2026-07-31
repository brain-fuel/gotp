package kernel

import (
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func mustAlias(t *testing.T, runtime *Kernel, owner term.PID) term.Reference {
	match runtime.Alias(owner) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(reference):
		return reference
	}
	panic("unreachable")
}

// assayxport:law gotp.kernel.process-alias-laws
func TestAliasRoutesMessagesAndPreservesSender(t *testing.T) {
	runtime := New(KernelConfig{})
	sender := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	var received option.Option[MessageEnvelope] = option.None[MessageEnvelope]
	owner := mustSpawn(t, runtime, func(context *Context) StepResult {
		match context.ReceiveMessage(nil) {
		case option.None:
			return Wait()
		case option.Some(envelope):
			received = option.Some[MessageEnvelope](envelope)
			return Stop(term.MustAtom("normal"))
		}
	}, Unlinked(false))
	reference := mustAlias(t, runtime, owner)
	match runtime.SendAlias(sender, reference, term.MustAtom("reply")) {
	case Delivered:
	case NoProcess:
		t.Fatal("live alias rejected message")
	}
	runtime.Run(10)
	match received {
	case option.None:
		t.Fatal("alias message was not received")
	case option.Some(envelope):
		if envelope.From != sender || !term.Equal(envelope.Message, term.MustAtom("reply")) {
			t.Fatalf("alias envelope = %#v", envelope)
		}
	}
}

func TestOnlyOwnerCanRevokeAlias(t *testing.T) {
	runtime := New(KernelConfig{})
	owner := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	other := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	reference := mustAlias(t, runtime, owner)
	match runtime.Unalias(other, reference) {
	case AliasRemoved:
		t.Fatal("non-owner revoked alias")
	case AliasAbsent:
	}
	match runtime.SendAlias(other, reference, term.MustAtom("still_live")) {
	case Delivered:
	case NoProcess:
		t.Fatal("non-owner revocation changed routing")
	}
	match runtime.Unalias(owner, reference) {
	case AliasRemoved:
	case AliasAbsent:
		t.Fatal("owner could not revoke alias")
	}
	match runtime.SendAlias(other, reference, term.MustAtom("stale")) {
	case Delivered:
		t.Fatal("revoked alias accepted message")
	case NoProcess:
	}
}

func TestOwnerExitRevokesEveryAlias(t *testing.T) {
	runtime := New(KernelConfig{})
	owner := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	sender := mustSpawn(t, runtime, waitingProcess, Unlinked(false))
	aliases := []term.Reference{mustAlias(t, runtime, owner), mustAlias(t, runtime, owner)}
	runtime.Exit(owner, term.MustAtom("shutdown"))
	for _, reference := range aliases {
		match runtime.SendAlias(sender, reference, term.MustAtom("stale")) {
		case Delivered:
			t.Fatal("dead owner's alias accepted message")
		case NoProcess:
		}
	}
}
