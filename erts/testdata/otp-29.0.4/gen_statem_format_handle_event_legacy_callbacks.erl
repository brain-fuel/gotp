-module(gen_statem_format_handle_event_legacy_callbacks).
-behaviour(gen_statem).

-export([init/1, callback_mode/0, handle_event/4, format_status/2]).

init(Data) -> {ok, idle, Data}.
callback_mode() -> handle_event_function.
handle_event(_Type, _Event, _State, _Data) -> keep_state_and_data.
format_status(_Opt, [_PDict, State, Data]) ->
    [{data, [{"Legacy state", {legacy_state, State}},
             {"Legacy data", {legacy_data, Data}}]}].
