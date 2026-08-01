package genstatem

import (
    "fmt"

    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/term"
)

func ok[T any](value T) result.Result[T, Failure] { return result.Ok[T, Failure](value) }
func bad[T any](path, detail string) result.Result[T, Failure] { return result.Err[T, Failure](Invalid(path, detail)) }

func EncodeReplyTag(value ReplyTag) term.Term { return value.Term() }
func DecodeReplyTag(value term.Term) result.Result[ReplyTag, Failure] { return ok(NewReplyTag(value)) }

func EncodeRequestID(value RequestID) term.Term { return term.ReferenceValue(value.Reference()) }
func DecodeRequestID(value term.Term) result.Result[RequestID, Failure] {
    match value { case term.ReferenceTerm(reference): return ok(NewRequestID(reference)); case _: return bad[RequestID]("request_id", "expected reference") }
}

func EncodeRequestIDCollection(value RequestIDCollection) result.Result[term.Term, Failure] {
    entries := value.Entries(); encoded := make([]term.MapEntry, len(entries))
    for index, entry := range entries { encoded[index] = term.MapEntry{Key: EncodeRequestID(entry.ID), Value: entry.Label.Clone()} }
    match term.Map(encoded) { case result.Err(_): return bad[term.Term]("request_id_collection", "duplicate request id"); case result.Ok(found): return ok(found) }
}
func DecodeRequestIDCollection(value term.Term) result.Result[RequestIDCollection, Failure] {
    match value {
    case term.MapTerm(entries):
        decoded := make([]RequestIDEntry, len(entries))
        for index, entry := range entries { match DecodeRequestID(entry.Key) { case result.Err(failure): return result.Err[RequestIDCollection, Failure](failure); case result.Ok(id): decoded[index] = RequestIDEntry{ID: id, Label: entry.Value.Clone()} } }
        return ok(NewRequestIDCollection(decoded))
    case _: return bad[RequestIDCollection]("request_id_collection", "expected map")
    }
}

func EncodeFrom(value From) term.Term { return term.Tuple(term.PIDValue(value.To), EncodeReplyTag(value.Tag)) }
func DecodeFrom(value term.Term) result.Result[From, Failure] {
    match pair(value) { case result.Err(_): return bad[From]("from", "expected {pid, reply_tag}"); case result.Ok(parts):
        match parts[0] { case term.PIDTerm(pid): return ok(From{To: pid, Tag: NewReplyTag(parts[1])}); case _: return bad[From]("from.to", "expected pid") }
    }
}

func EncodeEventType(value EventType) term.Term {
    match value {
    case CallEvent(from): return term.Tuple(atom("call"), EncodeFrom(from))
    case CastEvent: return atom("cast")
    case InfoEvent: return atom("info")
    case InternalEvent: return atom("internal")
    case EventTimeout: return atom("timeout")
    case NamedTimeout(name): return term.Tuple(atom("timeout"), name)
    case StateTimeout: return atom("state_timeout")
    }
}
func DecodeEventType(value term.Term) result.Result[EventType, Failure] {
    match value {
    case term.AtomTerm(name): switch name { case "cast": return ok[EventType](CastEvent()); case "info": return ok[EventType](InfoEvent()); case "internal": return ok[EventType](InternalEvent()); case "timeout": return ok[EventType](EventTimeout()); case "state_timeout": return ok[EventType](StateTimeout()) }
    case term.TupleTerm(parts):
        if len(parts)==2 { match parts[0] { case term.AtomTerm(name): if name=="call" { match DecodeFrom(parts[1]) { case result.Err(failure): return result.Err[EventType,Failure](failure); case result.Ok(from): return ok[EventType](CallEvent(from)) } }; if name=="timeout" { return ok[EventType](NamedTimeout(parts[1].Clone())) }; case _: } }
    case _: }
    return bad[EventType]("event_type", "unknown event type")
}

func EncodeCallbackMode(value CallbackModeResult) term.Term {
    match value { case StateFunctions(stateEnter): if stateEnter { return term.List(atom("state_functions"),atom("state_enter")) }; return atom("state_functions"); case HandleEventFunction(stateEnter): if stateEnter { return term.List(atom("handle_event_function"),atom("state_enter")) }; return atom("handle_event_function") }
}
func DecodeCallbackMode(value term.Term) result.Result[CallbackModeResult, Failure] {
    match value { case term.AtomTerm(name): switch name { case "state_functions": return ok[CallbackModeResult](StateFunctions(false)); case "handle_event_function": return ok[CallbackModeResult](HandleEventFunction(false)) }; case term.ProperListTerm(parts): if len(parts)==2 && isAtom(parts[1],"state_enter") { if isAtom(parts[0],"state_functions") { return ok[CallbackModeResult](StateFunctions(true)) }; if isAtom(parts[0],"handle_event_function") { return ok[CallbackModeResult](HandleEventFunction(true)) } }; case _: }
    return bad[CallbackModeResult]("callback_mode_result", "expected callback mode with optional state_enter")
}

func EncodeTimeout(value Timeout) term.Term { match value { case Infinity: return atom("infinity"); case Milliseconds(milliseconds): return term.Integer(milliseconds) } }
func DecodeTimeout(value term.Term) result.Result[Timeout, Failure] {
    match value { case term.AtomTerm(name): if name=="infinity" { return ok[Timeout](Infinity()) }; case term.IntegerTerm(integer): if integer.IsInt64() { return ok[Timeout](Milliseconds(integer.Int64())) }; case _: }
    return bad[Timeout]("timeout", "expected infinity or int64")
}
func timeoutOptions(options TimeoutOptions) term.Term { if options.Absolute { return term.List(term.Tuple(atom("abs"),atom("true"))) }; return term.List() }

func EncodeReplyAction(value ReplyAction) term.Term { return term.Tuple(atom("reply"), EncodeFrom(value.From), value.Reply) }
func DecodeReplyAction(value term.Term) result.Result[ReplyAction, Failure] {
    match tuple(value,3) { case result.Err(_): return bad[ReplyAction]("reply_action", "expected {reply, from, reply}"); case result.Ok(parts): if !isAtom(parts[0],"reply") { return bad[ReplyAction]("reply_action", "missing reply tag") }; match DecodeFrom(parts[1]) { case result.Err(failure): return result.Err[ReplyAction,Failure](failure); case result.Ok(from): return ok(ReplyAction{From:from,Reply:parts[2].Clone()}) } }
}

func EncodeTimeoutAction(value TimeoutAction) term.Term {
    match value {
    case EventTimeoutAfter(time, content, options): return timeoutAfter(atom("timeout"),time,content,options)
    case NamedTimeoutAfter(name,time,content,options): return timeoutAfter(term.Tuple(atom("timeout"),name),time,content,options)
    case StateTimeoutAfter(time,content,options): return timeoutAfter(atom("state_timeout"),time,content,options)
    case CancelEventTimeout: return term.Tuple(atom("timeout"),atom("cancel"))
    case CancelNamedTimeout(name): return term.Tuple(term.Tuple(atom("timeout"),name),atom("cancel"))
    case CancelStateTimeout: return term.Tuple(atom("state_timeout"),atom("cancel"))
    case UpdateEventTimeout(content): return term.Tuple(atom("timeout"),atom("update"),content)
    case UpdateNamedTimeout(name,content): return term.Tuple(term.Tuple(atom("timeout"),name),atom("update"),content)
    case UpdateStateTimeout(content): return term.Tuple(atom("state_timeout"),atom("update"),content)
    }
}
func timeoutAfter(kind term.Term,time Timeout,content term.Term,options TimeoutOptions) term.Term { if options.Absolute { return term.Tuple(kind,EncodeTimeout(time),content,timeoutOptions(options)) }; return term.Tuple(kind,EncodeTimeout(time),content) }

func DecodeTimeoutAction(value term.Term) result.Result[TimeoutAction, Failure] {
    match value {
    case term.TupleTerm(parts):
        if len(parts)==2 && isAtom(parts[1],"cancel") { match timeoutKind(parts[0]) { case result.Err(failure): return result.Err[TimeoutAction,Failure](failure); case result.Ok(kind): return cancelTimeout(kind) } }
        if len(parts)==3 && isAtom(parts[1],"update") { match timeoutKind(parts[0]) { case result.Err(failure): return result.Err[TimeoutAction,Failure](failure); case result.Ok(kind): return updateTimeout(kind,parts[2]) } }
        if len(parts)==3 || len(parts)==4 { match timeoutKind(parts[0]) { case result.Err(failure): return result.Err[TimeoutAction,Failure](failure); case result.Ok(kind): match DecodeTimeout(parts[1]) { case result.Err(failure): return result.Err[TimeoutAction,Failure](failure); case result.Ok(time): options:=TimeoutOptions{}; if len(parts)==4 { match decodeTimeoutOptions(parts[3]) { case result.Err(failure): return result.Err[TimeoutAction,Failure](failure); case result.Ok(found): options=found } }; return afterTimeout(kind,time,parts[2],options) } } }
    case term.IntegerTerm(_), term.AtomTerm(_): match DecodeTimeout(value) { case result.Err(failure): return result.Err[TimeoutAction,Failure](failure); case result.Ok(time): return ok[TimeoutAction](EventTimeoutAfter(time,atom("timeout"),TimeoutOptions{})) }
    case _: }
    return bad[TimeoutAction]("timeout_action", "invalid timeout action")
}

type timeoutKindValue enum { eventKind(); namedKind(Name term.Term); stateKind() }
func timeoutKind(value term.Term) result.Result[timeoutKindValue,Failure] { if isAtom(value,"timeout") { return ok[timeoutKindValue](eventKind()) }; if isAtom(value,"state_timeout") { return ok[timeoutKindValue](stateKind()) }; match value { case term.TupleTerm(parts): if len(parts)==2 && isAtom(parts[0],"timeout") { return ok[timeoutKindValue](namedKind(parts[1].Clone())) }; case _: }; return bad[timeoutKindValue]("timeout_action.kind","invalid timeout kind") }
func cancelTimeout(kind timeoutKindValue) result.Result[TimeoutAction,Failure] { match kind { case eventKind: return ok[TimeoutAction](CancelEventTimeout()); case namedKind(name): return ok[TimeoutAction](CancelNamedTimeout(name)); case stateKind: return ok[TimeoutAction](CancelStateTimeout()) } }
func updateTimeout(kind timeoutKindValue,content term.Term) result.Result[TimeoutAction,Failure] { match kind { case eventKind: return ok[TimeoutAction](UpdateEventTimeout(content.Clone())); case namedKind(name): return ok[TimeoutAction](UpdateNamedTimeout(name,content.Clone())); case stateKind: return ok[TimeoutAction](UpdateStateTimeout(content.Clone())) } }
func afterTimeout(kind timeoutKindValue,time Timeout,content term.Term,options TimeoutOptions) result.Result[TimeoutAction,Failure] { match kind { case eventKind: return ok[TimeoutAction](EventTimeoutAfter(time,content.Clone(),options)); case namedKind(name): return ok[TimeoutAction](NamedTimeoutAfter(name,time,content.Clone(),options)); case stateKind: return ok[TimeoutAction](StateTimeoutAfter(time,content.Clone(),options)) } }
func decodeTimeoutOptions(value term.Term) result.Result[TimeoutOptions,Failure] { match value { case term.TupleTerm(parts): if len(parts)==2 && isAtom(parts[0],"abs") { return boolAtom(parts[1],"timeout_action.options.abs") }; case term.ProperListTerm(parts): if len(parts)==1 { return decodeTimeoutOptions(parts[0]) }; case _: }; return bad[TimeoutOptions]("timeout_action.options","expected {abs, boolean} or singleton list") }

func EncodeEnterAction(value EnterAction) term.Term { match value { case HibernateEnter(enabled): if enabled { return atom("hibernate") }; return term.Tuple(atom("hibernate"),atom("false")); case TimeoutEnter(timeout): return EncodeTimeoutAction(timeout); case ReplyEnter(reply): return EncodeReplyAction(reply) } }
func DecodeEnterAction(value term.Term) result.Result[EnterAction,Failure] { if isAtom(value,"hibernate") { return ok[EnterAction](HibernateEnter(true)) }; match value { case term.TupleTerm(parts): if len(parts)==2 && isAtom(parts[0],"hibernate") { match boolAtom(parts[1],"enter_action.hibernate") { case result.Err(failure): return result.Err[EnterAction,Failure](failure); case result.Ok(enabled): return ok[EnterAction](HibernateEnter(enabled.Absolute)) } }; case _: }; match DecodeReplyAction(value) { case result.Ok(reply): return ok[EnterAction](ReplyEnter(reply)); case result.Err(_): }; match DecodeTimeoutAction(value) { case result.Ok(timeout): return ok[EnterAction](TimeoutEnter(timeout)); case result.Err(_): return bad[EnterAction]("enter_action","unknown enter action") } }

func EncodeAction(value Action) term.Term { match value { case Postpone(enabled): if enabled { return atom("postpone") }; return term.Tuple(atom("postpone"),atom("false")); case NextEvent(kind,content): return term.Tuple(atom("next_event"),EncodeEventType(kind),content); case ChangeCallbackModule(module): return term.Tuple(atom("change_callback_module"),atom(module)); case PushCallbackModule(module): return term.Tuple(atom("push_callback_module"),atom(module)); case PopCallbackModule: return atom("pop_callback_module"); case Enter(enter): return EncodeEnterAction(enter) } }
func DecodeAction(value term.Term) result.Result[Action,Failure] {
    if isAtom(value,"postpone") { return ok[Action](Postpone(true)) }; if isAtom(value,"pop_callback_module") { return ok[Action](PopCallbackModule()) }
    match value { case term.TupleTerm(parts):
        if len(parts)==2 && isAtom(parts[0],"postpone") { match boolAtom(parts[1],"action.postpone") { case result.Err(failure): return result.Err[Action,Failure](failure); case result.Ok(enabled): return ok[Action](Postpone(enabled.Absolute)) } }
        if len(parts)==2 && (isAtom(parts[0],"change_callback_module")||isAtom(parts[0],"push_callback_module")) { match parts[1] { case term.AtomTerm(module): if module=="" { return bad[Action]("action.module","empty module") }; if isAtom(parts[0],"change_callback_module") { return ok[Action](ChangeCallbackModule(module)) }; return ok[Action](PushCallbackModule(module)); case _: return bad[Action]("action.module","expected atom") } }
        if len(parts)==3 && isAtom(parts[0],"next_event") { match DecodeEventType(parts[1]) { case result.Err(failure): return result.Err[Action,Failure](failure); case result.Ok(kind): return ok[Action](NextEvent(kind,parts[2].Clone())) } }
    case _: }
    match DecodeEnterAction(value) { case result.Ok(enter): return ok[Action](Enter(enter)); case result.Err(_): return bad[Action]("action","unknown action") }
}

func EncodeTransitionOption(value TransitionOption) term.Term { match value { case BooleanTransition(enabled): if enabled{return atom("true")};return atom("false"); case TimeoutTransition(time): return EncodeTimeout(time) } }
func DecodeTransitionOption(value term.Term) result.Result[TransitionOption,Failure] { match value { case term.AtomTerm(name): if name=="true"{return ok[TransitionOption](BooleanTransition(true))};if name=="false"{return ok[TransitionOption](BooleanTransition(false))};case _:};match DecodeTimeout(value){case result.Ok(time):return ok[TransitionOption](TimeoutTransition(time));case result.Err(_):return bad[TransitionOption]("transition_option","expected boolean or timeout")} }

func EncodeServerName(value ServerName) term.Term { match value { case LocalName(name): return term.Tuple(atom("local"),atom(name)); case GlobalName(name): return term.Tuple(atom("global"),name); case ViaName(module,name): return term.Tuple(atom("via"),atom(module),name) } }
func DecodeServerName(value term.Term) result.Result[ServerName,Failure] { match value { case term.TupleTerm(parts): if len(parts)==2 && isAtom(parts[0],"local") { match parts[1] { case term.AtomTerm(name): return ok[ServerName](LocalName(name)); case _: } }; if len(parts)==2 && isAtom(parts[0],"global") { return ok[ServerName](GlobalName(parts[1].Clone())) }; if len(parts)==3 && isAtom(parts[0],"via") { match parts[1] { case term.AtomTerm(module): return ok[ServerName](ViaName(module,parts[2].Clone())); case _: } }; case _: }; return bad[ServerName]("server_name","invalid server name") }

func EncodeServerRef(value ServerRef) term.Term { match value { case ServerPID(pid): return term.PIDValue(pid); case LocalRef(name): return atom(name); case RemoteRef(name,node): return term.Tuple(atom(name),atom(node)); case GlobalRef(name): return term.Tuple(atom("global"),name); case ViaRef(module,name): return term.Tuple(atom("via"),atom(module),name) } }
func DecodeServerRef(value term.Term) result.Result[ServerRef,Failure] { match value { case term.PIDTerm(pid): return ok[ServerRef](ServerPID(pid)); case term.AtomTerm(name): return ok[ServerRef](LocalRef(name)); case term.TupleTerm(parts): if len(parts)==2 && isAtom(parts[0],"global") { return ok[ServerRef](GlobalRef(parts[1].Clone())) }; if len(parts)==2 { match parts[0] { case term.AtomTerm(name): match parts[1] { case term.AtomTerm(node): return ok[ServerRef](RemoteRef(name,node)); case _: }; case _: } }; if len(parts)==3 && isAtom(parts[0],"via") { match parts[1] { case term.AtomTerm(module): return ok[ServerRef](ViaRef(module,parts[2].Clone())); case _: } }; case _: }; return bad[ServerRef]("server_ref","invalid server reference") }

func EncodeEnterLoopOpt(value EnterLoopOpt) term.Term { match value { case HibernateAfter(time): return term.Tuple(atom("hibernate_after"),EncodeTimeout(time)); case Debug(options): return term.Tuple(atom("debug"),term.List(options...)) } }
func DecodeEnterLoopOpt(value term.Term) result.Result[EnterLoopOpt,Failure] { match pair(value) { case result.Err(_): return bad[EnterLoopOpt]("enter_loop_opt","expected pair"); case result.Ok(parts): if isAtom(parts[0],"hibernate_after") { match DecodeTimeout(parts[1]) { case result.Err(failure): return result.Err[EnterLoopOpt,Failure](failure); case result.Ok(time): return ok[EnterLoopOpt](HibernateAfter(time)) } }; if isAtom(parts[0],"debug") { match parts[1] { case term.ProperListTerm(options): return ok[EnterLoopOpt](Debug(clone(options))); case _: } } }; return bad[EnterLoopOpt]("enter_loop_opt","unknown option") }

func EncodeStartOpt(value StartOpt) term.Term { match value { case StartTimeout(time): return term.Tuple(atom("timeout"),EncodeTimeout(time)); case SpawnOptions(options): return term.Tuple(atom("spawn_opt"),term.List(options...)); case EnterLoopOption(option): return EncodeEnterLoopOpt(option) } }
func DecodeStartOpt(value term.Term) result.Result[StartOpt,Failure] { match pair(value) { case result.Ok(parts): if isAtom(parts[0],"timeout") { match DecodeTimeout(parts[1]) { case result.Err(failure): return result.Err[StartOpt,Failure](failure); case result.Ok(time): return ok[StartOpt](StartTimeout(time)) } }; if isAtom(parts[0],"spawn_opt") { match parts[1] { case term.ProperListTerm(options): return ok[StartOpt](SpawnOptions(clone(options))); case _: return bad[StartOpt]("start_opt.spawn_opt","expected list") } }; case result.Err(_): }; match DecodeEnterLoopOpt(value) { case result.Ok(option): return ok[StartOpt](EnterLoopOption(option)); case result.Err(_): return bad[StartOpt]("start_opt","unknown option") } }

func EncodeStartRet(value StartRet) term.Term { match value { case Started(pid): return term.Tuple(atom("ok"),term.PIDValue(pid)); case StartIgnored: return atom("ignore"); case StartFailed(reason): return term.Tuple(atom("error"),reason) } }
func DecodeStartRet(value term.Term) result.Result[StartRet,Failure] { if isAtom(value,"ignore") { return ok[StartRet](StartIgnored()) }; match pair(value) { case result.Ok(parts): if isAtom(parts[0],"ok") { match parts[1] { case term.PIDTerm(pid): return ok[StartRet](Started(pid)); case _: } }; if isAtom(parts[0],"error") { return ok[StartRet](StartFailed(parts[1].Clone())) }; case result.Err(_): }; return bad[StartRet]("start_ret","invalid start result") }

func EncodeStartMonRet(value StartMonRet) term.Term { match value { case StartedMonitored(pid,reference): return term.Tuple(atom("ok"),term.Tuple(term.PIDValue(pid),term.ReferenceValue(reference))); case StartMonitorIgnored: return atom("ignore"); case StartMonitorFailed(reason): return term.Tuple(atom("error"),reason) } }
func DecodeStartMonRet(value term.Term) result.Result[StartMonRet,Failure] { if isAtom(value,"ignore") { return ok[StartMonRet](StartMonitorIgnored()) }; match pair(value) { case result.Ok(parts): if isAtom(parts[0],"error") { return ok[StartMonRet](StartMonitorFailed(parts[1].Clone())) }; if isAtom(parts[0],"ok") { match pair(parts[1]) { case result.Ok(inner): match inner[0] { case term.PIDTerm(pid): match inner[1] { case term.ReferenceTerm(reference): return ok[StartMonRet](StartedMonitored(pid,reference)); case _: }; case _: }; case result.Err(_): } }; case result.Err(_): }; return bad[StartMonRet]("start_mon_ret","invalid monitored start result") }

type codecPair[S,D any] struct { State S; Data D }
func encodeCodecPair[S,D any](state Codec[S],stateValue S,data Codec[D],dataValue D) result.Result[[]term.Term,Failure] { match state.Encode(stateValue){case result.Err(failure):return result.Err[[]term.Term,Failure](failure);case result.Ok(encodedState):match data.Encode(dataValue){case result.Err(failure):return result.Err[[]term.Term,Failure](failure);case result.Ok(encodedData):return ok([]term.Term{encodedState,encodedData})}} }
func decodeCodecPair[S,D any](state Codec[S],stateValue term.Term,data Codec[D],dataValue term.Term) result.Result[codecPair[S,D],Failure] { match state.Decode(stateValue){case result.Err(failure):return result.Err[codecPair[S,D],Failure](failure);case result.Ok(decodedState):match data.Decode(dataValue){case result.Err(failure):return result.Err[codecPair[S,D],Failure](failure);case result.Ok(decodedData):return ok(codecPair[S,D]{State:decodedState,Data:decodedData})}} }

func EncodeInitResult[S,D any](value InitResult[S,D], state Codec[S], data Codec[D]) result.Result[term.Term,Failure] {
    match value {
    case InitOK(stateValue,dataValue,actions): match encodeCodecPair(state,stateValue,data,dataValue){case result.Err(failure):return result.Err[term.Term,Failure](failure);case result.Ok(encoded):if len(actions)==0{return ok(term.Tuple(atom("ok"),encoded[0],encoded[1]))};return ok(term.Tuple(atom("ok"),encoded[0],encoded[1],encodeActions(actions)))}
    case InitIgnore: return ok(atom("ignore"))
    case InitStop(reason): return ok(term.Tuple(atom("stop"),reason))
    case InitError(reason): return ok(term.Tuple(atom("error"),reason))
    }
}
func DecodeInitResult[S,D any](value term.Term,state Codec[S],data Codec[D]) result.Result[InitResult[S,D],Failure] {
    if isAtom(value,"ignore"){return ok[InitResult[S,D]](InitIgnore())}
    match value { case term.TupleTerm(parts):
        if len(parts)==2&&isAtom(parts[0],"stop"){return ok[InitResult[S,D]](InitStop(parts[1].Clone()))}
        if len(parts)==2&&isAtom(parts[0],"error"){return ok[InitResult[S,D]](InitError(parts[1].Clone()))}
        if (len(parts)==3||len(parts)==4)&&isAtom(parts[0],"ok"){match decodeCodecPair(state,parts[1],data,parts[2]){case result.Err(failure):return result.Err[InitResult[S,D],Failure](failure);case result.Ok(decoded):actions:=[]Action{};if len(parts)==4{match decodeActions(parts[3]){case result.Err(failure):return result.Err[InitResult[S,D],Failure](failure);case result.Ok(found):actions=found}};return ok[InitResult[S,D]](InitOK(decoded.State,decoded.Data,actions))}}
    case _: }
    return bad[InitResult[S,D]]("init_result","invalid callback result")
}

func EncodeEventHandlerResult[S,D any](value EventHandlerResult[S,D],state Codec[S],data Codec[D]) result.Result[term.Term,Failure] { match value {
case EventNext(s,d,a):match encodeCodecPair(state,s,data,d){case result.Err(f):return result.Err[term.Term,Failure](f);case result.Ok(v):return callbackTuple("next_state",v[0],v[1],encodeActions(a),len(a)>0)}
case EventKeep(d,a):match data.Encode(d){case result.Err(f):return result.Err[term.Term,Failure](f);case result.Ok(v):return callbackDataTuple("keep_state",v,encodeActions(a),len(a)>0)}
case EventKeepData(a):return callbackAtomTuple("keep_state_and_data",encodeActions(a),len(a)>0)
case EventRepeat(d,a):match data.Encode(d){case result.Err(f):return result.Err[term.Term,Failure](f);case result.Ok(v):return callbackDataTuple("repeat_state",v,encodeActions(a),len(a)>0)}
case EventRepeatData(a):return callbackAtomTuple("repeat_state_and_data",encodeActions(a),len(a)>0)
case EventStop(reason):return ok(term.Tuple(atom("stop"),reason))
case EventStopWithData(reason,d):match data.Encode(d){case result.Err(f):return result.Err[term.Term,Failure](f);case result.Ok(v):return ok(term.Tuple(atom("stop"),reason,v))}
case EventStopAndReply(reason,replies):return ok(term.Tuple(atom("stop_and_reply"),reason,encodeReplies(replies)))
case EventStopReplyData(reason,replies,d):match data.Encode(d){case result.Err(f):return result.Err[term.Term,Failure](f);case result.Ok(v):return ok(term.Tuple(atom("stop_and_reply"),reason,encodeReplies(replies),v))}
} }

func DecodeEventHandlerResult[S,D any](value term.Term,state Codec[S],data Codec[D]) result.Result[EventHandlerResult[S,D],Failure] { match value { case term.AtomTerm(name): switch name { case "keep_state_and_data":return ok[EventHandlerResult[S,D]](EventKeepData(nil));case "repeat_state_and_data":return ok[EventHandlerResult[S,D]](EventRepeatData(nil));case "stop":return ok[EventHandlerResult[S,D]](EventStop(atom("normal"))) }; case term.TupleTerm(parts):
        if (len(parts)==3||len(parts)==4)&&isAtom(parts[0],"next_state"){match decodeCodecPair(state,parts[1],data,parts[2]){case result.Err(f):return result.Err[EventHandlerResult[S,D],Failure](f);case result.Ok(decoded):a:=[]Action{};if len(parts)==4{match decodeActions(parts[3]){case result.Err(f):return result.Err[EventHandlerResult[S,D],Failure](f);case result.Ok(v):a=v}};return ok[EventHandlerResult[S,D]](EventNext(decoded.State,decoded.Data,a))}}
        if (len(parts)==2||len(parts)==3)&&(isAtom(parts[0],"keep_state")||isAtom(parts[0],"repeat_state")){match data.Decode(parts[1]){case result.Err(f):return result.Err[EventHandlerResult[S,D],Failure](f);case result.Ok(d):a:=[]Action{};if len(parts)==3{match decodeActions(parts[2]){case result.Err(f):return result.Err[EventHandlerResult[S,D],Failure](f);case result.Ok(v):a=v}};if isAtom(parts[0],"keep_state"){return ok[EventHandlerResult[S,D]](EventKeep(d,a))};return ok[EventHandlerResult[S,D]](EventRepeat(d,a))}}
        if len(parts)==2&&(isAtom(parts[0],"keep_state_and_data")||isAtom(parts[0],"repeat_state_and_data")){match decodeActions(parts[1]){case result.Err(f):return result.Err[EventHandlerResult[S,D],Failure](f);case result.Ok(a):if isAtom(parts[0],"keep_state_and_data"){return ok[EventHandlerResult[S,D]](EventKeepData(a))};return ok[EventHandlerResult[S,D]](EventRepeatData(a))}}
        if len(parts)==2&&isAtom(parts[0],"stop"){return ok[EventHandlerResult[S,D]](EventStop(parts[1].Clone()))};if len(parts)==3&&isAtom(parts[0],"stop"){match data.Decode(parts[2]){case result.Err(f):return result.Err[EventHandlerResult[S,D],Failure](f);case result.Ok(d):return ok[EventHandlerResult[S,D]](EventStopWithData(parts[1].Clone(),d))}}
        if (len(parts)==3||len(parts)==4)&&isAtom(parts[0],"stop_and_reply"){match decodeReplies(parts[2]){case result.Err(f):return result.Err[EventHandlerResult[S,D],Failure](f);case result.Ok(replies):if len(parts)==3{return ok[EventHandlerResult[S,D]](EventStopAndReply(parts[1].Clone(),replies))};match data.Decode(parts[3]){case result.Err(f):return result.Err[EventHandlerResult[S,D],Failure](f);case result.Ok(d):return ok[EventHandlerResult[S,D]](EventStopReplyData(parts[1].Clone(),replies,d))}}}
    case _: };return bad[EventHandlerResult[S,D]]("event_handler_result","invalid callback result") }

func EncodeStateEnterResult[S,D any](value StateEnterResult[S,D],state Codec[S],data Codec[D]) result.Result[term.Term,Failure] { match value {
case EnterNext(s,d,a):match encodeCodecPair(state,s,data,d){case result.Err(f):return result.Err[term.Term,Failure](f);case result.Ok(v):return callbackTuple("next_state",v[0],v[1],encodeEnterActions(a),len(a)>0)}
case EnterKeep(d,a):match data.Encode(d){case result.Err(f):return result.Err[term.Term,Failure](f);case result.Ok(v):return callbackDataTuple("keep_state",v,encodeEnterActions(a),len(a)>0)}
case EnterKeepData(a):return callbackAtomTuple("keep_state_and_data",encodeEnterActions(a),len(a)>0)
case EnterRepeat(d,a):match data.Encode(d){case result.Err(f):return result.Err[term.Term,Failure](f);case result.Ok(v):return callbackDataTuple("repeat_state",v,encodeEnterActions(a),len(a)>0)}
case EnterRepeatData(a):return callbackAtomTuple("repeat_state_and_data",encodeEnterActions(a),len(a)>0)
case EnterStop(reason):return ok(term.Tuple(atom("stop"),reason))
case EnterStopWithData(reason,d):match data.Encode(d){case result.Err(f):return result.Err[term.Term,Failure](f);case result.Ok(v):return ok(term.Tuple(atom("stop"),reason,v))}
case EnterStopAndReply(reason,replies):return ok(term.Tuple(atom("stop_and_reply"),reason,encodeReplies(replies)))
case EnterStopReplyData(reason,replies,d):match data.Encode(d){case result.Err(f):return result.Err[term.Term,Failure](f);case result.Ok(v):return ok(term.Tuple(atom("stop_and_reply"),reason,encodeReplies(replies),v))}
} }

func DecodeStateEnterResult[S,D any](value term.Term,state Codec[S],data Codec[D]) result.Result[StateEnterResult[S,D],Failure] { match value { case term.AtomTerm(name):switch name{case "keep_state_and_data":return ok[StateEnterResult[S,D]](EnterKeepData(nil));case "repeat_state_and_data":return ok[StateEnterResult[S,D]](EnterRepeatData(nil));case "stop":return ok[StateEnterResult[S,D]](EnterStop(atom("normal")))};case term.TupleTerm(parts):
    if (len(parts)==3||len(parts)==4)&&isAtom(parts[0],"next_state"){match decodeCodecPair(state,parts[1],data,parts[2]){case result.Err(f):return result.Err[StateEnterResult[S,D],Failure](f);case result.Ok(decoded):a:=[]EnterAction{};if len(parts)==4{match decodeEnterActions(parts[3]){case result.Err(f):return result.Err[StateEnterResult[S,D],Failure](f);case result.Ok(v):a=v}};return ok[StateEnterResult[S,D]](EnterNext(decoded.State,decoded.Data,a))}}
    if (len(parts)==2||len(parts)==3)&&(isAtom(parts[0],"keep_state")||isAtom(parts[0],"repeat_state")){match data.Decode(parts[1]){case result.Err(f):return result.Err[StateEnterResult[S,D],Failure](f);case result.Ok(d):a:=[]EnterAction{};if len(parts)==3{match decodeEnterActions(parts[2]){case result.Err(f):return result.Err[StateEnterResult[S,D],Failure](f);case result.Ok(v):a=v}};if isAtom(parts[0],"keep_state"){return ok[StateEnterResult[S,D]](EnterKeep(d,a))};return ok[StateEnterResult[S,D]](EnterRepeat(d,a))}}
    if len(parts)==2&&(isAtom(parts[0],"keep_state_and_data")||isAtom(parts[0],"repeat_state_and_data")){match decodeEnterActions(parts[1]){case result.Err(f):return result.Err[StateEnterResult[S,D],Failure](f);case result.Ok(a):if isAtom(parts[0],"keep_state_and_data"){return ok[StateEnterResult[S,D]](EnterKeepData(a))};return ok[StateEnterResult[S,D]](EnterRepeatData(a))}}
    if len(parts)==2&&isAtom(parts[0],"stop"){return ok[StateEnterResult[S,D]](EnterStop(parts[1].Clone()))};if len(parts)==3&&isAtom(parts[0],"stop"){match data.Decode(parts[2]){case result.Err(f):return result.Err[StateEnterResult[S,D],Failure](f);case result.Ok(d):return ok[StateEnterResult[S,D]](EnterStopWithData(parts[1].Clone(),d))}}
    if (len(parts)==3||len(parts)==4)&&isAtom(parts[0],"stop_and_reply"){match decodeReplies(parts[2]){case result.Err(f):return result.Err[StateEnterResult[S,D],Failure](f);case result.Ok(replies):if len(parts)==3{return ok[StateEnterResult[S,D]](EnterStopAndReply(parts[1].Clone(),replies))};match data.Decode(parts[3]){case result.Err(f):return result.Err[StateEnterResult[S,D],Failure](f);case result.Ok(d):return ok[StateEnterResult[S,D]](EnterStopReplyData(parts[1].Clone(),replies,d))}}}
case _:};return bad[StateEnterResult[S,D]]("state_enter_result","invalid callback result") }

func EncodeStateFunctionResult[D any](value StateFunctionResult[D],data Codec[D]) result.Result[term.Term,Failure] { return EncodeEventHandlerResult(value.Result,AtomCodec{},data) }
func DecodeStateFunctionResult[D any](value term.Term,data Codec[D]) result.Result[StateFunctionResult[D],Failure] { match DecodeEventHandlerResult(value,AtomCodec{},data){case result.Err(f):return result.Err[StateFunctionResult[D],Failure](f);case result.Ok(decoded):return ok(StateFunctionResult[D]{Result:decoded})} }
func EncodeHandleEventResult[S,D any](value HandleEventResult[S,D],state Codec[S],data Codec[D]) result.Result[term.Term,Failure] { return EncodeEventHandlerResult(value.Result,state,data) }
func DecodeHandleEventResult[S,D any](value term.Term,state Codec[S],data Codec[D]) result.Result[HandleEventResult[S,D],Failure] { match DecodeEventHandlerResult(value,state,data){case result.Err(f):return result.Err[HandleEventResult[S,D],Failure](f);case result.Ok(decoded):return ok(HandleEventResult[S,D]{Result:decoded})} }

type AtomCodec struct{}
func (AtomCodec) Encode(value string) result.Result[term.Term,Failure] { if value==""{return bad[term.Term]("state_name","empty atom")};match term.Atom(value){case result.Err(f):return bad[term.Term]("state_name",f.Error());case result.Ok(encoded):return ok(encoded)} }
func (AtomCodec) Decode(value term.Term) result.Result[string,Failure] { match value{case term.AtomTerm(name):if name!=""{return ok(name)};case _:};return bad[string]("state_name","expected non-empty atom") }

func EncodeFormatStatus(value FormatStatus) result.Result[term.Term,Failure] { entries:=[]term.MapEntry{{Key:atom("state"),Value:value.State},{Key:atom("data"),Value:value.Data},{Key:atom("reason"),Value:value.Reason},{Key:atom("queue"),Value:encodeStatusEvents(value.Queue)},{Key:atom("postponed"),Value:encodeStatusEvents(value.Postponed)},{Key:atom("timeouts"),Value:encodeStatusTimeouts(value.Timeouts)},{Key:atom("log"),Value:term.List(value.Log...)}};match term.Map(entries){case result.Err(_):return bad[term.Term]("format_status","duplicate field");case result.Ok(encoded):return ok(encoded)} }
func DecodeFormatStatus(value term.Term) result.Result[FormatStatus,Failure] { match value { case term.MapTerm(entries): fields:=map[string]term.Term{};for _,entry:=range entries{match entry.Key{case term.AtomTerm(name):fields[name]=entry.Value.Clone();case _:return bad[FormatStatus]("format_status","non-atom key")}};required:=[]string{"state","data","reason","queue","postponed","timeouts","log"};for _,name:=range required{if fields[name]==nil{return bad[FormatStatus]("format_status."+name,"missing field")}};queue,f:=decodeStatusEvents(fields["queue"]);if f!=nil{return result.Err[FormatStatus,Failure](f)};postponed,f:=decodeStatusEvents(fields["postponed"]);if f!=nil{return result.Err[FormatStatus,Failure](f)};timeouts,f:=decodeStatusTimeouts(fields["timeouts"]);if f!=nil{return result.Err[FormatStatus,Failure](f)};match fields["log"]{case term.ProperListTerm(log):return ok(FormatStatus{State:fields["state"],Data:fields["data"],Reason:fields["reason"],Queue:queue,Postponed:postponed,Timeouts:timeouts,Log:clone(log)});case _:return bad[FormatStatus]("format_status.log","expected list")};case _:return bad[FormatStatus]("format_status","expected map")} }

func encodeActions(values []Action) term.Term { encoded:=make([]term.Term,len(values));for i,v:=range values{encoded[i]=EncodeAction(v)};return term.List(encoded...) }
func decodeActions(value term.Term) result.Result[[]Action,Failure] { items:=[]term.Term{value};match value{case term.ProperListTerm(found):items=found;case _:};decoded:=make([]Action,len(items));for i,item:=range items{match DecodeAction(item){case result.Err(f):return result.Err[[]Action,Failure](f);case result.Ok(v):decoded[i]=v}};return ok(decoded) }
func encodeEnterActions(values []EnterAction) term.Term { encoded:=make([]term.Term,len(values));for i,v:=range values{encoded[i]=EncodeEnterAction(v)};return term.List(encoded...) }
func decodeEnterActions(value term.Term) result.Result[[]EnterAction,Failure] { items:=[]term.Term{value};match value{case term.ProperListTerm(found):items=found;case _:};decoded:=make([]EnterAction,len(items));for i,item:=range items{match DecodeEnterAction(item){case result.Err(f):return result.Err[[]EnterAction,Failure](f);case result.Ok(v):decoded[i]=v}};return ok(decoded) }
func encodeReplies(values []ReplyAction) term.Term { encoded:=make([]term.Term,len(values));for i,v:=range values{encoded[i]=EncodeReplyAction(v)};return term.List(encoded...) }
func decodeReplies(value term.Term) result.Result[[]ReplyAction,Failure] { items:=[]term.Term{value};match value{case term.ProperListTerm(found):items=found;case _:};decoded:=make([]ReplyAction,len(items));for i,item:=range items{match DecodeReplyAction(item){case result.Err(f):return result.Err[[]ReplyAction,Failure](f);case result.Ok(v):decoded[i]=v}};return ok(decoded) }
func callbackTuple(tag string,a,b,actions term.Term,include bool) result.Result[term.Term,Failure] { if include{return ok(term.Tuple(atom(tag),a,b,actions))};return ok(term.Tuple(atom(tag),a,b)) }
func callbackDataTuple(tag string,data,actions term.Term,include bool) result.Result[term.Term,Failure] { if include{return ok(term.Tuple(atom(tag),data,actions))};return ok(term.Tuple(atom(tag),data)) }
func callbackAtomTuple(tag string,actions term.Term,include bool) result.Result[term.Term,Failure] { if include{return ok(term.Tuple(atom(tag),actions))};return ok(atom(tag)) }
func encodeStatusEvents(values []StatusEvent) term.Term { encoded:=make([]term.Term,len(values));for i,v:=range values{encoded[i]=term.Tuple(EncodeEventType(v.Type),v.Content)};return term.List(encoded...) }
func encodeStatusTimeouts(values []StatusTimeout) term.Term { encoded:=make([]term.Term,len(values));for i,v:=range values{encoded[i]=term.Tuple(EncodeEventType(v.Type),v.Content)};return term.List(encoded...) }
func decodeStatusEvents(value term.Term) ([]StatusEvent,Failure) { match value{case term.ProperListTerm(items):out:=make([]StatusEvent,len(items));for i,item:=range items{match pair(item){case result.Err(_):return nil,Invalid("format_status.events",fmt.Sprintf("item %d is not pair",i));case result.Ok(parts):match DecodeEventType(parts[0]){case result.Err(f):return nil,f;case result.Ok(kind):out[i]=StatusEvent{Type:kind,Content:parts[1].Clone()}}}};return out,nil;case _:return nil,Invalid("format_status.events","expected list")} }
func decodeStatusTimeouts(value term.Term) ([]StatusTimeout,Failure) { events,f:=decodeStatusEvents(value);if f!=nil{return nil,f};out:=make([]StatusTimeout,len(events));for i,v:=range events{out[i]=StatusTimeout{Type:v.Type,Content:v.Content}};return out,nil }
func decodeTimeoutOptionsBool(value term.Term,path string) result.Result[bool,Failure] { match value{case term.AtomTerm(name):if name=="true"{return ok(true)};if name=="false"{return ok(false)};case _:};return bad[bool](path,"expected boolean atom") }
func boolAtom(value term.Term,path string) result.Result[TimeoutOptions,Failure] { match decodeTimeoutOptionsBool(value,path){case result.Err(f):return result.Err[TimeoutOptions,Failure](f);case result.Ok(v):return ok(TimeoutOptions{Absolute:v})} }
func atom(name string) term.Term { return term.MustAtom(name) }
func isAtom(value term.Term,name string) bool { match value{case term.AtomTerm(found):return found==name;case _:return false} }
func pair(value term.Term) result.Result[[]term.Term,Failure] { return tuple(value,2) }
func tuple(value term.Term,size int) result.Result[[]term.Term,Failure] { match value{case term.TupleTerm(parts):if len(parts)==size{return ok(parts)};case _:};return bad[[]term.Term]("tuple",fmt.Sprintf("expected arity %d",size)) }
func clone(values []term.Term) []term.Term { out:=make([]term.Term,len(values));for i,v:=range values{out[i]=v.Clone()};return out }
