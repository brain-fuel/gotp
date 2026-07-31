package erts

import (
	"fmt"
	"sync"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type PortOpenRequest struct {
	Owner term.PID
	Name term.Term
	Settings []term.Term
}

type PortCommandOutcome enum {
	PortCommandAccepted()
	PortCommandOutput(Data []byte)
	PortCommandRejected(Detail string)
}

type PortCloseOutcome enum {
	PortDriverClosed(Status int)
	PortCloseRejected(Detail string)
}

type PortDriverSession struct {
	Command func(Data []byte) PortCommandOutcome
	Close func() PortCloseOutcome
}

type PortOpenOutcome enum {
	PortDriverOpened(Session PortDriverSession)
	PortOpenRejected(Detail string)
}

type PortDriver struct {
	Open func(Request PortOpenRequest) PortOpenOutcome
}

type PortFailure enum {
	InvalidPortDriver(Detail string)
	PortDriverFailure(Operation string, Detail string)
	MissingPort(Port term.Port)
	PortOwnerRequired(Port term.Port, Caller term.PID)
}

func (failure PortFailure) Error() string {
	match failure {
	case InvalidPortDriver(detail):
		return "gotp/erts: invalid port driver: " + detail
	case PortDriverFailure(operation, detail):
		return fmt.Sprintf("gotp/erts: port driver %s: %s", operation, detail)
	case MissingPort(port):
		return fmt.Sprintf("gotp/erts: port %v does not exist", port)
	case PortOwnerRequired(port, caller):
		return fmt.Sprintf("gotp/erts: process %v is not owner of port %v", caller, port)
	}
}

type portState struct {
	mu sync.Mutex
	identity term.Port
	owner term.PID
	session PortDriverSession
	closed bool
}

type PortManager struct {
	mu sync.RWMutex
	node uint32
	creation uint32
	next uint64
	ports map[term.Port]*portState
}

func NewPortManager(node uint32, creation uint32) *PortManager {
	if node == 0 { node = 1 }
	if creation == 0 { creation = 1 }
	return &PortManager{node: node, creation: creation, ports: make(map[term.Port]*portState)}
}

// assayxport:unit gotp.erts.port-manager
func (manager *PortManager) Open(
	owner term.PID,
	name term.Term,
	settings []term.Term,
	driver PortDriver,
) result.Result[term.Port, PortFailure] {
	if driver.Open == nil {
		return result.Err[term.Port, PortFailure](InvalidPortDriver("open effect is nil"))
	}
	clonedSettings := make([]term.Term, len(settings))
	for index, setting := range settings { clonedSettings[index] = setting.Clone() }
	var session PortDriverSession
	match driver.Open(PortOpenRequest{Owner: owner, Name: name.Clone(), Settings: clonedSettings}) {
	case PortOpenRejected(detail):
		return result.Err[term.Port, PortFailure](PortDriverFailure("open", detail))
	case PortDriverOpened(opened):
		if opened.Command == nil || opened.Close == nil {
			return result.Err[term.Port, PortFailure](InvalidPortDriver("session effects must be complete"))
		}
		session = opened
	}
	manager.mu.Lock()
	defer manager.mu.Unlock()
	manager.next++
	identity := term.Port{Node: manager.node, ID: manager.next, Creation: manager.creation}
	manager.ports[identity] = &portState{identity: identity, owner: owner, session: session}
	return result.Ok[term.Port, PortFailure](identity)
}

func (manager *PortManager) Command(
	caller term.PID,
	identity term.Port,
	data []byte,
) result.Result[PortCommandOutcome, PortFailure] {
	match manager.port(identity) {
	case option.None:
		return result.Err[PortCommandOutcome, PortFailure](MissingPort(identity))
	case option.Some(port):
		port.mu.Lock()
		defer port.mu.Unlock()
		if port.closed {
			return result.Err[PortCommandOutcome, PortFailure](MissingPort(identity))
		}
		if port.owner != caller {
			return result.Err[PortCommandOutcome, PortFailure](PortOwnerRequired(identity, caller))
		}
		match port.session.Command(append([]byte(nil), data...)) {
		case PortCommandRejected(detail):
			return result.Err[PortCommandOutcome, PortFailure](PortDriverFailure("command", detail))
		case PortCommandAccepted:
			return result.Ok[PortCommandOutcome, PortFailure](PortCommandAccepted())
		case PortCommandOutput(output):
			return result.Ok[PortCommandOutcome, PortFailure](PortCommandOutput(append([]byte(nil), output...)))
		}
	}
}

func (manager *PortManager) Close(
	caller term.PID,
	identity term.Port,
) result.Result[PortCloseOutcome, PortFailure] {
	match manager.port(identity) {
	case option.None:
		return result.Err[PortCloseOutcome, PortFailure](MissingPort(identity))
	case option.Some(port):
		port.mu.Lock()
		defer port.mu.Unlock()
		if port.closed {
			return result.Err[PortCloseOutcome, PortFailure](MissingPort(identity))
		}
		if port.owner != caller {
			return result.Err[PortCloseOutcome, PortFailure](PortOwnerRequired(identity, caller))
		}
		match port.session.Close() {
		case PortCloseRejected(detail):
			return result.Err[PortCloseOutcome, PortFailure](PortDriverFailure("close", detail))
		case PortDriverClosed(status):
			port.closed = true
			manager.remove(identity)
			return result.Ok[PortCloseOutcome, PortFailure](PortDriverClosed(status))
		}
	}
}

func (manager *PortManager) OwnerExit(owner term.PID) int {
	manager.mu.RLock()
	owned := []term.Port{}
	for identity, port := range manager.ports {
		if port.owner == owner { owned = append(owned, identity) }
	}
	manager.mu.RUnlock()
	closed := 0
	for _, identity := range owned {
		match manager.Close(owner, identity) {
		case result.Err(_):
		case result.Ok(_): closed++
		}
	}
	return closed
}

func (manager *PortManager) port(identity term.Port) option.Option[*portState] {
	manager.mu.RLock()
	defer manager.mu.RUnlock()
	port, present := manager.ports[identity]
	return option.Of(port, present)
}

func (manager *PortManager) remove(identity term.Port) {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	delete(manager.ports, identity)
}
