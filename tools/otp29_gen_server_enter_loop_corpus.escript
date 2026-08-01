#!/usr/bin/env escript

main(_) ->
    logger:set_primary_config(level, emergency),
    Functions = [
		proc_lib_ancestry,
        enter3_lifecycle,
        enter4_registered,
        enter4_timeout,
        enter4_continue,
        enter5_continue,
        enter5_hibernate,
        unsolicited_info,
        code_change_system,
        global_registered,
        via_registered,
        invalid_non_proc,
        invalid_local_missing,
        invalid_local_wrong,
        invalid_bad_action,
        linked_parent
    ],
    lists:foreach(fun emit/1, Functions).

emit(Function) ->
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Outcome = try {ok, apply(gen_server_enter_loop_callbacks, Function, [])}
                  catch Class:Reason -> {raised, Class, normalize_reason(Reason)}
                  end,
        Parent ! {self(), Outcome}
    end),
    Outcome = receive {Pid, Result} -> Result end,
    receive {'DOWN', Monitor, process, Pid, normal} -> ok end,
    io:format("case|~s|~s~n", [atom_to_list(Function), encode(Outcome)]).

normalize_reason({Reason, Stack}) when is_list(Stack) -> Reason;
normalize_reason(Reason) -> Reason.

encode(Term) -> base64:encode(term_to_binary(Term, [{minor_version, 2}])).
