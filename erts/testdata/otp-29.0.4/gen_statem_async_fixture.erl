-module(gen_statem_async_fixture).
-export([init/0,event/4,run/2,property_collection/3]).

init() -> {ok,idle,none}.

event({call,From},{reply,Value},_State,Data) -> {keep_state,Data,{reply,From,Value}};
event({call,From},defer,_State,_Data) -> {keep_state,{deferred,From}};
event({call,From},release,_State,{deferred,Deferred}) -> ok=gen_statem:reply(Deferred,late), {keep_state,none,{reply,From,released}};
event({call,_From},crash,_State,_Data) -> exit(async_crash);
event({call,From},{ordered,first},_State,_Data) -> {keep_state,{ordered,From}};
event({call,From},{ordered,second},_State,{ordered,First}) -> {keep_state,First,[{reply,From,second},{next_event,internal,release_first}]};
event({call,From},{hold,Label},_State,Data) -> {keep_state,[{Label,From}|list_state(Data)]};
event({call,From},{release_order,Order},_State,Data) ->
 lists:foreach(fun(Label)->{Label,Pending}=lists:keyfind(Label,1,Data),ok=gen_statem:reply(Pending,Label) end,Order),
 {keep_state,none,{reply,From,released}};
event(internal,release_first,_State,First) -> ok=gen_statem:reply(First,first), {keep_state,none};
event(_Type,_Event,_State,Data) -> {keep_state,Data}.

run(Module,wait1) -> with_server(Module,fun(P)->R=gen_statem:send_request(P,{reply,wait1}),gen_statem:wait_response(R) end);
run(Module,wait2) -> with_server(Module,fun(P)->R=gen_statem:send_request(P,{reply,wait2}),gen_statem:wait_response(R,infinity) end);
run(Module,receive1) -> with_server(Module,fun(P)->R=gen_statem:send_request(P,{reply,receive1}),gen_statem:receive_response(R) end);
run(Module,receive2) -> with_server(Module,fun(P)->R=gen_statem:send_request(P,{reply,receive2}),gen_statem:receive_response(R,infinity) end);
run(Module,send4_wait_collection) -> with_server(Module,fun(P)->C=gen_statem:send_request(P,{reply,collected},label,gen_statem:reqids_new()),{{reply,collected},label,R}=gen_statem:wait_response(C,infinity,true),{gen_statem:reqids_size(C),gen_statem:reqids_size(R)} end);
run(Module,receive_collection) -> with_server(Module,fun(P)->C=gen_statem:send_request(P,{reply,collected},label,gen_statem:reqids_new()),{{reply,collected},label,R}=gen_statem:receive_response(C,infinity,true),{gen_statem:reqids_size(C),gen_statem:reqids_size(R)} end);
run(Module,reqids_add_list) -> with_server(Module,fun(P)->R=gen_statem:send_request(P,{reply,added}),C=gen_statem:reqids_add(R,added_label,gen_statem:reqids_new()),L=gen_statem:reqids_to_list(C),{{reply,added},added_label,_}=gen_statem:wait_response(C,infinity,true),{gen_statem:reqids_size(C),classify_reqids(L)} end);
run(Module,collection_retain) -> with_server(Module,fun(P)->C=gen_statem:send_request(P,{reply,retained},retained_label,gen_statem:reqids_new()),{{reply,retained},retained_label,R}=gen_statem:wait_response(C,infinity,false),{gen_statem:reqids_size(C),gen_statem:reqids_size(R),length(gen_statem:reqids_to_list(R))} end);
run(Module,wait_timeout_retry) -> with_server(Module,fun(P)->R=gen_statem:send_request(P,defer),timeout=gen_statem:wait_response(R,0),released=gen_statem:call(P,release),gen_statem:wait_response(R,infinity) end);
run(Module,receive_abandon_late) -> with_server(Module,fun(P)->R=gen_statem:send_request(P,defer),timeout=gen_statem:receive_response(R,0),released=gen_statem:call(P,release),receive _->contaminated after 0->clean end end);
run(Module,crashed_server) ->
 {ok,P}=gen_statem:start(Module,[],[]),R=gen_statem:send_request(P,crash),case gen_statem:wait_response(R,infinity) of {error,{async_crash,P}}->exact_async_crash; Other->{unexpected,Other} end;
run(Module,dead_server) ->
 {ok,P}=gen_statem:start(Module,[],[]),ok=gen_statem:stop(P),R=gen_statem:send_request(P,{reply,late}),case gen_statem:wait_response(R,infinity) of {error,{noproc,P}}->exact_noproc; Other->{unexpected,Other} end;
run(Module,named_server) ->
 Name=gen_statem_async_named,{ok,P}=gen_statem:start({local,Name},Module,[],[]),R=gen_statem:send_request(Name,{reply,named}),Value=gen_statem:receive_response(R,infinity),ok=gen_statem:stop(P),Value;
run(Module,out_of_order) -> with_server(Module,fun(P)->C0=gen_statem:reqids_new(),C1=gen_statem:send_request(P,{ordered,first},first,C0),C2=gen_statem:send_request(P,{ordered,second},second,C1),{{reply,second},second,C3}=gen_statem:wait_response(C2,infinity,true),{{reply,first},first,C4}=gen_statem:wait_response(C3,infinity,true),{gen_statem:reqids_size(C2),gen_statem:reqids_size(C3),gen_statem:reqids_size(C4)} end);
run(Module,check_direct) -> with_server(Module,fun(P)->R=gen_statem:send_request(P,{reply,checked}),no_reply=gen_statem:check_response(unrelated,R),receive Msg->gen_statem:check_response(Msg,R) end end);
run(Module,check_collection) -> with_server(Module,fun(P)->C=gen_statem:send_request(P,{reply,checked},checked_label,gen_statem:reqids_new()),no_reply=gen_statem:check_response(unrelated,C,true),{{reply,checked},checked_label,R}=receive Msg->gen_statem:check_response(Msg,C,true) end,gen_statem:reqids_size(R) end);
run(Module,mailbox_clean) -> with_server(Module,fun(P)->R=gen_statem:send_request(P,{reply,clean}),{reply,clean}=gen_statem:wait_response(R,infinity),receive _->contaminated after 0->clean end end).

property_collection(Module,Order,Delete) ->
 {ok,P}=gen_statem:start(Module,[],[]), C0=gen_statem:reqids_new(),
 C=lists:foldl(fun(Label,A)->gen_statem:send_request(P,{hold,Label},Label,A) end,C0,lists:seq(1,length(Order))),
 released=gen_statem:call(P,{release_order,Order}), Result=collect(C,Order,Delete,[],[]), ok=gen_statem:stop(P),Result.
collect(_C,[],_Delete,Labels,Sizes)->{lists:reverse(Labels),lists:reverse(Sizes)};
collect(C,[_|Rest],Delete,Labels,Sizes)->{{reply,L},L,N}=gen_statem:wait_response(C,infinity,Delete),collect(N,Rest,Delete,[L|Labels],[gen_statem:reqids_size(N)|Sizes]).

with_server(Module,Fun)->{ok,P}=gen_statem:start(Module,[],[]),Value=Fun(P),ok=gen_statem:stop(P),Value.
classify_reqids([{_ReqId,added_label}])->one_labeled_request;
classify_reqids(_)->unexpected_collection.
list_state(none)->[];
list_state(Data)->Data.
