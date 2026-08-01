-module(gen_statem_format_state_functions_legacy_callbacks).
-behaviour(gen_statem).

-export([init/1, callback_mode/0, idle/3, format_status/2]).

init(Data) -> {ok, idle, Data}.
callback_mode() -> state_functions.
idle(_Type, _Event, _Data) -> keep_state_and_data.
format_status(_Opt, [_PDict, State, Data]) ->
    [{data, [{"Legacy state", {legacy_state, State}},
             {"Legacy data", {legacy_data, Data}}]}].
