package beam

import (
	"fmt"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

type CodeInstallState enum {
	FirstCodeVersion()
	CurrentAndOldCodeVersions()
}

type CodePurgeState enum {
	NoOldCodeVersion()
	OldCodeVersionBusy(References int)
	OldCodeVersionPurged(InvalidatedReferences int)
}

type HotCodeFailure enum {
	InvalidCodeModule(Detail string)
	OldCodeNotPurged(Module string)
	CodeModuleNotLoaded(Module string)
	UnknownCodeReference(Generation uint64)
}

func (failure HotCodeFailure) Error() string {
	match failure {
	case InvalidCodeModule(detail): return "gotp/beam: invalid code module: " + detail
	case OldCodeNotPurged(module): return "gotp/beam: old code is not purged for " + module
	case CodeModuleNotLoaded(module): return "gotp/beam: code module is not loaded: " + module
	case UnknownCodeReference(generation): return fmt.Sprintf("gotp/beam: unknown code generation %d", generation)
	}
}

type CodeHandle struct {
	Module string
	Digest string
	Generation uint64
	Image *Module
}

type CodeReference struct {
	Module string
	Generation uint64
}

type CodeInstallTransition struct {
	Store CodeStore
	State CodeInstallState
	Current CodeHandle
	Old option.Option[CodeHandle]
}

type CodeEnterTransition struct {
	Store CodeStore
	Handle CodeHandle
	Reference CodeReference
}

type CodePurgeTransition struct {
	Store CodeStore
	State CodePurgeState
}

type codeGeneration struct {
	generation uint64
	image *Module
}

type codeSlot struct {
	current codeGeneration
	old *codeGeneration
}

type CodeStore struct {
	slots map[string]codeSlot
	references map[uint64]int
	nextGeneration uint64
}

func NewCodeStore() CodeStore {
	return CodeStore{slots: map[string]codeSlot{}, references: map[uint64]int{}, nextGeneration: 1}
}

// assayxport:unit gotp.beam.hot-code
func (store CodeStore) Install(image *Module) result.Result[CodeInstallTransition, HotCodeFailure] {
	if image == nil || image.Name == "" || image.Digest == "" { return result.Err[CodeInstallTransition, HotCodeFailure](InvalidCodeModule("name and digest are required")) }
	next := store.clone()
	generation := codeGeneration{generation: next.nextGeneration, image: cloneCodeModule(image)}
	next.nextGeneration++
	slot, loaded := next.slots[image.Name]
	if !loaded {
		next.slots[image.Name] = codeSlot{current: generation}
		return result.Ok[CodeInstallTransition, HotCodeFailure](CodeInstallTransition{Store: next, State: FirstCodeVersion(), Current: generation.handle(), Old: option.None[CodeHandle]()})
	}
	if slot.old != nil { return result.Err[CodeInstallTransition, HotCodeFailure](OldCodeNotPurged(image.Name)) }
	old := slot.current
	next.slots[image.Name] = codeSlot{current: generation, old: &old}
	return result.Ok[CodeInstallTransition, HotCodeFailure](CodeInstallTransition{Store: next, State: CurrentAndOldCodeVersions(), Current: generation.handle(), Old: option.Some(old.handle())})
}

func (store CodeStore) Current(module string) option.Option[CodeHandle] {
	slot, loaded := store.slots[module]
	match option.Of(slot, loaded) {
	case option.None: return option.None[CodeHandle]()
	case option.Some(slot): return option.Some(slot.current.handle())
	}
}

func (store CodeStore) Old(module string) option.Option[CodeHandle] {
	slot, loaded := store.slots[module]
	match option.Of(slot, loaded) {
	case option.None: return option.None[CodeHandle]()
	case option.Some(slot):
		if slot.old == nil { return option.None[CodeHandle]() }
		return option.Some(slot.old.handle())
	}
}

func (store CodeStore) EnterCurrent(module string) result.Result[CodeEnterTransition, HotCodeFailure] {
	slot, loaded := store.slots[module]
	if !loaded { return result.Err[CodeEnterTransition, HotCodeFailure](CodeModuleNotLoaded(module)) }
	next := store.clone()
	next.references[slot.current.generation]++
	reference := CodeReference{Module: module, Generation: slot.current.generation}
	return result.Ok[CodeEnterTransition, HotCodeFailure](CodeEnterTransition{Store: next, Handle: slot.current.handle(), Reference: reference})
}

func (store CodeStore) Leave(reference CodeReference) result.Result[CodeStore, HotCodeFailure] {
	count, present := store.references[reference.Generation]
	if !present || count < 1 { return result.Err[CodeStore, HotCodeFailure](UnknownCodeReference(reference.Generation)) }
	next := store.clone()
	if count == 1 { delete(next.references, reference.Generation) } else { next.references[reference.Generation] = count - 1 }
	return result.Ok[CodeStore, HotCodeFailure](next)
}

func (store CodeStore) SoftPurge(module string) CodePurgeTransition {
	return store.purgeOld(module, false)
}

func (store CodeStore) Purge(module string) CodePurgeTransition {
	return store.purgeOld(module, true)
}

func (store CodeStore) purgeOld(module string, force bool) CodePurgeTransition {
	slot, loaded := store.slots[module]
	if !loaded || slot.old == nil { return CodePurgeTransition{Store: store.clone(), State: NoOldCodeVersion()} }
	count := store.references[slot.old.generation]
	if count > 0 && !force { return CodePurgeTransition{Store: store.clone(), State: OldCodeVersionBusy(count)} }
	next := store.clone()
	nextSlot := next.slots[module]
	delete(next.references, nextSlot.old.generation)
	nextSlot.old = nil
	next.slots[module] = nextSlot
	return CodePurgeTransition{Store: next, State: OldCodeVersionPurged(count)}
}

func (store CodeStore) clone() CodeStore {
	next := NewCodeStore()
	next.nextGeneration = store.nextGeneration
	for module, slot := range store.slots {
		copied := codeSlot{current: slot.current.clone()}
		if slot.old != nil { old := slot.old.clone(); copied.old = &old }
		next.slots[module] = copied
	}
	for generation, count := range store.references { next.references[generation] = count }
	return next
}

func (generation codeGeneration) clone() codeGeneration {
	return codeGeneration{generation: generation.generation, image: cloneCodeModule(generation.image)}
}

func (generation codeGeneration) handle() CodeHandle {
	return CodeHandle{Module: generation.image.Name, Digest: generation.image.Digest, Generation: generation.generation, Image: cloneCodeModule(generation.image)}
}

func cloneCodeModule(module *Module) *Module {
	if module == nil { return nil }
	clone := *module
	clone.Atoms = append([]string{}, module.Atoms...)
	clone.Imports = append([]Import{}, module.Imports...)
	clone.Exports = append([]Export{}, module.Exports...)
	clone.Chunks = make([]Chunk, len(module.Chunks))
	for index, chunk := range module.Chunks { clone.Chunks[index] = chunk; clone.Chunks[index].Data = append([]byte{}, chunk.Data...) }
	clone.byID = map[string]int{}
	for id, index := range module.byID { clone.byID[id] = index }
	return &clone
}
