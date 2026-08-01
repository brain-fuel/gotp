package erts

import (
    "os"
    "strings"
    "testing"

    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/otp/genstatem"
    "goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.otp29-gen-statem-static-types
func TestPinnedOTPGenStatemTypeAcceptanceCorpus(t *testing.T) {
    payload, cause := os.ReadFile("testdata/otp-29.0.4-gen_statem-types.corpus")
    if cause != nil { t.Fatal(cause) }
    for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
        fields := strings.Split(line, "|")
        if len(fields) != 3 || fields[0] != "case" { t.Fatalf("line %d malformed", lineNumber+1) }
        encoded := decodeGenServerCorpusTerm(t, fields[2])
        var record []term.Term
        match encoded { case term.TupleTerm(outcome): if len(outcome)!=2 || !genStatemTypeAtom(outcome[0],"ok") { t.Fatalf("line %d outcome differs",lineNumber+1) }; match outcome[1] { case term.TupleTerm(found): record=found; case _: t.Fatalf("line %d record differs",lineNumber+1) }; case _: t.Fatalf("line %d envelope differs",lineNumber+1) }
        if len(record)!=4 { t.Fatalf("line %d record arity differs",lineNumber+1) }
        kind := genStatemTypeAtomName(t, record[0]); expected := genStatemTypeAtom(record[3],"accepted")
        actual := typedGenStatemAccepts(kind,record[2])
        if actual != expected { t.Fatalf("%s: typed acceptance = %v, OTP = %v",fields[1],actual,expected) }
    }
}

func typedGenStatemAccepts(kind string,value term.Term) bool {
    codec:=genstatem.TermCodec{}
    switch kind {
    case "init_result": match genstatem.DecodeInitResult(value,codec,codec){case result.Ok(_):return true;case result.Err(_):return false}
    case "callback_mode_result": match genstatem.DecodeCallbackMode(value){case result.Ok(_):return true;case result.Err(_):return false}
    case "action": match genstatem.DecodeAction(value){case result.Ok(_):return true;case result.Err(_):return false}
    case "event_type": match genstatem.DecodeEventType(value){case result.Ok(_):return true;case result.Err(_):return false}
    case "event_handler_result": match genstatem.DecodeEventHandlerResult(value,codec,codec){case result.Ok(_):return true;case result.Err(_):return false}
    case "state_enter_result": match genstatem.DecodeStateEnterResult(value,codec,codec){case result.Ok(_):return true;case result.Err(_):return false}
    case "start_opt": match genstatem.DecodeStartOpt(value){case result.Ok(_):return true;case result.Err(_):return false}
    case "server_name": match genstatem.DecodeServerName(value){case result.Ok(_):return true;case result.Err(_):return false}
    }
    return false
}

// assayxport:law gotp.erts.gen-statem-types-integrate-runtime-slices
func TestTypedGenStatemValuesIntegrateRuntimeSlices(t *testing.T) {
    requestProcess:=invokeGenStatemFixture(t,pinnedGenStatemAsyncModules(t),"gen_statem","reqids_new",nil)
    match requestProcess.State(){case VMProcessCompleted(value,_,_):match genstatem.DecodeRequestIDCollection(value){case result.Err(failure):t.Fatal(failure);case result.Ok(_):};case _:t.Fatal("reqids_new did not complete")}
    status:=genstatem.FormatStatus{State:term.MustAtom("idle"),Data:term.Tuple(term.MustAtom("secret"),term.Binary([]byte("token"))),Reason:term.MustAtom("normal"),Queue:[]genstatem.StatusEvent{},Postponed:[]genstatem.StatusEvent{},Timeouts:[]genstatem.StatusTimeout{},Log:[]term.Term{}}
    var encoded term.Term
    match genstatem.EncodeFormatStatus(status){case result.Err(failure):t.Fatal(failure);case result.Ok(value):encoded=value}
    modules:=pinnedGenStatemFormatModules(t)
    for _,mode:=range []string{"state_functions","handle_event"}{process:=invokeGenStatemFixture(t,modules,"gen_statem_format_"+mode+"_callbacks","format_status",[]term.Term{encoded});match process.State(){case VMProcessCompleted(value,_,_):match genstatem.DecodeFormatStatus(value){case result.Err(failure):t.Fatalf("%s: %v",mode,failure);case result.Ok(decoded):if !genStatemTypeAtom(decoded.Data,"redacted"){t.Fatalf("%s did not redact data",mode)}};case _:t.Fatalf("%s status did not complete",mode)}}
}

func genStatemTypeAtom(value term.Term,wanted string)bool{match value{case term.AtomTerm(name):return name==wanted;case _:return false}}
func genStatemTypeAtomName(t *testing.T,value term.Term)string{t.Helper();match value{case term.AtomTerm(name):return name;case _:t.Fatal("expected atom")};return ""}
