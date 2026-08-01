-module(gen_statem_type_fixture).
-behaviour(gen_statem).

-export([check/2, cases/0]).
-export([init/1, callback_mode/0, handle_event/4]).

check(init_result, Value) ->
    case gen_statem:start(?MODULE, {init_result, Value}, []) of
        {ok, Pid} -> alive(Pid);
        ignore when Value =:= ignore -> accepted;
        {error, Reason} when element(1, Value) =:= error; element(1, Value) =:= stop ->
            case Reason of _ -> accepted end;
        _ -> rejected
    end;
check(callback_mode_result, Value) -> check_start({callback_mode_result, Value}, []);
check(action, Value) -> check_start({action, Value}, []);
check(event_type, Value) -> check_start({event_type, Value}, []);
check(state_enter_result, Value) -> check_start({state_enter_result, Value}, []);
check(event_handler_result, Value) ->
    case gen_statem:start(?MODULE, normal, []) of
        {ok, Pid} ->
            gen_statem:cast(Pid, {return, Value}),
            alive(Pid);
        _ -> rejected
    end;
check(start_opt, Value) -> check_start(normal, [Value]);
check(server_name, Value) ->
    try gen_statem:start(Value, ?MODULE, normal, []) of
        {ok, Pid} -> alive(Pid);
        _ -> rejected
    catch _:_ -> rejected end.

check_start(Argument, Options) ->
    try gen_statem:start(?MODULE, Argument, Options) of
        {ok, Pid} -> alive(Pid);
        _ -> rejected
    catch _:_ -> rejected end.

alive(Pid) ->
    timer:sleep(1),
    try sys:get_status(Pid) of
        _ -> gen_statem:stop(Pid), accepted
    catch _:_ -> rejected end.

init({init_result, Value}) -> Value;
init({callback_mode_result, Value}) -> put(callback_mode_result, Value), {ok, idle, normal};
init({action, Value}) -> {ok, idle, normal, [Value]};
init({event_type, Value}) -> {ok, idle, normal, [{next_event, Value, payload}]};
init({state_enter_result, Value}) -> put(state_enter_result, Value), {ok, idle, normal};
init(normal) -> {ok, idle, normal}.

callback_mode() ->
    case get(callback_mode_result) of
        undefined ->
            case get(state_enter_result) of undefined -> handle_event_function; _ -> [handle_event_function, state_enter] end;
        Value -> Value
    end.

handle_event(enter, _Old, _State, _Data) ->
    case get(state_enter_result) of undefined -> keep_state_and_data; Value -> Value end;
handle_event(cast, {return, Value}, _State, _Data) -> Value;
handle_event(_Type, _Content, _State, _Data) -> keep_state_and_data.

cases() ->
    [
     {init_result, init_ok, {ok, idle, data}},
     {init_result, init_actions, {ok, idle, data, [{next_event, internal, payload}]}},
     {init_result, init_ignore, ignore},
     {init_result, init_bad_arity, {ok, idle}},
     {callback_mode_result, mode_state, state_functions},
     {callback_mode_result, mode_enter, [handle_event_function, state_enter]},
     {callback_mode_result, mode_bad, [handle_event_function, bad]},
     {action, action_next, {next_event, internal, payload}},
     {action, action_timeout, {state_timeout, 10, tick, [{abs, false}]}},
     {action, action_bad, {next_event, unknown, payload}},
     {event_type, event_internal, internal},
     {event_type, event_named_timeout, {timeout, heartbeat}},
     {event_type, event_bad, unknown},
     {event_handler_result, event_keep, keep_state_and_data},
     {event_handler_result, event_next, {next_state, active, data}},
     {event_handler_result, event_bad, {keep_state_and_data, invalid_action}},
     {state_enter_result, enter_keep, keep_state_and_data},
     {state_enter_result, enter_next, {next_state, idle, data, [hibernate]}},
     {state_enter_result, enter_bad_action, {keep_state_and_data, [postpone]}},
     {start_opt, start_timeout, {timeout, 100}},
     {start_opt, hibernate_after, {hibernate_after, 100}},
     {server_name, local_name, {local, gen_statem_type_fixture_name}},
     {server_name, server_name_bad, {local, 7}}
    ].
