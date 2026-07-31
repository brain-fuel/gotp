package vm

import (
	"testing"

	"goforge.dev/goplus/std/memory"
	"goforge.dev/goplus/std/option"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.vm.stack-memory-laws
func TestProcessMemoryReleaseClearsStacksAndLeavesCodeOnce(t *testing.T) {
	trace := []string{}; machine := &Machine{returns: memory.NewBuffer[returnFrame](4), handlers: memory.NewBuffer[exceptionHandler](2), x: memory.NewBuffer[option.Option[term.Term]](1), y: memory.NewBuffer[option.Option[term.Term]](1)}
	machine.x.Append(option.Some[term.Term](term.MustAtom("x"))); machine.y.Append(option.Some[term.Term](term.MustAtom("y")))
	machine.currentCodeLeave = func() { trace = append(trace, "current") }
	machine.returns.Append(returnFrame{codeLeave: func() { trace = append(trace, "first") }}); machine.returns.Append(returnFrame{codeLeave: func() { trace = append(trace, "second") }})
	machine.handlers.Append(exceptionHandler{pending: option.Some(pendingException{class: term.MustAtom("error"), reason: term.MustAtom("reason"), trace: term.List()})})
	machine.resetProcessMemory(); machine.resetProcessMemory()
	want := []string{"current", "second", "first"}; if len(trace) != len(want) { t.Fatalf("trace = %v", trace) }; for index := range want { if trace[index] != want[index] { t.Fatalf("trace = %v", trace) } }
	if machine.returns.Cap() != 0 || machine.handlers.Cap() != 0 || machine.y.Cap() != 0 { t.Fatalf("capacities = %d/%d/%d", machine.returns.Cap(), machine.handlers.Cap(), machine.y.Cap()) }
}
