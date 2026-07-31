package erts

import (
	"sync"
	"testing"

	"goforge.dev/goplus/std/result"
)

func codeVersions(t *testing.T) (*LoadedModule, *LoadedModule, *LoadedModule) {
	first := loadedImportDemo(t)
	secondValue := *first
	secondValue.digest = "second"
	thirdValue := *first
	thirdValue.digest = "third"
	return first, &secondValue, &thirdValue
}

func mustLoadCode(t *testing.T, server *CodeServer, module *LoadedModule) LoadOutcome {
	match server.Load(module) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(outcome):
		return outcome
	}
	panic("unreachable")
}

func mustAcquireCode(t *testing.T, server *CodeServer, name string) *CodeLease {
	match server.Acquire(name) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(lease):
		return lease
	}
	panic("unreachable")
}

// assayxport:law gotp.erts.hot-code-server-laws
func TestTwoVersionLoadRequiresExplicitOldPurge(t *testing.T) {
	first, second, third := codeVersions(t)
	server := NewCodeServer()
	mustLoadCode(t, server, first)
	oldLease := mustAcquireCode(t, server, first.Name())
	mustLoadCode(t, server, second)
	match server.Load(third) {
	case result.Ok(_):
		t.Fatal("third version loaded before purge")
	case result.Err(_):
	}
	match server.SoftPurge(first.Name()) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(outcome):
		var checked PurgeOutcome = outcome
		match checked {
		case OldCodeInUse(_, leases):
			if leases != 1 { t.Fatalf("old leases = %d", leases) }
		case NoOldCode, SoftPurged(_), ForcedPurged(_, _):
			t.Fatalf("soft purge outcome = %T", outcome)
		}
	}
	oldLease.Release()
	match server.SoftPurge(first.Name()) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(outcome):
		var checked PurgeOutcome = outcome
		match checked { case SoftPurged(_): case NoOldCode, OldCodeInUse(_, _), ForcedPurged(_, _): t.Fatalf("soft purge = %T", outcome) }
	}
	mustLoadCode(t, server, third)
	current := mustAcquireCode(t, server, first.Name())
	if current.Generation().Digest != "third" { t.Fatalf("current generation = %#v", current.Generation()) }
}

func TestForcedPurgeInvalidatesOldLease(t *testing.T) {
	first, second, _ := codeVersions(t)
	server := NewCodeServer(); mustLoadCode(t, server, first); old := mustAcquireCode(t, server, first.Name()); mustLoadCode(t, server, second)
	match server.ForcePurge(first.Name()) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(outcome):
		var checked PurgeOutcome = outcome
		match checked { case ForcedPurged(_, leases): if leases != 1 { t.Fatalf("forced leases = %d", leases) }; case NoOldCode, SoftPurged(_), OldCodeInUse(_, _): t.Fatalf("force purge = %T", outcome) }
	}
	match old.Module() { case result.Ok(_): t.Fatal("purged lease resolved module"); case result.Err(_): }
}

func TestLeaseReleaseIsConcurrentAndIdempotent(t *testing.T) {
	first, _, _ := codeVersions(t)
	server := NewCodeServer(); mustLoadCode(t, server, first); lease := mustAcquireCode(t, server, first.Name())
	var group sync.WaitGroup
	for index := 0; index < 32; index++ { group.Add(1); go func() { defer group.Done(); lease.Release() }() }
	group.Wait()
	match lease.Module() { case result.Ok(_): t.Fatal("released lease resolved module"); case result.Err(_): }
}
