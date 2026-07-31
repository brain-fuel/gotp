package distribution

import (
	"sync"
	"testing"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

func mustControl(t *testing.T, code ControlCode, fields ...term.Term) Control {
	match NewControl(code, fields...) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(control): return control
	}
	panic("unreachable")
}

// assayxport:unit gotp.distribution.negotiated-control-laws
func TestNegotiatedFeaturesRejectUnadvertisedOperations(t *testing.T) {
	from, to, reference, _, _ := controlFixtureTerms()
	cases := []Control{
		mustControl(t, SendSenderCode(), from, to),
		mustControl(t, PayloadExitCode(), from, to),
		mustControl(t, AliasSendCode(), from, reference),
		mustControl(t, UnlinkIDCode(), term.Integer(1), from, to),
	}
	for _, control := range cases {
		match NewNegotiatedPolicy(0).Accept(control) {
		case result.Err(_):
		case result.Ok(_): t.Fatalf("unadvertised opcode %d was accepted", controlNumber(control.Code()))
		}
	}
}

func TestSenderTransitionForbidsDowngrade(t *testing.T) {
	from, to, _, token, _ := controlFixtureTerms()
	policy := NewNegotiatedPolicy(DFlagSendSender)
	modern := mustControl(t, SendSenderCode(), from, to)
	legacy := mustControl(t, SendTraceCode(), term.List(), to, token)
	match policy.Accept(modern) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(_):
	}
	match policy.Accept(legacy) {
	case result.Err(_):
	case result.Ok(_): t.Fatal("legacy sender mode resumed")
	}
}

func TestPayloadExitTransitionForbidsEveryEmbeddedVariant(t *testing.T) {
	from, to, reference, _, reason := controlFixtureTerms()
	policy := NewNegotiatedPolicy(DFlagExitPayload)
	modern := mustControl(t, PayloadMonitorExitCode(), from, to, reference)
	legacy := []Control{
		mustControl(t, ExitCode(), from, to, reason),
		mustControl(t, Exit2Code(), from, to, reason),
		mustControl(t, MonitorExitCode(), from, to, reference, reason),
	}
	match policy.Accept(modern) {
	case result.Err(failure): t.Fatal(failure.Error())
	case result.Ok(_):
	}
	for _, control := range legacy {
		match policy.Accept(control) {
		case result.Err(_):
		case result.Ok(_): t.Fatalf("embedded opcode %d resumed", controlNumber(control.Code()))
		}
	}
}

func TestNegotiatedPolicySerializesFirstModernTransition(t *testing.T) {
	from, to, _, _, _ := controlFixtureTerms()
	policy := NewNegotiatedPolicy(DFlagSendSender)
	modern := mustControl(t, SendSenderCode(), from, to)
	legacy := mustControl(t, SendCode(), term.List(), to)
	var wait sync.WaitGroup
	wait.Add(2)
	results := make(chan bool, 2)
	go func() { defer wait.Done(); match policy.Accept(modern) { case result.Ok(_): results <- true; case result.Err(_): results <- false } }()
	go func() { defer wait.Done(); match policy.Accept(legacy) { case result.Ok(_): results <- true; case result.Err(_): results <- false } }()
	wait.Wait()
	close(results)
	accepted := 0
	for value := range results { if value { accepted++ } }
	if accepted < 1 || accepted > 2 { t.Fatalf("accepted = %d", accepted) }
	match policy.Accept(legacy) {
	case result.Err(_):
	case result.Ok(_): t.Fatal("legacy operation accepted after completed transition")
	}
}
