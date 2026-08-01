-module(gen_server_remaining_callbacks).
-behaviour(gen_server).

-export([
    init_success/0, init_ignore/0, init_error/0, init_stop/0,
    init_bad_return/0, init_bad_action/0, init_crash/0, init_metadata/0,
    wake_call/0, wake_cast/0, wake_info/0, wake_timeout/0,
    wake_system/0, wake_malformed/0, wake_parent_exit/0, wake_parent_helper/1,
    abcast_all/0, abcast_nodes/0, stop_custom/0, stop_noproc/0,
    system_get_replace_continue/0, system_terminate/0,
    hibernate_equivalence/1, init_entry/4
]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

init_success() ->
    {ok, Pid} = direct_start(init_success_server, {normal, 1, self()}, []),
    {normal, 1, _} = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    initialized.

init_ignore() -> init_failure(init_ignore_server, ignore).
init_error() -> init_failure(init_error_server, init_error).
init_stop() -> init_failure(init_stop_server, init_stop).
init_bad_return() -> init_failure(init_bad_return_server, init_bad_return).
init_bad_action() -> init_failure(init_bad_action_server, init_bad_action).
init_crash() -> init_failure(init_crash_server, init_crash).

init_failure(Name, Argument) ->
    Result = direct_start(Name, Argument, []),
    {classify_init(Result), whereis(Name)}.

classify_init(ignore) -> ignore;
classify_init({error, init_error}) -> {error, init_error};
classify_init({error, init_stop}) -> {error, init_stop};
classify_init({error, {bad_return_value, init_bad_return}}) -> bad_return;
classify_init({error, {bad_return_value, {ok, {normal, 0, _}, {bad, action}}}}) -> bad_action;
classify_init({error, {init_crash, _Stacktrace}}) -> init_crash;
classify_init(Other) -> Other.

init_metadata() ->
    {ok, Pid} = direct_start(init_metadata_server, metadata, []),
    {metadata, [Parent | _], InitialCall} = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    {metadata, Parent =:= self(), InitialCall}.

direct_start(Name, Argument, Options) ->
    proc_lib:start(?MODULE, init_entry, [self(), Name, Argument, Options]).

init_entry(Starter, Name, Argument, Options) ->
    true = register(Name, self()),
    gen_server:init_it(Starter, Starter, {local, Name}, ?MODULE, Argument, Options).

wake_call() ->
    Pid = start_hibernating(2),
    {hibernate, 2, _} = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    call_woke.

wake_cast() ->
    Pid = start_hibernating(3),
    ok = gen_server:cast(Pid, increment),
    {hibernate, 4, _} = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    cast_woke.

wake_info() ->
    Pid = start_hibernating(4),
    Pid ! {info, self()},
    receive {info_seen, Pid, 5} -> ok end,
    {hibernate, 5, _} = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    info_woke.

wake_timeout() ->
    {ok, Pid} = gen_server:start(?MODULE, {hibernate, 5, self()}, []),
    receive after 1 -> ok end,
    armed = gen_server:call(Pid, arm_timeout),
    receive {timeout_seen, Pid, 6} -> ok end,
    ok = gen_server:stop(Pid),
    timeout_woke.

wake_system() ->
    Pid = start_hibernating(6),
    ok = sys:suspend(Pid),
    {hibernate, 6, _} = sys:get_state(Pid),
    {hibernate, 7, _} = sys:replace_state(Pid, fun({Mode, Count, Owner}) -> {Mode, Count + 1, Owner} end),
    ok = sys:change_code(Pid, ?MODULE, old, 2),
    ok = sys:resume(Pid),
    {hibernate, 9, _} = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    system_woke.

wake_malformed() ->
    Pid = start_hibernating(7),
    Ref = monitor(process, Pid),
    ok = gen_server:cast(Pid, malformed),
    receive {'DOWN', Ref, process, Pid, Reason} -> classify_wake_failure(Reason) end.

classify_wake_failure({bad_return_value, malformed_after_wake}) -> malformed_after_wake;
classify_wake_failure(Other) -> Other.

wake_parent_exit() ->
    {Helper, Ref} = spawn_monitor(?MODULE, wake_parent_helper, [self()]),
    Child = receive {hibernating_child, Helper, Pid} -> Pid end,
    ChildRef = monitor(process, Child),
    Helper ! crash,
    receive {'DOWN', Ref, process, Helper, parent_crash} -> ok end,
    receive {'DOWN', ChildRef, process, Child, Reason} -> {parent_exit, Reason} end.

wake_parent_helper(Parent) ->
    {ok, Pid} = gen_server:start_link(?MODULE, {hibernate, 8, self()}, []),
    receive after 1 -> ok end,
    Parent ! {hibernating_child, self(), Pid},
    receive crash -> exit(parent_crash) end.

abcast_all() ->
    {ok, Pid} = gen_server:start({local, remaining_abcast_all}, ?MODULE, {normal, 0, self()}, []),
    abcast = gen_server:abcast(remaining_abcast_all, increment),
    {normal, 1, _} = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    abcast_all.

abcast_nodes() ->
    {ok, Pid} = gen_server:start({local, remaining_abcast_nodes}, ?MODULE, {normal, 0, self()}, []),
    abcast = gen_server:abcast([node(), 'missing@invalid'], remaining_abcast_nodes, increment),
    {normal, 1, _} = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    abcast_nodes.

stop_custom() ->
    {ok, Pid} = gen_server:start(?MODULE, {normal, 0, self()}, []),
    ok = gen_server:stop(Pid, shutdown, 1000),
    receive {terminated, Pid, shutdown, 0} -> stopped_custom end.

stop_noproc() ->
    capture_exit(fun() -> gen_server:stop(whereis(remaining_absent), normal, 0) end).

system_get_replace_continue() ->
    {ok, Pid} = gen_server:start(?MODULE, {normal, 9, self()}, []),
    ok = sys:suspend(Pid),
    {normal, 9, _} = sys:get_state(Pid),
    {normal, 10, _} = sys:replace_state(Pid, fun({Mode, Count, Owner}) -> {Mode, Count + 1, Owner} end),
    ok = sys:resume(Pid),
    {normal, 10, _} = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    system_state.

system_terminate() ->
    {ok, Pid} = gen_server:start(?MODULE, {normal, 10, self()}, []),
    Ref = monitor(process, Pid),
    ok = sys:terminate(Pid, system_stopped),
    receive {terminated, Pid, system_stopped, 10} -> ok end,
    receive {'DOWN', Ref, process, Pid, system_stopped} -> system_terminated end.

hibernate_equivalence(Operations) ->
    {ok, Ordinary} = gen_server:start(?MODULE, {normal, 0, self()}, []),
    {ok, Hibernating} = gen_server:start(?MODULE, {hibernate, 0, self()}, []),
    receive after 1 -> ok end,
    run_operations(Ordinary, Operations),
    run_operations(Hibernating, Operations),
    {normal, OrdinaryState, _} = gen_server:call(Ordinary, get),
    {hibernate, HibernatingState, _} = gen_server:call(Hibernating, get),
    ok = gen_server:stop(Ordinary),
    ok = gen_server:stop(Hibernating),
    {OrdinaryState, HibernatingState}.

run_operations(_Pid, []) -> ok;
run_operations(Pid, [call | Rest]) -> _ = gen_server:call(Pid, {add, 2}), run_operations(Pid, Rest);
run_operations(Pid, [cast | Rest]) -> ok = gen_server:cast(Pid, increment), _ = gen_server:call(Pid, get), run_operations(Pid, Rest);
run_operations(Pid, [info | Rest]) -> Pid ! increment, _ = gen_server:call(Pid, get), run_operations(Pid, Rest);
run_operations(Pid, [system | Rest]) ->
    ok = sys:suspend(Pid),
    _ = sys:replace_state(Pid, fun({Mode, Count, Owner}) -> {Mode, Count + 3, Owner} end),
    ok = sys:resume(Pid),
    run_operations(Pid, Rest);
run_operations(Pid, [code_change | Rest]) ->
    ok = sys:suspend(Pid), ok = sys:change_code(Pid, ?MODULE, old, 1), ok = sys:resume(Pid),
    run_operations(Pid, Rest).

start_hibernating(State) ->
    {ok, Pid} = gen_server:start(?MODULE, {hibernate, State, self()}, []),
    receive after 1 -> ok end,
    Pid.

capture_exit(Fun) -> try Fun() catch exit:Reason -> {exit, normalize_exit(Reason)} end.
normalize_exit({Reason, {gen_server, stop, _}}) -> Reason;
normalize_exit(Reason) -> Reason.

init(ignore) -> ignore;
init(init_error) -> {error, init_error};
init(init_stop) -> {stop, init_stop};
init(init_bad_return) -> init_bad_return;
init(init_bad_action) -> {ok, {normal, 0, self()}, {bad, action}};
init(init_crash) -> erlang:error(init_crash);
init(metadata) -> {ok, {metadata, get('$ancestors'), get('$initial_call')}};
init(State) -> {ok, State, action(State)}.

action({hibernate, _, _}) -> hibernate;
action(_) -> infinity.

handle_call(get, _From, State) -> {reply, State, State, action(State)};
handle_call({add, Amount}, _From, {Mode, Count, Owner}) ->
    State = {Mode, Count + Amount, Owner}, {reply, State, State, action(State)};
handle_call(arm_timeout, _From, {_Mode, Count, Owner}) ->
    {reply, armed, {hibernate, Count, Owner}, 0}.

handle_cast(increment, {Mode, Count, Owner}) ->
    State = {Mode, Count + 1, Owner}, {noreply, State, action(State)};
handle_cast(malformed, _State) -> malformed_after_wake.

handle_info(increment, {Mode, Count, Owner}) ->
    State = {Mode, Count + 1, Owner}, {noreply, State, action(State)};
handle_info({info, To}, {Mode, Count, Owner}) ->
    State = {Mode, Count + 1, Owner}, To ! {info_seen, self(), Count + 1}, {noreply, State, action(State)};
handle_info(timeout, {_Mode, Count, Owner}) ->
    State = {hibernate, Count + 1, Owner}, Owner ! {timeout_seen, self(), Count + 1}, {noreply, State, hibernate};
handle_info(_Info, State) -> {noreply, State, action(State)}.

terminate(Reason, {Mode, Count, Owner}) when Mode =:= normal; Mode =:= hibernate ->
    Owner ! {terminated, self(), Reason, Count}, ok;
terminate(_Reason, _State) -> ok.
code_change(_Old, {Mode, Count, Owner}, Extra) -> {ok, {Mode, Count + Extra, Owner}}.
