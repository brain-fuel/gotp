package erts

import (
	"fmt"
	"sync"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

type CodeGeneration struct {
	Module string
	Number uint64
	Digest string
}

type LoadOutcome enum {
	InitialCodeLoaded(Generation CodeGeneration)
	NewCodeLoaded(Current CodeGeneration, Old CodeGeneration)
}

type PurgeOutcome enum {
	NoOldCode()
	SoftPurged(Generation CodeGeneration)
	OldCodeInUse(Generation CodeGeneration, Leases int)
	ForcedPurged(Generation CodeGeneration, Leases int)
}

type LeaseMutation enum {
	LeaseReleased()
	LeaseAlreadyReleased()
}

type CodeServerFailure enum {
	NilCodeModule()
	MissingCodeModule(Name string)
	OldGenerationNotPurged(Name string, Generation CodeGeneration)
	PurgedCodeGeneration(Generation CodeGeneration)
	ReleasedCodeLease(Generation CodeGeneration)
}

func (failure CodeServerFailure) Error() string {
	match failure {
	case NilCodeModule:
		return "gotp/erts: hot-code module is nil"
	case MissingCodeModule(name):
		return fmt.Sprintf("gotp/erts: hot-code module %q is not loaded", name)
	case OldGenerationNotPurged(name, generation):
		return fmt.Sprintf("gotp/erts: old generation %s:%d must be purged before loading another %s", generation.Module, generation.Number, name)
	case PurgedCodeGeneration(generation):
		return fmt.Sprintf("gotp/erts: code generation %s:%d was purged", generation.Module, generation.Number)
	case ReleasedCodeLease(generation):
		return fmt.Sprintf("gotp/erts: code lease %s:%d was released", generation.Module, generation.Number)
	}
}

type loadedGeneration struct {
	identity CodeGeneration
	module *LoadedModule
	leases int
}

type codeSlot struct {
	next uint64
	current *loadedGeneration
	old *loadedGeneration
}

type CodeServer struct {
	mu sync.Mutex
	modules map[string]*codeSlot
}

type CodeLease struct {
	server *CodeServer
	generation CodeGeneration
	released bool
}

func NewCodeServer() *CodeServer {
	return &CodeServer{modules: make(map[string]*codeSlot)}
}

// assayxport:unit gotp.erts.hot-code-server
func (server *CodeServer) Load(module *LoadedModule) result.Result[LoadOutcome, CodeServerFailure] {
	if module == nil {
		return result.Err[LoadOutcome, CodeServerFailure](NilCodeModule())
	}
	server.mu.Lock()
	defer server.mu.Unlock()
	slot, present := server.modules[module.Name()]
	match option.Of(slot, present) {
	case option.None:
		created := &codeSlot{next: 1}
		generation := newLoadedGeneration(module, created.next)
		created.current = generation
		server.modules[module.Name()] = created
		return result.Ok[LoadOutcome, CodeServerFailure](InitialCodeLoaded(generation.identity))
	case option.Some(found):
		if found.old != nil {
			return result.Err[LoadOutcome, CodeServerFailure](OldGenerationNotPurged(module.Name(), found.old.identity))
		}
		found.next++
		found.old = found.current
		found.current = newLoadedGeneration(module, found.next)
		return result.Ok[LoadOutcome, CodeServerFailure](NewCodeLoaded(
			found.current.identity,
			found.old.identity,
		))
	}
}

func (server *CodeServer) Acquire(name string) result.Result[*CodeLease, CodeServerFailure] {
	server.mu.Lock()
	defer server.mu.Unlock()
	slot, present := server.modules[name]
	if !present || slot.current == nil {
		return result.Err[*CodeLease, CodeServerFailure](MissingCodeModule(name))
	}
	slot.current.leases++
	return result.Ok[*CodeLease, CodeServerFailure](&CodeLease{
		server: server,
		generation: slot.current.identity,
	})
}

func (server *CodeServer) SoftPurge(name string) result.Result[PurgeOutcome, CodeServerFailure] {
	server.mu.Lock()
	defer server.mu.Unlock()
	match server.slot(name) {
	case option.None:
		return result.Err[PurgeOutcome, CodeServerFailure](MissingCodeModule(name))
	case option.Some(slot):
		if slot.old == nil {
			return result.Ok[PurgeOutcome, CodeServerFailure](NoOldCode())
		}
		if slot.old.leases > 0 {
			return result.Ok[PurgeOutcome, CodeServerFailure](OldCodeInUse(slot.old.identity, slot.old.leases))
		}
		identity := slot.old.identity
		slot.old = nil
		return result.Ok[PurgeOutcome, CodeServerFailure](SoftPurged(identity))
	}
}

func (server *CodeServer) ForcePurge(name string) result.Result[PurgeOutcome, CodeServerFailure] {
	server.mu.Lock()
	defer server.mu.Unlock()
	match server.slot(name) {
	case option.None:
		return result.Err[PurgeOutcome, CodeServerFailure](MissingCodeModule(name))
	case option.Some(slot):
		if slot.old == nil {
			return result.Ok[PurgeOutcome, CodeServerFailure](NoOldCode())
		}
		identity := slot.old.identity
		leases := slot.old.leases
		slot.old = nil
		return result.Ok[PurgeOutcome, CodeServerFailure](ForcedPurged(identity, leases))
	}
}

func (lease *CodeLease) Module() result.Result[*LoadedModule, CodeServerFailure] {
	lease.server.mu.Lock()
	defer lease.server.mu.Unlock()
	if lease.released {
		return result.Err[*LoadedModule, CodeServerFailure](ReleasedCodeLease(lease.generation))
	}
	match lease.server.generation(lease.generation) {
	case option.None:
		return result.Err[*LoadedModule, CodeServerFailure](PurgedCodeGeneration(lease.generation))
	case option.Some(found):
		return result.Ok[*LoadedModule, CodeServerFailure](found.module)
	}
}

func (lease *CodeLease) Release() LeaseMutation {
	lease.server.mu.Lock()
	defer lease.server.mu.Unlock()
	if lease.released {
		return LeaseAlreadyReleased()
	}
	lease.released = true
	match lease.server.generation(lease.generation) {
	case option.None:
	case option.Some(found):
		if found.leases > 0 {
			found.leases--
		}
	}
	return LeaseReleased()
}

func (lease *CodeLease) Generation() CodeGeneration {
	return lease.generation
}

func (server *CodeServer) slot(name string) option.Option[*codeSlot] {
	slot, present := server.modules[name]
	return option.Of(slot, present)
}

func (server *CodeServer) generation(identity CodeGeneration) option.Option[*loadedGeneration] {
	slot, present := server.modules[identity.Module]
	if !present {
		return option.None[*loadedGeneration]
	}
	for _, candidate := range []*loadedGeneration{slot.current, slot.old} {
		if candidate != nil && candidate.identity.Number == identity.Number {
			return option.Some[*loadedGeneration](candidate)
		}
	}
	return option.None[*loadedGeneration]
}

func newLoadedGeneration(module *LoadedModule, number uint64) *loadedGeneration {
	return &loadedGeneration{
		identity: CodeGeneration{Module: module.Name(), Number: number, Digest: module.Digest()},
		module: module,
	}
}
