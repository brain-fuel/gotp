package beam

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

func codeFixture(name string, digest string) *Module { return &Module{Name: name, Digest: digest, Atoms: []string{name}} }

// assayxport:unit gotp.beam.hot-code-laws
func TestHotCodeMaintainsCurrentAndOldVersions(t *testing.T) {
	store := NewCodeStore()
	match store.Install(codeFixture("sample", "v1")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(first):
		store = first.Store
		match first.State { case FirstCodeVersion: case CurrentAndOldCodeVersions: t.Fatal("first install reported old code") }
	}
	match store.Install(codeFixture("sample", "v2")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(second):
		store = second.Store
		if second.Current.Digest != "v2" { t.Fatalf("current digest = %s", second.Current.Digest) }
		match second.Old { case option.None: t.Fatal("old code is absent"); case option.Some(old): if old.Digest != "v1" { t.Fatalf("old digest = %s", old.Digest) } }
	}
	match store.Install(codeFixture("sample", "v3")) {
	case result.Err(failure):
		match failure { case OldCodeNotPurged(module): if module != "sample" { t.Fatalf("module = %s", module) }; case _: t.Fatalf("unexpected failure: %s", failure.Error()) }
	case result.Ok(_): t.Fatal("third version was installed before purge")
	}
	purged := store.SoftPurge("sample")
	match purged.State { case OldCodeVersionPurged(count): if count != 0 { t.Fatalf("invalidated references = %d", count) }; case _: t.Fatalf("purge state = %v", purged.State) }
	match purged.Store.Install(codeFixture("sample", "v3")) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(third): if third.Current.Digest != "v3" { t.Fatalf("current digest = %s", third.Current.Digest) }
	}
}

func TestSoftPurgeRejectsLiveOldCodeAndForceInvalidates(t *testing.T) {
	store := NewCodeStore()
	match store.Install(codeFixture("sample", "v1")) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(loaded): store = loaded.Store }
	var reference CodeReference
	match store.EnterCurrent("sample") { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(entered): store = entered.Store; reference = entered.Reference }
	match store.Install(codeFixture("sample", "v2")) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(loaded): store = loaded.Store }
	busy := store.SoftPurge("sample")
	match busy.State { case OldCodeVersionBusy(count): if count != 1 { t.Fatalf("busy references = %d", count) }; case _: t.Fatalf("soft purge state = %v", busy.State) }
	forced := store.Purge("sample")
	match forced.State { case OldCodeVersionPurged(count): if count != 1 { t.Fatalf("invalidated references = %d", count) }; case _: t.Fatalf("forced purge state = %v", forced.State) }
	match forced.Store.Leave(reference) { case result.Err(failure): match failure { case UnknownCodeReference(_): case _: t.Fatalf("unexpected failure: %s", failure.Error()) }; case result.Ok(_): t.Fatal("purged reference remained valid") }
}

func TestCodeStoreSnapshotsDoNotAliasCallerModules(t *testing.T) {
	image := codeFixture("sample", "v1")
	match NewCodeStore().Install(image) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(loaded):
		image.Digest = "mutated"
		match loaded.Store.Current("sample") { case option.None: t.Fatal("current code absent"); case option.Some(current): if current.Digest != "v1" { t.Fatalf("stored digest = %s", current.Digest) } }
	}
}

func TestHotCodeNeverExposesMoreThanTwoVersions(t *testing.T) {
	law := func(loads []byte) bool {
		store := NewCodeStore()
		for index, load := range loads {
			if index >= 128 { break }
			match store.Install(codeFixture("sample", string([]byte{load}))) {
			case result.Err(failure):
				match failure { case OldCodeNotPurged(_): store = store.Purge("sample").Store; case _: return false }
			case result.Ok(transition): store = transition.Store
			}
			versions := 0
			match store.Current("sample") { case option.Some(_): versions++; case option.None: }
			match store.Old("sample") { case option.Some(_): versions++; case option.None: }
			if versions > 2 { return false }
		}
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 2000})) { case result.Err(cause): t.Fatal(cause); case result.Ok(_): }
}
