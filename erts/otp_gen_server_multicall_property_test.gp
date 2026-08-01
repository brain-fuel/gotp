package erts

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.gen-server-multi-call-classification-order
func TestGenServerMultiCallStatefulClassificationOrderLaw(t *testing.T) {
	base := newMultiCallHarness(t)
	law := func(control uint8, ordering []uint8) bool {
		harness := freshMultiCallHarness(t, base.modules, base.registry)
		firstServer := control&1 != 0; secondServer := control&2 != 0
		firstConnected := control&4 != 0; secondConnected := control&8 != 0
		if firstServer { startMultiCallServer(t, harness, harness.first, "multicall_property", "normal") }
		if secondServer { startMultiCallServer(t, harness, harness.second, "multicall_property", "normal") }
		if !firstConnected { harness.cluster.Disconnect(harness.local.ID, harness.first.ID) }
		if !secondConnected { harness.cluster.Disconnect(harness.local.ID, harness.second.ID) }
		count := int(control>>4) % 5
		targets := make([]term.Term, count)
		replies := []term.Term{}; bad := []term.Term{}
		for index := 0; index < count; index++ {
			chooseSecond := false
			if len(ordering) > 0 { chooseSecond = ordering[index%len(ordering)]&1 != 0 } else { chooseSecond = index&1 != 0 }
			role := "first"; node := "first@gotp"; available := firstServer && firstConnected
			if chooseSecond { role = "second"; node = "second@gotp"; available = secondServer && secondConnected }
			targets[index] = term.MustAtom(node)
			if available { replies = append(replies, term.Tuple(term.MustAtom(role), term.Tuple(term.MustAtom("served"), term.MustAtom(role)))) } else { bad = append(bad, term.MustAtom(role)) }
		}
		process := invokeMultiCall(t, harness, "property_multi_call", []term.Term{multiCallNodes(), term.List(targets...)})
		runMultiCallUntilSettled(t, harness.cluster, process)
		expected := term.Tuple(term.Tuple(term.List(replies...), term.List(bad...)), term.MustAtom("clean"))
		match process.State() { case VMProcessCompleted(value, _, _): return term.Equal(value, expected); case _: return false }
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 200})) {
	case result.Err(cause): t.Fatal(cause)
	case result.Ok(_):
	}
}

func freshMultiCallHarness(t *testing.T, modules *ModuleSet, registry *CallRegistry) multiCallHarness {
	cluster := NewVirtualCluster(); var local, first, second VirtualNode
	match cluster.AddNode("local@gotp", 1, 1) { case result.Err(failure): t.Fatal(failure); case result.Ok(node): local = node }
	match cluster.AddNode("first@gotp", 2, 1) { case result.Err(failure): t.Fatal(failure); case result.Ok(node): first = node }
	match cluster.AddNode("second@gotp", 3, 1) { case result.Err(failure): t.Fatal(failure); case result.Ok(node): second = node }
	return multiCallHarness{cluster: cluster, local: local, first: first, second: second, modules: modules, registry: registry}
}
