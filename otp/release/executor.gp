package release

import (
	"fmt"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type RestartKind enum {
	CurrentEmulatorRestart()
	NewEmulatorRestart()
}

type EffectOutcome enum {
	EffectApplied()
	EffectRejected(Detail string)
	EffectRestartRequested(Kind RestartKind)
}

type RollbackOutcome enum {
	RollbackApplied()
	RollbackRejected(Detail string)
}

type ExecuteEffect func(Instruction) EffectOutcome
type RollbackEffect func(Instruction) RollbackOutcome

//goplus:derive off
type EffectCapability enum {
	ReleaseEffects(Execute ExecuteEffect, Rollback RollbackEffect)
}

type ExecutionReport enum {
	ReleaseCompleted(Applied int)
	ReleaseRestarted(Kind RestartKind, Applied int, Committed bool)
}

type ExecutionFailure enum {
	InvalidEffects(Detail string)
	InvalidScript(Cause ScriptFailure)
	PreflightRejected(Index int, Detail string, RolledBack int)
	PreflightRollbackRejected(Index int, Cause string, RollbackDetail string, RolledBack int)
	CommitRejected(Index int, Detail string, Applied int)
}

func (failure ExecutionFailure) Error() string {
	match failure {
	case InvalidEffects(detail): return "gotp/release: invalid effects: " + detail
	case InvalidScript(cause): return cause.Error()
	case PreflightRejected(index, detail, rolledBack): return fmt.Sprintf("gotp/release: preflight instruction %d rejected after %d rollbacks: %s", index, rolledBack, detail)
	case PreflightRollbackRejected(index, cause, rollback, rolledBack): return fmt.Sprintf("gotp/release: preflight instruction %d rejected (%s); rollback failed after %d operations: %s", index, cause, rolledBack, rollback)
	case CommitRejected(index, detail, applied): return fmt.Sprintf("gotp/release: committed instruction %d rejected after %d operations: %s", index, applied, detail)
	}
}

func NewEffectCapability(execute ExecuteEffect, rollback RollbackEffect) result.Result[EffectCapability, ExecutionFailure] {
	if execute == nil { return result.Err[EffectCapability, ExecutionFailure](InvalidEffects("execute effect is nil")) }
	if rollback == nil { return result.Err[EffectCapability, ExecutionFailure](InvalidEffects("rollback effect is nil")) }
	return result.Ok[EffectCapability, ExecutionFailure](ReleaseEffects(execute, rollback))
}

// assayxport:unit gotp.otp.release-executor
func Execute(script Script, capability EffectCapability) result.Result[ExecutionReport, ExecutionFailure] {
	match validateScript(script.Instructions) {
	case result.Err(cause): return result.Err[ExecutionReport, ExecutionFailure](InvalidScript(cause))
	case result.Ok(commit): if commit != script.CommitIndex { return result.Err[ExecutionReport, ExecutionFailure](InvalidScript(InvalidOrdering(commit, "commit index differs from instructions"))) }
	}
	var execute ExecuteEffect
	var rollback RollbackEffect
	match capability { case ReleaseEffects(run, undo): execute = run; rollback = undo }
	if execute == nil || rollback == nil { return result.Err[ExecutionReport, ExecutionFailure](InvalidEffects("capability contains nil effect")) }
	applied := 0
	preflightApplied := []Instruction{}
	if script.CommitIndex >= 0 {
		for index, instruction := range script.Instructions[:script.CommitIndex] {
			match execute(cloneInstruction(instruction)) {
			case EffectApplied: preflightApplied = append(preflightApplied, cloneInstruction(instruction)); applied++
			case EffectRestartRequested(kind): return result.Ok[ExecutionReport, ExecutionFailure](ReleaseRestarted(kind, applied, false))
			case EffectRejected(detail): return rollbackPreflight(index, detail, preflightApplied, rollback)
			}
		}
	}
	start := 0
	if script.CommitIndex >= 0 { start = script.CommitIndex }
	for offset, instruction := range script.Instructions[start:] {
		index := start + offset
		match execute(cloneInstruction(instruction)) {
		case EffectApplied: applied++
		case EffectRestartRequested(kind): return result.Ok[ExecutionReport, ExecutionFailure](ReleaseRestarted(kind, applied, script.CommitIndex >= 0 && index >= script.CommitIndex))
		case EffectRejected(detail): return result.Err[ExecutionReport, ExecutionFailure](CommitRejected(index, detail, applied))
		}
	}
	return result.Ok[ExecutionReport, ExecutionFailure](ReleaseCompleted(applied))
}

func rollbackPreflight(index int, cause string, applied []Instruction, rollback RollbackEffect) result.Result[ExecutionReport, ExecutionFailure] {
	rolledBack := 0
	for position := len(applied) - 1; position >= 0; position-- {
		match rollback(cloneInstruction(applied[position])) {
		case RollbackApplied: rolledBack++
		case RollbackRejected(detail): return result.Err[ExecutionReport, ExecutionFailure](PreflightRollbackRejected(index, cause, detail, rolledBack))
		}
	}
	return result.Err[ExecutionReport, ExecutionFailure](PreflightRejected(index, cause, rolledBack))
}

func cloneInstruction(instruction Instruction) Instruction {
	match instruction {
	case LoadObjectCode(library, version, modules): return LoadObjectCode(library, version, append([]string{}, modules...))
	case PointOfNoReturn: return PointOfNoReturn()
	case LoadCode(module, pre, post): return LoadCode(module, pre, post)
	case RemoveCode(module, pre, post): return RemoveCode(module, pre, post)
	case PurgeCode(modules): return PurgeCode(append([]string{}, modules...))
	case SuspendCode(targets): return SuspendCode(append([]SuspendTarget{}, targets...))
	case ResumeCode(modules): return ResumeCode(append([]string{}, modules...))
	case ChangeCode(mode, targets):
		cloned := make([]ChangeTarget, len(targets)); for index, target := range targets { cloned[index] = ChangeTarget{Module: target.Module, Extra: target.Extra.Clone()} }; return ChangeCode(mode, cloned)
	case StopCode(modules): return StopCode(append([]string{}, modules...))
	case StartCode(modules): return StartCode(append([]string{}, modules...))
	case SyncNodesList(id, nodes): return SyncNodesList(id.Clone(), append([]string{}, nodes...))
	case SyncNodesApply(id, call): return SyncNodesApply(id.Clone(), cloneMFA(call))
	case Apply(call): return Apply(cloneMFA(call))
	case RestartEmulator: return RestartEmulator()
	case RestartNewEmulator: return RestartNewEmulator()
	}
}

func cloneMFA(call MFA) MFA { arguments := make([]term.Term, len(call.Arguments)); for index, argument := range call.Arguments { arguments[index] = argument.Clone() }; return MFA{Module: call.Module, Function: call.Function, Arguments: arguments} }
