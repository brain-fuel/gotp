#!/usr/bin/env escript

main(_) ->
    logger:set_primary_config(level, emergency),
    Functions = [
        init_success, init_ignore, init_error, init_stop, init_bad_return,
        init_bad_action, init_crash, init_metadata,
        wake_call, wake_cast, wake_info, wake_timeout, wake_system,
        wake_malformed, wake_parent_exit, abcast_all, abcast_nodes,
        stop_custom, stop_noproc, system_get_replace_continue, system_terminate
    ],
    lists:foreach(fun emit/1, Functions).

emit(Function) ->
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Outcome = try {ok, apply(gen_server_remaining_callbacks, Function, [])}
                  catch Class:Reason -> {raised, Class, normalize_reason(Reason)}
                  end,
        Parent ! {self(), Outcome}
    end),
    Outcome = receive {Pid, Result} -> Result end,
    receive {'DOWN', Monitor, process, Pid, normal} -> ok end,
    io:format("case|~s|~s~n", [atom_to_list(Function), base64:encode(term_to_binary(Outcome, [deterministic]))]).

normalize_reason({Reason, Stacktrace}) when is_list(Stacktrace) -> Reason;
normalize_reason(Reason) -> Reason.
