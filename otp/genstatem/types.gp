package genstatem

import (
    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/term"
)

type Failure enum {
    Invalid(Path string, Detail string)
}

func (failure Failure) Error() string {
    match failure { case Invalid(path, detail): return "gotp/genstatem: " + path + ": " + detail }
}

type Codec[T any] interface {
    Encode(T) result.Result[term.Term, Failure]
    Decode(term.Term) result.Result[T, Failure]
}

type TermCodec struct{}
func (TermCodec) Encode(value term.Term) result.Result[term.Term, Failure] { return result.Ok[term.Term, Failure](value.Clone()) }
func (TermCodec) Decode(value term.Term) result.Result[term.Term, Failure] { return result.Ok[term.Term, Failure](value.Clone()) }

type ReplyTag struct { value term.Term }
type RequestID struct { value term.Reference }
type RequestIDCollection struct { entries []RequestIDEntry }
type RequestIDEntry struct { ID RequestID; Label term.Term }

func NewReplyTag(value term.Term) ReplyTag { return ReplyTag{value: value.Clone()} }
func (tag ReplyTag) Term() term.Term { return tag.value.Clone() }
func NewRequestID(value term.Reference) RequestID { return RequestID{value: value} }
func (id RequestID) Reference() term.Reference { return id.value }
func NewRequestIDCollection(entries []RequestIDEntry) RequestIDCollection {
    copied := make([]RequestIDEntry, len(entries))
    for index, entry := range entries { copied[index] = RequestIDEntry{ID: entry.ID, Label: entry.Label.Clone()} }
    return RequestIDCollection{entries: copied}
}
func (collection RequestIDCollection) Entries() []RequestIDEntry { return NewRequestIDCollection(collection.entries).entries }

type From struct { To term.PID; Tag ReplyTag }

type EventType enum {
    CallEvent(Caller From)
    CastEvent()
    InfoEvent()
    InternalEvent()
    EventTimeout()
    NamedTimeout(Name term.Term)
    StateTimeout()
}

type CallbackModeResult enum {
    StateFunctions(StateEnter bool)
    HandleEventFunction(StateEnter bool)
}

type Timeout enum {
    Infinity()
    Milliseconds(Value int64)
}

type TimeoutOptions struct { Absolute bool }

type TimeoutAction enum {
    EventTimeoutAfter(Time Timeout, Content term.Term, Options TimeoutOptions)
    NamedTimeoutAfter(Name term.Term, Time Timeout, Content term.Term, Options TimeoutOptions)
    StateTimeoutAfter(Time Timeout, Content term.Term, Options TimeoutOptions)
    CancelEventTimeout()
    CancelNamedTimeout(Name term.Term)
    CancelStateTimeout()
    UpdateEventTimeout(Content term.Term)
    UpdateNamedTimeout(Name term.Term, Content term.Term)
    UpdateStateTimeout(Content term.Term)
}

type ReplyAction struct { From From; Reply term.Term }

type EnterAction enum {
    HibernateEnter(Enabled bool)
    TimeoutEnter(Value TimeoutAction)
    ReplyEnter(Value ReplyAction)
}

type Action enum {
    Postpone(Enabled bool)
    NextEvent(Type EventType, Content term.Term)
    ChangeCallbackModule(Module string)
    PushCallbackModule(Module string)
    PopCallbackModule()
    Enter(Value EnterAction)
}

type TransitionOption enum {
    BooleanTransition(Enabled bool)
    TimeoutTransition(Time Timeout)
}

type InitResult[State, Data any] enum {
    InitOK(StateValue State, DataValue Data, Actions []Action)
    InitIgnore()
    InitStop(Reason term.Term)
    InitError(Reason term.Term)
}

type StateEnterResult[State, Data any] enum {
    EnterNext(StateValue State, DataValue Data, Actions []EnterAction)
    EnterKeep(DataValue Data, Actions []EnterAction)
    EnterKeepData(Actions []EnterAction)
    EnterRepeat(DataValue Data, Actions []EnterAction)
    EnterRepeatData(Actions []EnterAction)
    EnterStop(Reason term.Term)
    EnterStopWithData(Reason term.Term, DataValue Data)
    EnterStopAndReply(Reason term.Term, Replies []ReplyAction)
    EnterStopReplyData(Reason term.Term, Replies []ReplyAction, DataValue Data)
}

type EventHandlerResult[State, Data any] enum {
    EventNext(StateValue State, DataValue Data, Actions []Action)
    EventKeep(DataValue Data, Actions []Action)
    EventKeepData(Actions []Action)
    EventRepeat(DataValue Data, Actions []Action)
    EventRepeatData(Actions []Action)
    EventStop(Reason term.Term)
    EventStopWithData(Reason term.Term, DataValue Data)
    EventStopAndReply(Reason term.Term, Replies []ReplyAction)
    EventStopReplyData(Reason term.Term, Replies []ReplyAction, DataValue Data)
}

type StateFunctionResult[Data any] struct { Result EventHandlerResult[string, Data] }
type HandleEventResult[State, Data any] struct { Result EventHandlerResult[State, Data] }

type ServerName enum {
    LocalName(Name string)
    GlobalName(Name term.Term)
    ViaName(Module string, Name term.Term)
}

type ServerRef enum {
    ServerPID(PID term.PID)
    LocalRef(Name string)
    RemoteRef(Name string, Node string)
    GlobalRef(Name term.Term)
    ViaRef(Module string, Name term.Term)
}

type EnterLoopOpt enum {
    HibernateAfter(Time Timeout)
    Debug(Options []term.Term)
}

type StartOpt enum {
    StartTimeout(Time Timeout)
    SpawnOptions(Options []term.Term)
    EnterLoopOption(Option EnterLoopOpt)
}

type StartRet enum {
    Started(PID term.PID)
    StartIgnored()
    StartFailed(Reason term.Term)
}

type StartMonRet enum {
    StartedMonitored(PID term.PID, Monitor term.Reference)
    StartMonitorIgnored()
    StartMonitorFailed(Reason term.Term)
}

type StatusEvent struct { Type EventType; Content term.Term }
type StatusTimeout struct { Type EventType; Content term.Term }
type FormatStatus struct {
    State term.Term
    Data term.Term
    Reason term.Term
    Queue []StatusEvent
    Postponed []StatusEvent
    Timeouts []StatusTimeout
    Log []term.Term
}
