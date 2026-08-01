-module(gen_statem_format_state_functions_callbacks).
-behaviour(gen_statem).

-export([format_log_legacy/0, format_log_multi_unicode/0,
         format_log_single_depth/0, format_log_chars_limit/0,
         format_generated/4,
         malformed_log_report/0, malformed_status_data/0,
         status_normal/0, status_suspended/0, status_callback/0,
         status_callback_malformed/0, status_callback_legacy/0]).
-export([init/1, callback_mode/0, idle/3, format_status/1]).

format_log_legacy() -> gen_statem_format_fixture:format_log_legacy().
format_log_multi_unicode() -> gen_statem_format_fixture:format_log_multi_unicode().
format_log_single_depth() -> gen_statem_format_fixture:format_log_single_depth().
format_log_chars_limit() -> gen_statem_format_fixture:format_log_chars_limit().
format_generated(State, Data, Event, Variant) ->
    gen_statem_format_fixture:format_generated(State, Data, Event, Variant).
malformed_log_report() -> gen_statem_format_fixture:malformed_log_report().
malformed_status_data() -> gen_statem_format_fixture:malformed_status_data().
status_normal() -> gen_statem_format_fixture:status(?MODULE, statem_format_sf_normal, false).
status_suspended() -> gen_statem_format_fixture:status(?MODULE, statem_format_sf_suspended, true).
status_callback() -> gen_statem_format_fixture:status_callback(?MODULE, statem_format_sf_callback).
status_callback_malformed() ->
    gen_statem_format_fixture:status_callback_malformed(?MODULE, statem_format_sf_malformed).
status_callback_legacy() ->
    gen_statem_format_fixture:status_legacy(gen_statem_format_state_functions_legacy_callbacks,
                                            statem_format_sf_legacy).

init(Data) -> {ok, idle, Data}.
callback_mode() -> state_functions.
idle({call, From}, get, Data) -> {keep_state_and_data, [{reply, From, Data}]};
idle(_Type, _Event, _Data) -> keep_state_and_data.

format_status(#{data := malformed}) -> malformed;
format_status(Status = #{data := {secret, _}}) ->
    Status#{data => redacted,
            '$status' => {data, [{"State", maps:get(state, Status)},
                                  {"Data", redacted}]}};
format_status(Status) -> Status.
