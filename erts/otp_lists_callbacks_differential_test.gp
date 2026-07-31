package erts

import (
	"os"
	"strconv"
	"strings"
	"testing"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.otp29-lists-callback-differential
// assayxport:law gotp.erts.otp29-lists-callback-differential
func TestPinnedOTPListsCallbackDifferentialCorpus(t *testing.T) {
	payload, cause := os.ReadFile("testdata/otp-29.0.4-lists-callbacks.corpus")
	if cause != nil { t.Fatal(cause) }
	var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
	var callback *LoadedModule
	match LoadModuleFile(read, "testdata/otp-29.0.4/lists_callbacks.beam", ModuleLoaderConfig{}) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): callback = found }
	var modules *ModuleSet
	match NewModuleSet([]*LoadedModule{pinnedListsModule(t), callback}) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): modules = found }
	registry := otpRegistryForInvocation(t)
	for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
		if strings.HasPrefix(line, "#") { continue }
		fields := strings.Split(line, "|")
		if len(fields) != 6 || fields[0] != "case" { t.Fatalf("line %d is malformed", lineNumber+1) }
		arity, cause := strconv.Atoi(fields[2])
		if cause != nil { t.Fatal(cause) }
		argumentsTerm := decodeListsCorpusTerm(t, fields[4])
		var arguments []term.Term
		match argumentsTerm { case term.ProperListTerm(found): arguments = found; case _: t.Fatalf("%s/%d arguments differ", fields[1], arity) }
		var process *VMProcess
		match modules.Invoke("lists_callbacks", fields[1], arguments, clock.Real{}, registry) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): process = found }
		runListsCorpusProcess(t, process)
		assertListsCorpusOutcome(t, fields[1], arity, process.State(), decodeListsCorpusTerm(t, fields[5]))
	}
}
