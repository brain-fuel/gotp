-module(gen_server_callbacks).
-behaviour(gen_server).
-export([exercise/0,start_link_3/0,start_link_4/0,start_monitor_3/0,
         start_monitor_4/0,timeout_alias/0,callback_crash/0,
         handle_info_continue/0,linked_parent/0,linked_parent_helper/1,
         named_duplicate/0,code_change_case/0]).
-export([init/1,handle_call/3,handle_cast/2,handle_continue/2,handle_info/2,terminate/2,code_change/3]).

exercise() ->
    {ok, Pid} = gen_server:start(?MODULE, 1, []),
    Initial = gen_server:call(Pid, get),
    ok = gen_server:cast(Pid, {set, 9}),
    Updated = gen_server:call(Pid, get),
    Delayed = gen_server:call(Pid, {reply, acknowledged}),
    ok = gen_server:stop(Pid),
    {Initial, Updated, Delayed}.

start_link_3() ->
    {ok, Pid} = gen_server:start_link(?MODULE, 1, []),
    Linked = lists:member(Pid, element(2, process_info(self(), links))),
    ok = gen_server:stop(Pid),
    {linked, Linked}.

start_link_4() ->
    {ok, Pid} = gen_server:start_link({local, lifecycle_linked}, ?MODULE, 1, []),
    Registered = whereis(lifecycle_linked) =:= Pid,
    ok = gen_server:stop(Pid),
    {linked_named, Registered}.

start_monitor_3() ->
    {ok, {Pid, Reference}} = gen_server:start_monitor(?MODULE, 1, []),
    ok = gen_server:stop(Pid),
    receive {'DOWN', Reference, process, Pid, Reason} -> {monitored, Reason} end.

start_monitor_4() ->
    {ok, {Pid, Reference}} = gen_server:start_monitor({local, lifecycle_monitored}, ?MODULE, 1, []),
    Registered = whereis(lifecycle_monitored) =:= Pid,
    ok = gen_server:stop(Pid),
    receive {'DOWN', Reference, process, Pid, Reason} -> {monitored_named, Registered, Reason} end.

timeout_alias() ->
    {ok, Pid} = gen_server:start(?MODULE, 1, []),
    TimedOut = try gen_server:call(Pid, late, 0) of
                   _ -> unexpected
               catch
                   exit:{timeout, _} -> timeout;
                   _:_ -> unexpected
               end,
    1 = gen_server:call(Pid, get),
    Leaked = receive _ -> leaked after 0 -> suppressed end,
    ok = gen_server:stop(Pid),
    {TimedOut, Leaked}.

callback_crash() ->
    {ok, {Pid, Reference}} = gen_server:start_monitor(?MODULE, 1, []),
    ok = gen_server:cast(Pid, crash),
    receive {'DOWN', Reference, process, Pid, Reason} -> Reason end.

handle_info_continue() ->
    {ok, Pid} = gen_server:start(?MODULE, {continue, self()}, []),
    Continued = receive ContinuedMessage = {continued, _} -> ContinuedMessage end,
    Pid ! {info, self()},
    Informed = receive InformedMessage = {informed, _} -> InformedMessage end,
    State = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    {Continued, Informed, State}.

linked_parent() ->
    {Helper, HelperReference} = spawn_monitor(?MODULE, linked_parent_helper, [self()]),
    receive {linked_child, Helper, Child} ->
        ChildReference = monitor(process, Child),
        Helper ! terminate_parent,
        receive {'DOWN', HelperReference, process, Helper, HelperReason} ->
            receive {'DOWN', ChildReference, process, Child, ChildReason} ->
                {HelperReason, ChildReason}
            end
        end
    end.

linked_parent_helper(Owner) ->
    {ok, Child} = gen_server:start_link(?MODULE, 1, []),
    Owner ! {linked_child, self(), Child},
    receive terminate_parent -> exit(parent_crash) end.

named_duplicate() ->
    {ok, Pid} = gen_server:start({local, lifecycle_duplicate}, ?MODULE, 1, []),
    Duplicate = gen_server:start({local, lifecycle_duplicate}, ?MODULE, 2, []),
    Registered = whereis(lifecycle_duplicate) =:= Pid,
    DuplicateMatches = case Duplicate of {error, {already_started, Pid}} -> true; _ -> false end,
    ok = gen_server:stop(Pid),
    {Registered, DuplicateMatches}.

code_change_case() ->
    {ok, Pid} = gen_server:start(?MODULE, 1, []),
    ok = sys:suspend(Pid),
    ok = sys:change_code(Pid, ?MODULE, old, 4),
    ok = sys:resume(Pid),
    State = gen_server:call(Pid, get),
    ok = gen_server:stop(Pid),
    State.

init({continue, Owner}) -> {ok, 0, {continue, Owner}};
init(State) -> {ok, State}.
handle_call(get, _From, State) -> {reply, State, State};
handle_call(late, From, State) ->
    self() ! {late_reply, From},
    {noreply, State};
handle_call({reply, Value}, From, State) ->
    ok = gen_server:reply(From, Value),
    {noreply, State}.
handle_cast({set, Value}, _State) -> {noreply, Value};
handle_cast(crash, _State) -> exit(callback_crash).
handle_continue(Owner, State) ->
    Owner ! {continued, State},
    {noreply, State + 1}.
handle_info({late_reply, From}, State) ->
    ok = gen_server:reply(From, late),
    {noreply, State};
handle_info({info, Owner}, State) ->
    Owner ! {informed, State},
    {noreply, State + 1};
handle_info(_Message, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVersion, State, Extra) -> {ok, State + Extra}.
