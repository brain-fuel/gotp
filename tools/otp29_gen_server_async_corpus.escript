#!/usr/bin/env escript

main(_) ->
    logger:set_primary_config(level, emergency),
    Functions = [
        success_send_wait,
        success_send_receive,
        send4_wait_collection,
        receive_collection,
        wait_timeout_retry,
        receive_abandon_late,
        crashed_server,
        named_server,
        out_of_order,
        check_direct,
        check_collection
    ],
    lists:foreach(fun emit/1, Functions).

emit(Function) ->
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Outcome = try {ok, apply(gen_server_async_callbacks, Function, [])}
                  catch Class:Reason -> {raised, Class, Reason}
                  end,
        Parent ! {self(), Outcome}
    end),
    Outcome = receive {Pid, Result} -> Result end,
    receive {'DOWN', Monitor, process, Pid, normal} -> ok end,
    io:format("case|~s|~s~n", [atom_to_list(Function), encode(Outcome)]).

encode(Term) -> base64:encode(term_to_binary(Term, [{minor_version, 2}])).
