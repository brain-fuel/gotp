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

type multiCallHarness struct {
	cluster *VirtualCluster
	local VirtualNode
	first VirtualNode
	second VirtualNode
	modules *ModuleSet
	registry *CallRegistry
}

// assayxport:law gotp.erts.otp29-gen-server-multi-call
func TestPinnedOTPGenServerMultiCall(t *testing.T) {
	payload, cause := os.ReadFile("testdata/otp-29.0.4-gen_server-multicall.corpus")
	if cause != nil { t.Fatal(cause) }
	for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
		fields := strings.Split(line, "|")
		if len(fields) != 3 || fields[0] != "case" { t.Fatalf("line %d is malformed", lineNumber+1) }
		harness := newMultiCallHarness(t)
		prepareMultiCallCase(t, harness, fields[1])
		arguments := []term.Term{}
		if fields[1] != "empty_nodes" { arguments = []term.Term{multiCallNodes()} }
		process := invokeMultiCall(t, harness, fields[1], arguments)
		runMultiCallUntilSettled(t, harness.cluster, process)
		assertGenServerCorpusOutcome(t, fields[1], len(arguments), process.State(), decodeGenServerCorpusTerm(t, fields[2]))
	}
}

func newMultiCallHarness(t *testing.T) multiCallHarness {
	cluster := NewVirtualCluster()
	var local, first, second VirtualNode
	match cluster.AddNode("local@gotp", 1, 1) { case result.Err(failure): t.Fatal(failure); case result.Ok(node): local = node }
	match cluster.AddNode("first@gotp", 2, 1) { case result.Err(failure): t.Fatal(failure); case result.Ok(node): first = node }
	match cluster.AddNode("second@gotp", 3, 1) { case result.Err(failure): t.Fatal(failure); case result.Ok(node): second = node }
	var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
	var callback *LoadedModule
	match LoadModuleFile(read, "testdata/otp-29.0.4/gen_server_multicall_callbacks.beam", ModuleLoaderConfig{}) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): callback = found }
	dependencies := []string{"sets", "gen", "proc_lib", "sys", "global", "code", "io", "io_lib", "logger", "logger_config", "error_logger"}
	loaded := []*LoadedModule{callback, pinnedGenServerModule(t), pinnedListsModule(t), pinnedMapsModule(t)}
	for _, dependency := range dependencies { loaded = append(loaded, pinnedStdlibDependency(t, dependency)) }
	var modules *ModuleSet
	match NewModuleSet(loaded) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): modules = found }
	return multiCallHarness{cluster: cluster, local: local, first: first, second: second, modules: modules, registry: otpRegistryForInvocation(t)}
}

func multiCallNodes() term.Term { return term.List(term.MustAtom("first@gotp"), term.MustAtom("second@gotp")) }

func prepareMultiCallCase(t *testing.T, harness multiCallHarness, function string) {
	switch function {
	case "multi_call_2": startMultiCallServer(t, harness, harness.local, "multicall_all", "normal"); startMultiCallServer(t, harness, harness.first, "multicall_all", "normal"); startMultiCallServer(t, harness, harness.second, "multicall_all", "normal")
	case "multi_call_3": startMultiCallServer(t, harness, harness.local, "multicall_three", "normal"); startMultiCallServer(t, harness, harness.first, "multicall_three", "normal"); startMultiCallServer(t, harness, harness.second, "multicall_three", "normal")
	case "multi_call_4": startMultiCallServer(t, harness, harness.local, "multicall_four", "normal"); startMultiCallServer(t, harness, harness.first, "multicall_four", "normal"); startMultiCallServer(t, harness, harness.second, "multicall_four", "normal")
	case "mixed_missing_name": startMultiCallServer(t, harness, harness.first, "multicall_mixed", "normal")
	case "crashing_server": startMultiCallServer(t, harness, harness.first, "multicall_crash", "crash")
	case "timeout_late_cleanup": startMultiCallServer(t, harness, harness.first, "multicall_late", "late")
	case "duplicate_nodes": startMultiCallServer(t, harness, harness.first, "multicall_duplicate", "normal")
	case "reply_order": startMultiCallServer(t, harness, harness.local, "multicall_order", "normal"); startMultiCallServer(t, harness, harness.first, "multicall_order", "normal"); startMultiCallServer(t, harness, harness.second, "multicall_order", "normal")
	case "unavailable_node", "empty_nodes":
	default: t.Fatalf("unknown multi_call case %s", function)
	}
}

func startMultiCallServer(t *testing.T, harness multiCallHarness, node VirtualNode, name string, mode string) {
	process := invokeMultiCallOnNode(t, harness, node, "start_named", []term.Term{term.MustAtom(name), term.MustAtom(mode)})
	runMultiCallUntilSettled(t, harness.cluster, process)
	match process.State() { case VMProcessCompleted(_, _, _): case _: t.Fatalf("start %s on %s did not complete", name, node.Name) }
}

func invokeMultiCall(t *testing.T, harness multiCallHarness, function string, arguments []term.Term) *VMProcess { return invokeMultiCallOnNode(t, harness, harness.local, function, arguments) }

func invokeMultiCallOnNode(t *testing.T, harness multiCallHarness, node VirtualNode, function string, arguments []term.Term) *VMProcess {
	var process *VMProcess
	match harness.modules.Invoke("gen_server_multicall_callbacks", function, arguments, clock.Real{}, harness.registry) { case result.Err(failure): t.Fatal(failure); case result.Ok(created): process = created }
	match node.Runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
	return process
}

func runMultiCallUntilSettled(t *testing.T, cluster *VirtualCluster, process *VMProcess) {
	deadline := time.Now().Add(250 * time.Millisecond)
	for time.Now().Before(deadline) {
		cluster.Run(32, 1_000_000)
		match process.State() { case VMProcessWaiting(_, _), VMProcessSuspended(_, _): time.Sleep(time.Millisecond); case _: return }
	}
	t.Fatalf("multi_call process did not settle: %v", process.State())
}
