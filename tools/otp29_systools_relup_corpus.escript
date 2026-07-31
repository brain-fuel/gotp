#!/usr/bin/env escript
%%! -noshell

main(_) ->
    System = erlang:system_info(system_version),
    true = string:find(System, "erts-17.0.4") =/= nomatch,
    io:format("# OTP-29.0.4 erts-17.0.4 erlang:29.0.4-alpine@sha256:a6e2d0c34adb0038f98953d89d82a501a26b8905027a8e840bf8851531de75d8~n"),
    selector("exact-first", "2.1.0", [{"2.1.0",[exact]},{<<"2\\..*">>,[pattern]}]),
    selector("regex-first", "2.1.0", [{<<"2\\..*">>,[pattern]},{"2.1.0",[exact]}]),
    selector("full-match", "12.1.0", [{<<"2\\.1">>,[partial]}]),
    selector("invalid-regex-skip", "2.1.0", [{<<"[">>,[bad]},{"2.1.0",[exact]}]),
    selector("malformed-skip", "2.1.0", [malformed,{"2.1.0",[exact]}]),
    selector("unicode", [16#3B2,$-, $2], [{<<"β-.*"/utf8>>,[unicode]}]),
    output("error-file-open", systools_relup:format_error({file_problem,{"demo.rel",{error,{open,enoent}}}})),
    output("error-warnings", systools_relup:format_error({warnings_treated_as_errors,[{erts_vsn_changed,{old,new}},pre_R15_emulator_upgrade,{other,3}]})),
    output("error-raw", systools_relup:format_error({odd,3})),
    output("warning-erts", systools_relup:format_warning({erts_vsn_changed,{old,new}})),
    output("warning-pre-r15", systools_relup:format_warning(pre_R15_emulator_upgrade)),
    output("warning-raw", systools_relup:format_warning({other,3})).

selector(ID, Base, Entries) ->
    Result = try systools_relup:appup_search_for_version(Base, Entries)
             catch error:badarg -> {error,badarg}
             end,
    io:format("selector|~s|~s|~s|~s~n", [ID, encoded(Base), encoded(Entries), encoded(Result)]).

output(ID, Value) ->
    io:format("diagnostic|~s|~s~n", [ID, base64:encode(iolist_to_binary(Value))]).

encoded(Value) -> base64:encode(term_to_binary(Value, [{minor_version,2}])).
