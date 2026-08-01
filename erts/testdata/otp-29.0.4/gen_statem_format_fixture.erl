-module(gen_statem_format_fixture).

-export([format_log_legacy/0, format_log_multi_unicode/0,
         format_log_single_depth/0, format_log_chars_limit/0,
         format_generated/4,
         malformed_log_report/0, malformed_status_data/0,
         status/3, status_callback/2, status_callback_malformed/2,
         status_legacy/2, status_projection/1]).

format_log_legacy() ->
    {Format, Args} = gen_statem:format_log(terminate_report()),
    unicode:characters_to_binary(io_lib:format(Format, Args)).

format_log_multi_unicode() ->
    unicode:characters_to_binary(gen_statem:format_log(terminate_report(), #{})).

format_log_single_depth() ->
    unicode:characters_to_binary(gen_statem:format_log(terminate_report(),
                                                       #{single_line => true, depth => 2})).

format_log_chars_limit() ->
    unicode:characters_to_binary(gen_statem:format_log(terminate_report(),
                                                       #{chars_limit => 96})).

format_generated(State, Data, Event, Variant) ->
    Options = case Variant of
                  0 -> #{};
                  1 -> #{single_line => true};
                  2 -> #{depth => 3};
                  _ -> #{single_line => true, depth => 4, chars_limit => 128}
              end,
    Report = (terminate_report())#{state => {State, Data}, queue => [Event]},
    unicode:characters_to_binary(gen_statem:format_log(Report, Options)).

malformed_log_report() -> capture(fun() -> gen_statem:format_log(#{}, #{}) end).
malformed_status_data() -> capture(fun() -> gen_statem:format_status(normal, []) end).

status(Module, Name, Suspended) ->
    {ok, Pid} = gen_statem:start({local, Name}, Module, normal, []),
    case Suspended of true -> ok = sys:suspend(Pid); false -> ok end,
    Status = normalize_status(sys:get_status(Pid)),
    case Suspended of true -> ok = sys:resume(Pid); false -> ok end,
    ok = gen_statem:stop(Pid),
    Status.

status_callback(Module, Name) ->
    {ok, Pid} = gen_statem:start({local, Name}, Module, {secret, <<"token">>}, []),
    Projection = status_projection(sys:get_status(Pid)),
    ok = gen_statem:stop(Pid),
    Projection.

status_callback_malformed(Module, Name) ->
    {ok, Pid} = gen_statem:start({local, Name}, Module, malformed, []),
    Projection = status_projection(sys:get_status(Pid)),
    ok = gen_statem:stop(Pid),
    Projection.

status_legacy(Module, Name) ->
    {ok, Pid} = gen_statem:start({local, Name}, Module, legacy, []),
    Status = normalize_status(sys:get_status(Pid)),
    ok = gen_statem:stop(Pid),
    Status.

terminate_report() ->
    #{label => {gen_statem, terminate},
      name => format_machine,
      queue => [{call, {client, tag}}, {unicode, "lambda lambda", [955,38634,1,2,3,4]}],
      postponed => [{internal, {postponed, secret}}],
      modules => [gen_statem_format_fixture],
      callback_mode => handle_event_function,
      state_enter => true,
      state => {active, {public, [115,110,111,119,32,38634], redacted,
                         {one, {two, {three, four}}}}},
      timeouts => {2, [{{timeout, heartbeat}, 50}, {state_timeout, 100}]},
      reason => {error, {badmatch, {crash, [38634]}},
                 [{gen_statem_format_fixture, handle_event, 4, [{line, 91}]}]},
      log => [{in, request}, {out, reply, client, #{count => 2}}],
      client_info => undefined,
      process_label => {worker, "format snow"}}.

capture(Fun) ->
    try {ok, Fun()}
    catch Class:Reason -> {raised, Class, Reason}
    end.

normalize_status({status, Pid, Module, [PDict | Rest]}) ->
    {status, normalize_status(Pid), normalize_status(Module),
     [lists:sort(normalize_status(PDict)) | normalize_status(Rest)]};
normalize_status(Term) when is_pid(Term) -> pid;
normalize_status(Term) when is_reference(Term) -> reference;
normalize_status(Term) when is_tuple(Term) ->
    list_to_tuple([normalize_status(Value) || Value <- tuple_to_list(Term)]);
normalize_status(Term) when is_list(Term) -> [normalize_status(Value) || Value <- Term];
normalize_status(Term) when is_map(Term) ->
    maps:map(fun(_Key, Value) -> normalize_status(Value) end, Term);
normalize_status(Term) -> Term.

status_projection(Status) ->
    {status, _Pid, _Module, [_PDict, _SysState, _Parent, _Debug, Formatted]} =
        normalize_status(Status),
    [Entry || Entry <- Formatted, element(1, Entry) =/= header].
