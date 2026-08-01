package erts

import (
	"os"
	"strings"
	"testing"
	"time"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.otp29-gen-server-enter-loop
func TestPinnedOTPGenServerEnterLoop(t *testing.T) {
	payload, cause := os.ReadFile("testdata/otp-29.0.4-gen_server-enter-loop.corpus")
	if cause != nil { t.Fatal(cause) }
	var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
	var callback *LoadedModule
	match LoadModuleFile(read, "testdata/otp-29.0.4/gen_server_enter_loop_callbacks.beam", ModuleLoaderConfig{}) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): callback = found }
	dependencies := []string{"sets", "gen", "proc_lib", "sys", "global", "code", "io", "io_lib", "logger", "logger_config", "error_logger"}
	loaded := []*LoadedModule{callback, pinnedGenServerModule(t), pinnedListsModule(t), pinnedMapsModule(t)}
	for _, dependency := range dependencies { loaded = append(loaded, pinnedStdlibDependency(t, dependency)) }
	var modules *ModuleSet
	match NewModuleSet(loaded) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): modules = found }
	registry := otpRegistryForInvocation(t)
	for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
		fields := strings.Split(line, "|")
		if len(fields) != 3 || fields[0] != "case" { t.Fatalf("line %d is malformed", lineNumber+1) }
		var process *VMProcess
		match modules.Invoke("gen_server_enter_loop_callbacks", fields[1], []term.Term{}, clock.Real{}, registry) { case result.Err(failure): t.Fatal(failure); case result.Ok(created): process = created }
		runtime := kernel.New(kernel.KernelConfig{})
		runtime.PersistentPut(term.Tuple(term.MustAtom("logger_config"), term.MustAtom("$primary_config$")), term.Integer(0))
		match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
		deadline := time.Now().Add(500 * time.Millisecond)
		for time.Now().Before(deadline) {
			runtime.Run(1_000_000)
			settled := false
			match process.State() { case VMProcessWaiting(_, _), VMProcessSuspended(_, _): time.Sleep(time.Millisecond); case _: settled = true }
			if settled { break }
		}
		assertGenServerCorpusOutcome(t, fields[1], 0, process.State(), decodeGenServerCorpusTerm(t, fields[2]))
	}
}
