package release

import (
	"testing"

	"goforge.dev/goplus/std/result"
)

func effectCapability(t *testing.T, execute ExecuteEffect, rollback RollbackEffect) EffectCapability {
	t.Helper(); match NewEffectCapability(execute, rollback) { case result.Err(failure): t.Fatal(failure.Error()); return nil; case result.Ok(capability): return capability }
}

// assayxport:law gotp.otp.release-executor-laws
func TestPreflightFailureRollsBackInReverseOrder(t *testing.T) {
	script := Script{CommitIndex: 2, Instructions: []Instruction{
		LoadObjectCode("one", "1", []string{"a"}), LoadObjectCode("two", "1", []string{"b"}), PointOfNoReturn(), PurgeCode([]string{"a"}),
	}}
	executed := []string{}; rolledBack := []string{}
	capability := effectCapability(t, func(instruction Instruction) EffectOutcome {
		match instruction { case LoadObjectCode(library, _, _): executed = append(executed, library); if library == "two" { return EffectRejected("staging failed") }; case _: }
		return EffectApplied()
	}, func(instruction Instruction) RollbackOutcome { match instruction { case LoadObjectCode(library, _, _): rolledBack = append(rolledBack, library); case _: }; return RollbackApplied() })
	match Execute(script, capability) {
	case result.Err(failure): match failure { case PreflightRejected(index, _, count): if index != 1 || count != 1 { t.Fatalf("failure = %v", failure) }; case _: t.Fatalf("failure = %v", failure) }
	case result.Ok(_): t.Fatal("failed preflight succeeded")
	}
	if len(executed) != 2 || len(rolledBack) != 1 || rolledBack[0] != "one" { t.Fatalf("executed/rollback = %v/%v", executed, rolledBack) }
}

func TestCommitFailureNeverRollsBack(t *testing.T) {
	script := Script{CommitIndex: 1, Instructions: []Instruction{LoadObjectCode("one", "1", []string{"a"}), PointOfNoReturn(), LoadCode("a", SoftPurge(), SoftPurge())}}
	rollbacks := 0
	capability := effectCapability(t, func(instruction Instruction) EffectOutcome { match instruction { case LoadCode(_, _, _): return EffectRejected("load failed"); case _: return EffectApplied() } }, func(Instruction) RollbackOutcome { rollbacks++; return RollbackApplied() })
	match Execute(script, capability) { case result.Err(failure): match failure { case CommitRejected(index, _, _): if index != 2 { t.Fatalf("index = %d", index) }; case _: t.Fatalf("failure = %v", failure) }; case result.Ok(_): t.Fatal("failed commit succeeded") }
	if rollbacks != 0 { t.Fatalf("commit rollbacks = %d", rollbacks) }
}

func TestRestartIsExplicitExecutionOutcome(t *testing.T) {
	script := Script{CommitIndex: -1, Instructions: []Instruction{RestartEmulator()}}
	capability := effectCapability(t, func(Instruction) EffectOutcome { return EffectRestartRequested(CurrentEmulatorRestart()) }, func(Instruction) RollbackOutcome { return RollbackApplied() })
	match Execute(script, capability) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(report): match report { case ReleaseRestarted(kind, applied, committed): match kind { case CurrentEmulatorRestart: case NewEmulatorRestart: t.Fatal("wrong restart kind") }; if applied != 0 || committed { t.Fatalf("restart state = %d/%v", applied, committed) }; case _: t.Fatalf("report = %v", report) } }
}

func TestExecutorRevalidatesConstructedScriptsBeforeEffects(t *testing.T) {
	runs := 0
	script := Script{CommitIndex: 0, Instructions: []Instruction{LoadCode("missing", SoftPurge(), SoftPurge())}}
	capability := effectCapability(t, func(Instruction) EffectOutcome { runs++; return EffectApplied() }, func(Instruction) RollbackOutcome { return RollbackApplied() })
	match Execute(script, capability) { case result.Err(_): case result.Ok(_): t.Fatal("invalid constructed script succeeded") }
	if runs != 0 { t.Fatalf("effects before validation = %d", runs) }
}
