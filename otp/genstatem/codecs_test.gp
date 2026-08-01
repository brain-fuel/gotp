package genstatem

import (
    "testing"
    "testing/quick"

    "goforge.dev/goplus/std/nonempty"
    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/term"
)

func testPID() term.PID { return term.PID{Node: 1, Number: 7, Serial: 2, Creation: 3} }
func testReference(t *testing.T, seed uint32) term.Reference { t.Helper(); match term.ReferenceOf(1,2,nonempty.Of(seed)){case result.Err(f):t.Fatal(f);case result.Ok(v):return v};panic("unreachable") }

// assayxport:law gotp.otp.genstatem-type-codec-coverage
func TestEveryGenStatemTypeCodec(t *testing.T) {
    reference:=testReference(t,11); from:=From{To:testPID(),Tag:NewReplyTag(term.ReferenceValue(reference))}; reply:=ReplyAction{From:from,Reply:atom("done")}
    assertRoundTrip(t,"reply_tag",EncodeReplyTag(NewReplyTag(atom("tag"))),func(v term.Term)(term.Term,bool){match DecodeReplyTag(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeReplyTag(x),true}})
    assertRoundTrip(t,"request_id",EncodeRequestID(NewRequestID(reference)),func(v term.Term)(term.Term,bool){match DecodeRequestID(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeRequestID(x),true}})
    collection:=NewRequestIDCollection([]RequestIDEntry{{ID:NewRequestID(reference),Label:atom("label")}});match EncodeRequestIDCollection(collection){case result.Err(f):t.Fatal(f);case result.Ok(v):assertRoundTrip(t,"request_id_collection",v,func(x term.Term)(term.Term,bool){match DecodeRequestIDCollection(x){case result.Err(_):return nil,false;case result.Ok(decoded):match EncodeRequestIDCollection(decoded){case result.Err(_):return nil,false;case result.Ok(encoded):return encoded,true}}})}
    simple:=[]struct{name string; encoded term.Term; decode func(term.Term)(term.Term,bool)}{
        {"from",EncodeFrom(from),func(v term.Term)(term.Term,bool){match DecodeFrom(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeFrom(x),true}}},
        {"event_type",EncodeEventType(CallEvent(from)),func(v term.Term)(term.Term,bool){match DecodeEventType(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeEventType(x),true}}},
        {"callback_mode_result",EncodeCallbackMode(HandleEventFunction(true)),func(v term.Term)(term.Term,bool){match DecodeCallbackMode(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeCallbackMode(x),true}}},
        {"transition_option",EncodeTransitionOption(TimeoutTransition(Milliseconds(9))),func(v term.Term)(term.Term,bool){match DecodeTransitionOption(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeTransitionOption(x),true}}},
        {"reply_action",EncodeReplyAction(reply),func(v term.Term)(term.Term,bool){match DecodeReplyAction(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeReplyAction(x),true}}},
        {"enter_action",EncodeEnterAction(ReplyEnter(reply)),func(v term.Term)(term.Term,bool){match DecodeEnterAction(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeEnterAction(x),true}}},
        {"action",EncodeAction(NextEvent(InternalEvent(),atom("work"))),func(v term.Term)(term.Term,bool){match DecodeAction(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeAction(x),true}}},
        {"server_name",EncodeServerName(ViaName("registry",atom("worker"))),func(v term.Term)(term.Term,bool){match DecodeServerName(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeServerName(x),true}}},
        {"server_ref",EncodeServerRef(RemoteRef("worker","node@host")),func(v term.Term)(term.Term,bool){match DecodeServerRef(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeServerRef(x),true}}},
        {"enter_loop_opt",EncodeEnterLoopOpt(HibernateAfter(Milliseconds(50))),func(v term.Term)(term.Term,bool){match DecodeEnterLoopOpt(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeEnterLoopOpt(x),true}}},
        {"start_opt",EncodeStartOpt(SpawnOptions([]term.Term{atom("link")})),func(v term.Term)(term.Term,bool){match DecodeStartOpt(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeStartOpt(x),true}}},
        {"start_ret",EncodeStartRet(Started(testPID())),func(v term.Term)(term.Term,bool){match DecodeStartRet(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeStartRet(x),true}}},
        {"start_mon_ret",EncodeStartMonRet(StartedMonitored(testPID(),reference)),func(v term.Term)(term.Term,bool){match DecodeStartMonRet(v){case result.Err(_):return nil,false;case result.Ok(x):return EncodeStartMonRet(x),true}}},
    }
    for _,example:=range simple{assertRoundTrip(t,example.name,example.encoded,example.decode)}
    actions:=[]Action{Postpone(true),NextEvent(InternalEvent(),atom("next")),Enter(TimeoutEnter(StateTimeoutAfter(Milliseconds(5),atom("tick"),TimeoutOptions{Absolute:true})))}
    assertGenericResults(t,actions,reply)
    status:=FormatStatus{State:atom("idle"),Data:term.Integer(3),Reason:atom("normal"),Queue:[]StatusEvent{{Type:InternalEvent(),Content:atom("queued")}},Postponed:[]StatusEvent{{Type:CastEvent(),Content:atom("later")}},Timeouts:[]StatusTimeout{{Type:StateTimeout(),Content:atom("tick")}},Log:[]term.Term{atom("event")}}
    match EncodeFormatStatus(status){case result.Err(f):t.Fatal(f);case result.Ok(encoded):assertRoundTrip(t,"format_status",encoded,func(v term.Term)(term.Term,bool){match DecodeFormatStatus(v){case result.Err(_):return nil,false;case result.Ok(x):match EncodeFormatStatus(x){case result.Err(_):return nil,false;case result.Ok(out):return out,true}}})}
}

func assertGenericResults(t *testing.T, actions []Action, reply ReplyAction) {
    t.Helper()
    codec := TermCodec{}
    values := []EventHandlerResult[term.Term, term.Term]{
        EventNext(atom("next"), term.Integer(1), actions), EventKeep(term.Integer(2), actions),
        EventKeepData(actions), EventRepeat(term.Integer(3), actions), EventRepeatData(actions),
        EventStop(atom("normal")), EventStopWithData(atom("shutdown"), term.Integer(4)),
        EventStopAndReply(atom("done"), []ReplyAction{reply}),
        EventStopReplyData(atom("done"), []ReplyAction{reply}, term.Integer(5)),
    }
    for _, value := range values {
        match EncodeEventHandlerResult(value, codec, codec) {
        case result.Err(failure): t.Fatal(failure)
        case result.Ok(encoded):
            match DecodeEventHandlerResult(encoded, codec, codec) {
            case result.Err(failure): t.Fatal(failure)
            case result.Ok(decoded):
                match EncodeEventHandlerResult(decoded, codec, codec) {
                case result.Err(failure): t.Fatal(failure)
                case result.Ok(canonical): if !term.Equal(encoded, canonical) { t.Fatal("event result canonicalization differs") }
                }
            }
        }
    }
    initialized := InitOK[term.Term, term.Term](atom("idle"), term.Integer(0), actions)
    match EncodeInitResult(initialized, codec, codec) {
    case result.Err(failure): t.Fatal(failure)
    case result.Ok(encoded): match DecodeInitResult(encoded, codec, codec) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
    }
    enters := []EnterAction{HibernateEnter(true), ReplyEnter(reply), TimeoutEnter(EventTimeoutAfter(Milliseconds(1), atom("tick"), TimeoutOptions{}))}
    entered := EnterNext[term.Term, term.Term](atom("idle"), term.Integer(0), enters)
    match EncodeStateEnterResult(entered, codec, codec) {
    case result.Err(failure): t.Fatal(failure)
    case result.Ok(encoded): match DecodeStateEnterResult(encoded, codec, codec) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
    }
    stateFunction := StateFunctionResult[term.Term]{Result: EventNext[string, term.Term]("idle", term.Integer(0), actions)}
    match EncodeStateFunctionResult(stateFunction, codec) { case result.Err(failure): t.Fatal(failure); case result.Ok(encoded): match DecodeStateFunctionResult(encoded, codec) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): } }
    handled := HandleEventResult[term.Term, term.Term]{Result: EventKeep[term.Term, term.Term](term.Integer(0), actions)}
    match EncodeHandleEventResult(handled, codec, codec) { case result.Err(failure): t.Fatal(failure); case result.Ok(encoded): match DecodeHandleEventResult(encoded, codec, codec) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): } }
}

// assayxport:law gotp.otp.genstatem-canonical-round-trip
func TestGeneratedActionAndCallbackCanonicalization(t *testing.T) {
    codec := TermCodec{}
    law := func(raw []uint8) bool {
        actions := make([]Action, len(raw)%12)
        for index := range actions {
            choice := uint8(index)
            if len(raw) > 0 { choice = raw[index%len(raw)] }
            switch choice % 3 { case 0: actions[index] = Postpone(choice%2 == 0); case 1: actions[index] = NextEvent(InternalEvent(), term.Integer(int64(choice))); default: actions[index] = Enter(HibernateEnter(choice%2 == 0)) }
        }
        value := EventNext[term.Term, term.Term](atom("state"), term.List(), actions)
        match EncodeEventHandlerResult(value, codec, codec) {
        case result.Err(_): return false
        case result.Ok(first):
            match DecodeEventHandlerResult(first, codec, codec) {
            case result.Err(_): return false
            case result.Ok(decoded): match EncodeEventHandlerResult(decoded, codec, codec) { case result.Err(_): return false; case result.Ok(second): return term.Equal(first, second) }
            }
        }
    }
    match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 300})) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
}

func assertRoundTrip(t *testing.T,name string,encoded term.Term,decode func(term.Term)(term.Term,bool)){t.Helper();canonical,valid:=decode(encoded);if !valid{t.Fatalf("%s rejected encoded value",name)};if !term.Equal(encoded,canonical){t.Fatalf("%s canonical form = %v, want %v",name,canonical,encoded)}}

// assayxport:law gotp.otp.genstatem-invalid-wire-rejection
func TestInvalidWireTermsAreRejected(t *testing.T){invalid:=term.Tuple(atom("invalid"));checks:=[]func()bool{func()bool{match DecodeRequestID(invalid){case result.Err(_):return true;case result.Ok(_):return false}},func()bool{match DecodeEventType(invalid){case result.Err(_):return true;case result.Ok(_):return false}},func()bool{match DecodeAction(invalid){case result.Err(_):return true;case result.Ok(_):return false}},func()bool{match DecodeServerName(invalid){case result.Err(_):return true;case result.Ok(_):return false}},func()bool{match DecodeStartOpt(invalid){case result.Err(_):return true;case result.Ok(_):return false}},func()bool{match DecodeFormatStatus(invalid){case result.Err(_):return true;case result.Ok(_):return false}}};for index,check:=range checks{if !check(){t.Fatalf("invalid wire check %d accepted",index)}}}
