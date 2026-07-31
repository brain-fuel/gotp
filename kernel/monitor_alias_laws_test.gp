package kernel

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.kernel.monitor-alias-lifecycle
func TestMonitorAliasRoutesUntilDemonitor(t *testing.T) {
	property := func(message int64) bool {
		runtime := New(KernelConfig{})
		waiting := func(*Context) StepResult { return Wait() }
		var owner, target term.PID
		match runtime.Spawn(waiting, Unlinked(false)) { case result.Err(_): return false; case result.Ok(pid): owner = pid }
		match runtime.Spawn(waiting, Unlinked(false)) { case result.Err(_): return false; case result.Ok(pid): target = pid }
		var reference term.Reference
		match runtime.MonitorAlias(owner, target) { case result.Err(_): return false; case result.Ok(found): reference = found }
		match runtime.SendAlias(owner, reference, term.Integer(message)) { case NoProcess: return false; case Delivered: }
		match runtime.ProcessInfo(owner) { case option.None: return false; case option.Some(info): if info.MailboxLength != 1 { return false } }
		match runtime.Demonitor(owner, reference, false) { case MonitorAbsent: return false; case MonitorRemoved: }
		match runtime.SendAlias(owner, reference, term.Integer(message)) { case Delivered: return false; case NoProcess: }
		match runtime.ProcessInfo(owner) { case option.None: return false; case option.Some(info): return info.MailboxLength == 1 }
	}
	if cause := quick.Check(property, nil); cause != nil { t.Fatal(cause) }
}
