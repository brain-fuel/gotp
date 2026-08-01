-module(gen_server_enter_loop_callbacks).
-behaviour(gen_server).

-export([
    enter3_lifecycle/0,
	property_equivalence/1,
	proc_lib_ancestry/0,
    enter4_registered/0,
    enter4_timeout/0,
    enter4_continue/0,
    enter5_continue/0,
    enter5_hibernate/0,
    unsolicited_info/0,
    code_change_system/0,
    global_registered/0,
    via_registered/0,
    invalid_non_proc/0,
    invalid_local_missing/0,
    invalid_local_wrong/0,
    invalid_bad_action/0,
    linked_parent/0,
    linked_parent_helper/1,
    entered/5,
    direct_enter/1,
	ancestry_probe/1,
    register_name/2,
    unregister_name/1,
    whereis_name/1,
    send/2
]).
-export([init/1, handle_call/3, handle_cast/2, handle_continue/2, handle_info/2, terminate/2, code_change/3]).

proc_lib_ancestry() ->
    {ok, Ancestors} = proc_lib:start(?MODULE, ancestry_probe, [self()]),
    case Ancestors of [Parent | _] when Parent =:= self() -> initialized; Other -> {unexpected, Other} end.

ancestry_probe(Parent) -> proc_lib:init_ack(Parent, {ok, get('$ancestors')}).

enter3_lifecycle() ->
    Pid = start_enter(three, anonymous, infinity, 1),
    1 = gen_server:call(Pid, get),
    ok = gen_server:cast(Pid, increment),
    2 = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    {entered, 2}.

enter4_registered() ->
    Name = enter_loop_local,
    Pid = start_enter(four_name, {local, Name}, infinity, 3),
    Pid = whereis(Name),
    3 = gen_server:call(Name, get),
    ok = gen_server:stop(Name),
    {registered, true}.

enter4_timeout() ->
    Pid = start_enter(four_action, anonymous, 0, 4),
    receive {timeout_seen, Pid, 4} -> timeout_seen end.

enter4_continue() ->
    Pid = start_enter(four_action, anonymous, {continue, four}, 5),
    receive {continued, Pid, four, 5} -> ok end,
    Result = gen_server:call(Pid, get),
    gen_server:stop(Pid),
    {continued, Result}.

enter5_continue() ->
    Name = enter_loop_five,
    Pid = start_enter(five, {local, Name}, {continue, five}, 6),
    receive {continued, Pid, five, 6} -> ok end,
    Result = gen_server:call(Name, get),
    gen_server:stop(Name),
    {continued, Result}.

enter5_hibernate() ->
    Pid = start_enter(five, anonymous, hibernate, 7),
    Result = gen_server:call(Pid, get),
    gen_server:stop(Pid),
    {woke, Result}.

unsolicited_info() ->
    Pid = start_enter(three, anonymous, infinity, 8),
    Pid ! {info, self()},
    receive {info_seen, Pid, 8} -> ok end,
    9 = gen_server:call(Pid, get),
    gen_server:stop(Pid),
    {info, 9}.

code_change_system() ->
    Pid = start_enter(three, anonymous, infinity, 10),
    ok = sys:suspend(Pid),
    ok = sys:change_code(Pid, ?MODULE, old, 5),
    ok = sys:resume(Pid),
    15 = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    code_changed.

global_registered() ->
    Name = enter_loop_global,
    Pid = start_enter(five, {global, Name}, infinity, 11),
    Pid = global:whereis_name(Name),
    11 = gen_server:call({global, Name}, get),
    gen_server:stop({global, Name}),
    global_ok.

via_registered() ->
    Name = enter_loop_via,
    Via = {via, ?MODULE, Name},
    Pid = start_enter(five, Via, infinity, 12),
    Pid = whereis_name(Name),
    12 = gen_server:call(Via, get),
    gen_server:stop(Via),
    via_ok.

invalid_non_proc() ->
    {Pid, Ref} = spawn_monitor(?MODULE, direct_enter, [self()]),
    receive {'DOWN', Ref, process, Pid, Reason} -> classify_invalid(Reason) end.

invalid_local_missing() -> invalid_enter({local, enter_loop_missing}, missing).
invalid_local_wrong() -> invalid_enter({local, enter_loop_expected}, wrong).

invalid_bad_action() ->
    {ok, Pid} = proc_lib:start(?MODULE, entered, [self(), five, anonymous, {bad, action}, 0]),
    Ref = monitor(process, Pid),
    Pid ! enter_now,
    receive {'DOWN', Ref, process, Pid, Reason} -> Reason end.

linked_parent() ->
    {Helper, Ref} = spawn_monitor(?MODULE, linked_parent_helper, [self()]),
    Child = receive {linked_child, Helper, Pid} -> Pid end,
    ChildRef = monitor(process, Child),
    Helper ! crash_now,
    receive {'DOWN', Ref, process, Helper, parent_crash} -> ok end,
    receive {'DOWN', ChildRef, process, Child, Reason} -> {parent_crash, Reason} end.

linked_parent_helper(Parent) ->
    {ok, Pid} = proc_lib:start_link(?MODULE, entered, [self(), three, anonymous, infinity, 13]),
    Parent ! {linked_child, self(), Pid},
    receive crash_now -> exit(parent_crash) end.

direct_enter(_Parent) -> gen_server:enter_loop(?MODULE, [], 0).

invalid_enter(Name, Mode) ->
    {ok, Pid} = proc_lib:start(?MODULE, entered, [self(), five, Name, infinity, {invalid, Mode}]),
    Ref = monitor(process, Pid),
    Pid ! enter_now,
    receive {'DOWN', Ref, process, Pid, Reason} -> classify_invalid(Reason) end.

classify_invalid({process_not_registered, _}) -> process_not_registered;
classify_invalid({process_not_registered_globally, _}) -> process_not_registered_globally;
classify_invalid({process_not_registered_via, _}) -> process_not_registered_via;
classify_invalid({not_started_by_proc_lib, _}) -> not_started_by_proc_lib;
classify_invalid(process_was_not_started_by_proc_lib) -> process_was_not_started_by_proc_lib;
classify_invalid(Reason) -> Reason.

start_enter(Variant, Name, Action, State) ->
    {ok, Pid} = proc_lib:start(?MODULE, entered, [self(), Variant, Name, Action, State]),
    Pid.

entered(Parent, Variant, Name, Action, State) ->
    prepare_registration(Name, State),
    proc_lib:init_ack(Parent, {ok, self()}),
    maybe_wait_to_enter(Name, Action),
    case Variant of
        three -> gen_server:enter_loop(?MODULE, [], State);
        four_name -> gen_server:enter_loop(?MODULE, [], State, Name);
        four_action -> gen_server:enter_loop(?MODULE, [], State, Action);
        five -> gen_server:enter_loop(?MODULE, [], State, server_name(Name), Action)
    end.

server_name(anonymous) -> self();
server_name(Name) -> Name.

prepare_registration(_Name, {invalid, missing}) -> ok;
prepare_registration(_Name, {invalid, wrong}) -> register(enter_loop_other, self()), ok;
prepare_registration(anonymous, _State) -> ok;
prepare_registration({local, Name}, _State) -> register(Name, self()), ok;
prepare_registration({global, Name}, _State) -> yes = global:register_name(Name, self()), ok;
prepare_registration({via, Module, Name}, _State) -> yes = Module:register_name(Name, self()), ok;
prepare_registration(_, _State) -> ok.

maybe_wait_to_enter({local, enter_loop_missing}, _Action) -> receive enter_now -> ok end;
maybe_wait_to_enter({local, enter_loop_expected}, _Action) -> receive enter_now -> ok end;
maybe_wait_to_enter(_Name, {bad, action}) -> receive enter_now -> ok end;
maybe_wait_to_enter(_Name, _Action) -> ok.

register_name(enter_loop_via, Pid) -> register(enter_loop_via_backing, Pid), yes.
unregister_name(enter_loop_via) -> unregister(enter_loop_via_backing), ok.
whereis_name(enter_loop_via) -> whereis(enter_loop_via_backing).
send(enter_loop_via, Message) -> enter_loop_via_backing ! Message, enter_loop_via_backing.

init(State) -> {ok, State}.
handle_call(get, _From, State) -> {reply, State, State}.
handle_cast(increment, State) -> {noreply, State + 1}.
handle_continue(Value, State) -> self() ! {notify_continue, Value, State}, {noreply, State}.
handle_info({notify_continue, Value, State}, Current) -> get_parent() ! {continued, self(), Value, State}, {noreply, Current};
handle_info(timeout, State) -> get_parent() ! {timeout_seen, self(), State}, {noreply, State};
handle_info({info, To}, State) -> To ! {info_seen, self(), State}, {noreply, State + 1};
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_Old, State, Extra) -> {ok, State + Extra}.

get_parent() -> [Parent | _] = get('$ancestors'), Parent.

property_equivalence(Operations) ->
    {ok, Ordinary} = gen_server:start(?MODULE, 0, []),
    Entered = start_enter(three, anonymous, infinity, 0),
    OrdinaryTranscript = run_operations(Ordinary, Operations, []),
    EnteredTranscript = run_operations(Entered, Operations, []),
    OrdinaryState = gen_server:call(Ordinary, get),
    EnteredState = gen_server:call(Entered, get),
    ok = gen_server:stop(Ordinary),
    ok = gen_server:stop(Entered),
    {OrdinaryTranscript, OrdinaryState} = {EnteredTranscript, EnteredState},
    equivalent.

run_operations(_Pid, [], Transcript) -> lists:reverse(Transcript);
run_operations(Pid, [increment | Rest], Transcript) ->
    ok = gen_server:cast(Pid, increment),
    State = gen_server:call(Pid, get),
    run_operations(Pid, Rest, [{increment, State} | Transcript]);
run_operations(Pid, [info | Rest], Transcript) ->
    Pid ! {info, self()},
    receive {info_seen, Pid, State} ->
        Current = gen_server:call(Pid, get),
        run_operations(Pid, Rest, [{info, State, Current} | Transcript])
    end;
run_operations(Pid, [suspend | Rest], Transcript) ->
    ok = sys:suspend(Pid),
    ok = sys:resume(Pid),
    State = gen_server:call(Pid, get),
    run_operations(Pid, Rest, [{suspend, State} | Transcript]);
run_operations(Pid, [code_change | Rest], Transcript) ->
    ok = sys:suspend(Pid),
    ok = sys:change_code(Pid, ?MODULE, old, 1),
    ok = sys:resume(Pid),
    State = gen_server:call(Pid, get),
    run_operations(Pid, Rest, [{code_change, State} | Transcript]);
run_operations(Pid, [get | Rest], Transcript) ->
    State = gen_server:call(Pid, get),
    run_operations(Pid, Rest, [{get, State} | Transcript]).
