-module(gen_server_format_callbacks).
-behaviour(gen_server).

-export([
    format_log_legacy/0,
    format_log_multi_unicode/0,
    format_log_single_depth/0,
    format_log_chars_limit/0,
    format_log_no_handle_info/0,
    malformed_log_report/0,
    malformed_status_data/0,
    status_normal/0,
    status_suspended/0,
    status_callback/0,
    status_equivalence/1,
    status_equivalence_suspend/0,
    entered/2
]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, format_status/1]).

format_log_legacy() ->
    {Format, Args} = gen_server:format_log(terminate_report()),
    unicode:characters_to_binary(io_lib:format(Format, Args)).

format_log_multi_unicode() ->
    unicode:characters_to_binary(gen_server:format_log(terminate_report(), #{})).

format_log_single_depth() ->
    unicode:characters_to_binary(gen_server:format_log(terminate_report(), #{single_line => true, depth => 2})).

format_log_chars_limit() ->
    unicode:characters_to_binary(gen_server:format_log(terminate_report(), #{chars_limit => 96})).

format_log_no_handle_info() ->
    Report = #{label => {gen_server, no_handle_info}, module => ?MODULE,
               message => {unhandled, "snow 雪", [955,38634,1,2,3,4]}},
    unicode:characters_to_binary(gen_server:format_log(Report, #{single_line => true})).

malformed_log_report() -> capture(fun() -> gen_server:format_log(#{} , #{}) end).
malformed_status_data() -> capture(fun() -> gen_server:format_status(normal, []) end).

status_normal() ->
    {ok, Pid} = gen_server:start({local, format_status_normal}, ?MODULE, 3, []),
    Status = sys:get_status(Pid),
    ok = gen_server:stop(Pid),
    normalize_status(Status).

status_suspended() ->
    {ok, Pid} = gen_server:start({local, format_status_suspended}, ?MODULE, 4, []),
    ok = sys:suspend(Pid),
    Status = sys:get_status(Pid),
    ok = sys:resume(Pid),
    ok = gen_server:stop(Pid),
    normalize_status(Status).

status_callback() ->
    {ok, Pid} = gen_server:start({local, format_status_callback}, ?MODULE, 5, []),
    Status = sys:get_status(Pid),
    ok = gen_server:stop(Pid),
    status_projection(Status).

status_equivalence(Operations) ->
    {ok, Ordinary} = gen_server:start(?MODULE, 0, []),
    {ok, Entered} = proc_lib:start(?MODULE, entered, [self(), 0]),
    run_operations(Ordinary, Operations),
    run_operations(Entered, Operations),
    OrdinaryStatus = status_projection(sys:get_status(Ordinary)),
    EnteredStatus = status_projection(sys:get_status(Entered)),
    ok = gen_server:stop(Ordinary),
    ok = gen_server:stop(Entered),
    case OrdinaryStatus of
        EnteredStatus -> equivalent;
        _ -> {different, OrdinaryStatus, EnteredStatus}
    end.

status_equivalence_suspend() -> status_equivalence([increment, suspend]).

entered(Parent, State) ->
    proc_lib:init_ack(Parent, {ok, self()}),
    gen_server:enter_loop(?MODULE, [], State).

run_operations(_Pid, []) -> ok;
run_operations(Pid, [increment | Rest]) ->
    ok = gen_server:cast(Pid, increment),
    _ = gen_server:call(Pid, get),
    run_operations(Pid, Rest);
run_operations(Pid, [info | Rest]) ->
    Pid ! increment,
    _ = gen_server:call(Pid, get),
    run_operations(Pid, Rest);
run_operations(Pid, [suspend | Rest]) ->
    ok = sys:suspend(Pid),
    _ = sys:get_status(Pid),
    ok = sys:resume(Pid),
    run_operations(Pid, Rest);
run_operations(Pid, [code_change | Rest]) ->
    ok = sys:suspend(Pid),
    ok = sys:change_code(Pid, ?MODULE, old, 1),
    ok = sys:resume(Pid),
    run_operations(Pid, Rest).

terminate_report() ->
    #{label => {gen_server, terminate},
      name => format_server,
      last_message => {unicode, "λ雪", [955,38634,1,2,3,4]},
      state => {terminating, {one, {two, {three, four}}}},
      log => [{in, request}, {out, reply, client, #{count => 2}}],
      reason => {{badmatch, {crash, "雪"}}, [{?MODULE, handle_call, 3, [{line, 91}]}]},
      client_info => undefined,
      process_label => {worker, "format 雪"}}.

capture(Fun) ->
    try {ok, Fun()}
    catch Class:Reason -> {raised, Class, Reason}
    end.

normalize_status({status, Pid, Module, [PDict | Rest]}) ->
    {status, normalize_status(Pid), normalize_status(Module),
     [lists:sort(normalize_status(PDict)) | normalize_status(Rest)]};
normalize_status(Term) when is_pid(Term) -> pid;
normalize_status(Term) when is_reference(Term) -> reference;
normalize_status(Term) when is_tuple(Term) -> list_to_tuple([normalize_status(Value) || Value <- tuple_to_list(Term)]);
normalize_status(Term) when is_list(Term) -> [normalize_status(Value) || Value <- Term];
normalize_status(Term) when is_map(Term) -> maps:map(fun(_Key, Value) -> normalize_status(Value) end, Term);
normalize_status(Term) -> Term.

status_projection(Status) ->
    {status, _Pid, _Module, [_PDict, _SysState, _Parent, _Debug, Formatted]} = normalize_status(Status),
    [Entry || Entry <- Formatted, element(1, Entry) =/= header].

init(State) -> {ok, State}.
handle_call(get, _From, State) -> {reply, State, State}.
handle_cast(increment, State) -> {noreply, State + 1}.
handle_info(increment, State) -> {noreply, State + 1};
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_Old, State, Extra) -> {ok, State + Extra}.
format_status(Status) ->
    State = maps:get(state, Status),
    Status#{state => {callback_state, State},
            '$status' => {data, [{"Callback state", {callback_state, State}}]}}.
