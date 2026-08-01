-module(gen_statem_fixture).
-export([init/1,event/4,run/2,trace/2,linked_parent_helper/2,call_wait/3]).

init(Owner) -> {ok, idle, {Owner,0,[]}}.

event(enter, Old, State, {Owner,N,L}) -> {keep_state,{Owner,N,[{enter,Old,State}|L]}};
event({call,From}, get, _State, Data) -> {keep_state_and_data,{reply,From,normalize(Data)}};
event({call,From}, repeat, _State, _Data) -> {repeat_state_and_data,{reply,From,repeated}};
event({call,From}, repeat_with_data, _State, Data) -> {repeat_state,Data,{reply,From,repeated_with_data}};
event({call,From}, explicit_reply, _State, _Data) -> ok=gen_statem:reply(From,explicit), keep_state_and_data;
event({call,From}, list_reply, _State, _Data) -> ok=gen_statem:reply([{reply,From,listed}]), keep_state_and_data;
event({call,From}, hibernate, _State, _Data) -> {keep_state_and_data,[{reply,From,hibernating},hibernate]};
event({call,From}, {switch,Module}, _State, _Data) -> {keep_state_and_data,[{reply,From,switched},{change_callback_module,Module},{next_event,internal,changed_module}]};
event({call,From}, {push,Module}, _State, _Data) -> {keep_state_and_data,[{reply,From,pushed},{push_callback_module,Module},{next_event,internal,pushed_module}]};
event({call,From}, pop, _State, _Data) -> {keep_state_and_data,[{reply,From,popped},pop_callback_module,{next_event,internal,popped_module}]};
event({call,From}, {wait,Tag}, _State, {Owner,N,[{pending,OtherTag,OtherFrom}|L]}) ->
    {keep_state,{Owner,N,L},[{reply,OtherFrom,{OtherTag,replied}},{reply,From,{Tag,replied}}]};
event({call,From}, {wait,Tag}, _State, {Owner,N,L}) -> {keep_state,{Owner,N,[{pending,Tag,From}|L]}};
event({call,From}, arm, _State, _Data) -> {keep_state_and_data,[{reply,From,armed},{next_event,internal,next},{state_timeout,0,state_tick},{timeout,0,event_tick},{{timeout,named},0,named_tick}]};
event({call,From}, arm_event, _State, _Data) -> {keep_state_and_data,[{reply,From,armed},{timeout,0,event_tick}]};
event(cast, {set,V}, _State, {Owner,_N,L}) -> {next_state,active,{Owner,V,[set|L]}};
event(cast, postpone, idle, _Data) -> {keep_state_and_data,postpone};
event(cast, postpone, active, {Owner,N,L}) -> {keep_state,{Owner,N,[postponed|L]}};
event(cast, activate, _State, Data) -> {next_state,active,Data};
event(cast, sequence, _State, _Data) -> {keep_state_and_data,[{next_event,internal,first},{next_event,internal,second}]};
event(internal, E, _State, {Owner,N,L}) -> {keep_state,{Owner,N,[{internal,E}|L]}};
event(info, increment, _State, {Owner,N,L}) -> {keep_state,{Owner,N+1,[info|L]}};
event(state_timeout, state_tick, _State, {Owner,N,L}) -> {keep_state,{Owner,N,[state_timeout|L]}};
event(timeout, event_tick, _State, {Owner,N,L}) -> {keep_state,{Owner,N,[event_timeout|L]}};
event({timeout,named}, named_tick, _State, {Owner,N,L}) -> {keep_state,{Owner,N,[named_timeout|L]}};
event(cast, crash, _State, _Data) -> exit(callback_crash);
event(cast, malformed, _State, _Data) -> malformed_return;
event(cast, {invalid,Action}, _State, _Data) -> {keep_state_and_data,Action};
event(_Type, _Event, _State, _Data) -> keep_state_and_data.

normalize({_Owner,N,L}) -> {N,lists:reverse(L)}.

run(Module,lifecycle) ->
 {ok,P1}=gen_statem:start(Module,self(),[]),
 A=gen_statem:call(P1,get), ok=gen_statem:cast(P1,{set,7}), B=gen_statem:call(P1,get), ok=gen_statem:stop(P1),
 {ok,P2}=gen_statem:start({local,statem_named},Module,self(),[]), Named=whereis(statem_named)=:=P2, ok=gen_statem:stop(P2,normal,infinity),
 {ok,P3}=gen_statem:start_link(Module,self(),[]), Linked=lists:member(P3,element(2,process_info(self(),links))), ok=gen_statem:stop(P3),
 {ok,{P4,R4}}=gen_statem:start_monitor(Module,self(),[]), ok=gen_statem:stop(P4), receive {'DOWN',R4,process,P4,normal}->ok end,
 {A,B,Named,Linked,monitored};
run(Module,construction) ->
 {ok,P1}=gen_statem:start_link({local,statem_named_link},Module,self(),[]), L=whereis(statem_named_link)=:=P1, ok=gen_statem:stop(P1),
 {ok,{P2,R2}}=gen_statem:start_monitor({local,statem_named_monitor},Module,self(),[]), M=whereis(statem_named_monitor)=:=P2, ok=gen_statem:stop(P2), receive {'DOWN',R2,process,P2,normal}->ok end,
 {L,M};
run(Module,events) ->
 {ok,P}=gen_statem:start(Module,self(),[]),
 ok=gen_statem:cast(P,sequence), P ! increment, ok=gen_statem:cast(P,postpone), ok=gen_statem:cast(P,activate),
 repeated=gen_statem:call(P,repeat), repeated_with_data=gen_statem:call(P,repeat_with_data), Result=gen_statem:call(P,get), ok=gen_statem:stop(P), Result;
run(Module,timeouts) ->
 {ok,P}=gen_statem:start(Module,self(),[]), armed=gen_statem:call(P,arm), receive after 2 -> ok end,
 Result=gen_statem:call(P,get), ok=gen_statem:stop(P), Result;
run(Module,event_timeout) ->
 {ok,P}=gen_statem:start(Module,self(),[]), armed=gen_statem:call(P,arm_event), receive after 2->ok end,
 Result=gen_statem:call(P,get), ok=gen_statem:stop(P), Result;
run(Module,system) ->
 {ok,P}=gen_statem:start(Module,self(),[]), ok=sys:suspend(P), {idle,_}=sys:get_state(P),
 {idle,_}=sys:replace_state(P,fun({S,{O,N,L}})->{S,{O,N+2,[replaced|L]}} end), ok=sys:change_code(P,Module,old,3), ok=sys:resume(P),
 Result=gen_statem:call(P,get), ok=gen_statem:stop(P), Result;
run(Module,termination) ->
 {ok,P}=gen_statem:start(Module,self(),[]), ok=gen_statem:stop(P,shutdown,infinity),
 receive {terminated,P,shutdown}->terminated end;
run(Module,replies) ->
 {ok,P}=gen_statem:start(Module,self(),[]), explicit=gen_statem:call(P,explicit_reply,1000), listed=gen_statem:call(P,list_reply,1000),
 Owner=self(), spawn_monitor(?MODULE,call_wait,[Owner,P,one]), spawn_monitor(?MODULE,call_wait,[Owner,P,two]),
 R1=receive {reply_result,X1}->X1 end, R2=receive {reply_result,X2}->X2 end, ok=gen_statem:stop(P),
 {explicit,listed,lists:sort([R1,R2])};
run(Module,hibernate) ->
 {ok,P}=gen_statem:start(Module,self(),[]), hibernating=gen_statem:call(P,hibernate), Result=gen_statem:call(P,get), ok=gen_statem:stop(P), Result;
run(Module,switch) ->
 Other=case Module of gen_statem_state_functions_callbacks->gen_statem_handle_event_callbacks; _->gen_statem_state_functions_callbacks end,
 {ok,P}=gen_statem:start(Module,self(),[]), switched=gen_statem:call(P,{switch,Other}), Result=gen_statem:call(P,get), ok=gen_statem:stop(P), Result;
run(Module,callback_stack) ->
 Other=case Module of gen_statem_state_functions_callbacks->gen_statem_handle_event_callbacks; _->gen_statem_state_functions_callbacks end,
 {ok,P}=gen_statem:start(Module,self(),[]), pushed=gen_statem:call(P,{push,Other}), popped=gen_statem:call(P,pop), Result=gen_statem:call(P,get), ok=gen_statem:stop(P), Result;
run(Module,enter4) -> enter_case(Module,4);
run(Module,enter5) -> enter_case(Module,5);
run(Module,enter6) -> enter_case(Module,6);
run(Module,linked_parent) ->
 {Helper,HR}=spawn_monitor(?MODULE,linked_parent_helper,[self(),Module]),
 Child=receive {linked_child,Helper,P}->P end, CR=monitor(process,Child), Helper!crash,
 receive {'DOWN',HR,process,Helper,parent_crash}->ok end,
 receive {'DOWN',CR,process,Child,Reason}->{parent_exit,Reason} end;
run(Module,invalid_action) -> invalid_case(Module,{invalid,action});
run(Module,invalid_timeout) -> invalid_case(Module,{state_timeout,bad_time,payload});
run(Module,invalid_next_event) -> invalid_case(Module,{next_event,{call,bad_from},payload});
run(Module,crash) ->
 {ok,{P,R}}=gen_statem:start_monitor(Module,self(),[]), ok=gen_statem:cast(P,crash), receive {'DOWN',R,process,P,Reason}->classify(Reason) end;
run(Module,malformed) ->
 {ok,{P,R}}=gen_statem:start_monitor(Module,self(),[]), ok=gen_statem:cast(P,malformed), receive {'DOWN',R,process,P,Reason}->classify(Reason) end.

classify(callback_crash) -> callback_crash;
classify({bad_return_from_state_function,malformed_return}) -> malformed;
classify({bad_return_from_state_function,_}) -> malformed;
classify({{bad_return_from_state_function,_},_}) -> malformed;
classify(Other) -> Other.

invalid_case(Module,Action) ->
 {ok,{P,R}}=gen_statem:start_monitor(Module,self(),[]), ok=gen_statem:cast(P,{invalid,Action}),
 receive {'DOWN',R,process,P,Reason}->classify_invalid(Reason) end.

classify_invalid({bad_action_from_state_function,_}) -> invalid_action;
classify_invalid({{bad_action_from_state_function,_},_}) -> invalid_action;
classify_invalid({bad_timeout,_}) -> invalid_timeout;
classify_invalid({{bad_timeout,_},_}) -> invalid_timeout;
classify_invalid(_) -> invalid_failure.

enter_case(Module,Arity) ->
 {ok,P}=proc_lib:start_link(Module,enter_init,[self(),Arity]),
 Result=gen_statem:call(P,get), ok=gen_statem:stop(P), {entered,Arity,Result}.

linked_parent_helper(Owner,Module) ->
 {ok,Child}=gen_statem:start_link(Module,self(),[]), Owner!{linked_child,self(),Child}, receive crash->exit(parent_crash) end.

call_wait(Owner,Pid,Tag) -> Owner!{reply_result,gen_statem:call(Pid,{wait,Tag})}.

trace(Module, Operations) ->
    {ok,Pid}=gen_statem:start(Module,self(),[]),
    lists:foreach(fun
        (set) -> ok=gen_statem:cast(Pid,{set,7});
        (info) -> Pid ! increment;
        (sequence) -> ok=gen_statem:cast(Pid,sequence);
        (postpone) -> ok=gen_statem:cast(Pid,postpone), ok=gen_statem:cast(Pid,activate);
        (repeat) -> repeated=gen_statem:call(Pid,repeat), repeated_with_data=gen_statem:call(Pid,repeat_with_data)
    end, Operations),
    Result=gen_statem:call(Pid,get), ok=gen_statem:stop(Pid), Result.
