#!/usr/bin/env escript

main(_) ->
    logger:set_primary_config(level, emergency),
    Cases = [
        {format_log_legacy, gen_server_format_callbacks, format_log_legacy},
        {format_log_multi_unicode, gen_server_format_callbacks, format_log_multi_unicode},
        {format_log_single_depth, gen_server_format_callbacks, format_log_single_depth},
        {format_log_chars_limit, gen_server_format_callbacks, format_log_chars_limit},
        {format_log_no_handle_info, gen_server_format_callbacks, format_log_no_handle_info},
        {malformed_log_report, gen_server_format_callbacks, malformed_log_report},
        {malformed_status_data, gen_server_format_callbacks, malformed_status_data},
        {status_normal, gen_server_format_callbacks, status_normal},
        {status_suspended, gen_server_format_callbacks, status_suspended},
        {status_callback, gen_server_format_callbacks, status_callback},
        {status_equivalence_suspend, gen_server_format_callbacks, status_equivalence_suspend},
        {status_callback_legacy, gen_server_format_legacy_callbacks, status_callback}
    ],
    lists:foreach(fun emit/1, Cases).

emit({Name, Module, Function}) ->
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Outcome = try {ok, apply(Module, Function, [])}
                  catch Class:Reason -> {raised, Class, normalize_reason(Reason)}
                  end,
        Parent ! {self(), Outcome}
    end),
    Outcome = receive {Pid, Result} -> Result end,
    receive {'DOWN', Monitor, process, Pid, normal} -> ok end,
    io:format("case|~s|~s~n", [atom_to_list(Name), base64:encode(term_to_binary(Outcome, [deterministic]))]).

normalize_reason({Reason, Stacktrace}) when is_list(Stacktrace) -> Reason;
normalize_reason(Reason) -> Reason.
