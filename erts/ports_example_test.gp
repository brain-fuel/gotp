package erts

import (
	"sync"
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type recordingDriver struct {
	mu sync.Mutex
	commands [][]byte
	closes int
}

func (driver *recordingDriver) capability() PortDriver {
	return PortDriver{Open: func(_ PortOpenRequest) PortOpenOutcome {
		return PortDriverOpened(PortDriverSession{
			Command: func(data []byte) PortCommandOutcome {
			driver.mu.Lock(); defer driver.mu.Unlock()
			driver.commands = append(driver.commands, append([]byte(nil), data...))
			return PortCommandOutput(append([]byte(nil), data...))
			},
			Close: func() PortCloseOutcome {
			driver.mu.Lock(); defer driver.mu.Unlock(); driver.closes++
			return PortDriverClosed(0)
			},
		})
	}}
}

func portOwner(number uint64) term.PID { return term.PID{Node: 1, Number: number, Creation: 1} }

func mustOpenPort(t *testing.T, manager *PortManager, owner term.PID, driver PortDriver) term.Port {
	match manager.Open(owner, term.Tuple(term.MustAtom("spawn"), term.Binary([]byte("demo"))), nil, driver) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(port): return port
	}
	panic("unreachable")
}

// assayxport:law gotp.erts.port-manager-laws
func TestPortOwnerCommandsAndClonedOutput(t *testing.T) {
	manager := NewPortManager(1, 1); owner := portOwner(1); driver := &recordingDriver{}; port := mustOpenPort(t, manager, owner, driver.capability())
	payload := []byte("hello")
	match manager.Command(owner, port, payload) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(outcome):
		var checked PortCommandOutcome = outcome
		match checked {
		case PortCommandOutput(output): payload[0] = 'X'; if string(output) != "hello" { t.Fatalf("output = %q", output) }
		case PortCommandAccepted, PortCommandRejected(_): t.Fatalf("command = %T", outcome)
		}
	}
	driver.mu.Lock(); recorded := string(driver.commands[0]); driver.mu.Unlock()
	if recorded != "hello" { t.Fatalf("driver input = %q", recorded) }
}

func TestPortRejectsNonOwnerAndClosesOnOwnerExit(t *testing.T) {
	manager := NewPortManager(1, 1); owner := portOwner(1); other := portOwner(2); driver := &recordingDriver{}; port := mustOpenPort(t, manager, owner, driver.capability())
	match manager.Command(other, port, []byte("forbidden")) { case result.Ok(_): t.Fatal("non-owner command succeeded"); case result.Err(_): }
	if manager.OwnerExit(owner) != 1 { t.Fatal("owner exit did not close port") }
	match manager.Command(owner, port, []byte("late")) { case result.Ok(_): t.Fatal("closed port accepted command"); case result.Err(_): }
	driver.mu.Lock(); closes := driver.closes; driver.mu.Unlock(); if closes != 1 { t.Fatalf("driver closes = %d", closes) }
}

func TestConcurrentCloseInvokesDriverOnce(t *testing.T) {
	manager := NewPortManager(1, 1); owner := portOwner(1); driver := &recordingDriver{}; port := mustOpenPort(t, manager, owner, driver.capability())
	var group sync.WaitGroup
	for index := 0; index < 32; index++ { group.Add(1); go func() { defer group.Done(); manager.Close(owner, port) }() }
	group.Wait(); driver.mu.Lock(); closes := driver.closes; driver.mu.Unlock()
	if closes != 1 { t.Fatalf("concurrent closes = %d", closes) }
}

func TestPortOpenRejectsIncompleteDriver(t *testing.T) {
	manager := NewPortManager(1, 1)
	match manager.Open(portOwner(1), term.MustAtom("bad"), nil, PortDriver{}) { case result.Ok(_): t.Fatal("nil driver opened"); case result.Err(_): }
}
