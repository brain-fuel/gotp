#!/usr/bin/env escript

main(_) ->
    code:add_patha("/workspace/erts/testdata/otp-29.0.4"),
	logger:set_primary_config(level, emergency),
    Functions = [exercise,start_link_3,start_link_4,start_monitor_3,
                 start_monitor_4,timeout_alias,callback_crash,
                 handle_info_continue,linked_parent,named_duplicate,
                 code_change_case],
    lists:foreach(fun(Function) ->
        Outcome = try {ok, apply(gen_server_callbacks, Function, [])}
                  catch Class:Reason -> {raised, Class, Reason}
                  end,
        io:format("case|~s|~s~n", [Function, encoded(Outcome)])
    end, Functions).

encoded(Term) -> base64:encode(term_to_binary(Term, [{minor_version, 2}])).
