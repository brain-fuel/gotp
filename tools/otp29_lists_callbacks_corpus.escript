#!/usr/bin/env escript
%%! -noshell

main(_) ->
    true = string:find(erlang:system_info(system_version), "erts-17.0.4") =/= nomatch,
    true = code:add_patha("/workspace/erts/testdata/otp-29.0.4"),
    {module, lists_callbacks} = code:load_file(lists_callbacks),
    io:format("# OTP-29.0.4 erts-17.0.4 erlang:29.0.4-alpine@sha256:a6e2d0c34adb0038f98953d89d82a501a26b8905027a8e840bf8851531de75d8~n"),
    Cases = [
        {all, [[1,2,3]]}, {any, [[1,2,3]]}, {dropwhile, [[1,2,3,1]]},
        {filter, [[1,2,3,4]]}, {filtermap, [[1,2,3,4]]}, {flatmap, [[1,2,3]]},
        {foldl, [[1,2,3]]}, {foldr, [[1,2,3]]}, {foreach, [[1,2,3]]},
        {keymap, [[{a,1},{b,2}]]}, {map, [[1,2,3]]}, {mapfoldl, [[1,2,3]]},
        {mapfoldr, [[1,2,3]]}, {merge, [[1,3],[2,4]]}, {partition, [[1,2,3,4]]},
        {rmerge, [[4,2],[3,1]]}, {rumerge, [[4,2],[3,1]]}, {search, [[1,2,3]]},
        {sort, [[3,1,2,1]]}, {splitwith, [[1,2,3,1]]}, {takewhile, [[1,2,3,1]]},
        {umerge, [[1,3],[2,3]]}, {uniq, [[{a,1},{b,2},{a,3}]]}, {usort, [[3,1,2,1]]},
        {zf, [[1,2,3,4]]}, {zipwith, [[1,2],[10,20]]}, {zipwith, [[1,2],[10],trim]},
        {zipwith3, [[1,2],[10,20],[100,200]]}, {zipwith3, [[1,2],[10],[100,200],trim]}
    ],
    lists:foreach(fun emit/1, Cases).

emit({Function, Arguments}) ->
    Outcome = try {ok, apply(lists_callbacks, Function, Arguments)}
              catch Class:Reason -> {raised, Class, Reason}
              end,
    TargetArity = case Function of
                      keymap -> 3;
                      foldl -> 3;
                      foldr -> 3;
                      mapfoldl -> 3;
                      mapfoldr -> 3;
                      _ -> length(Arguments) + 1
                  end,
    io:format("case|~s|~B|~B|~s|~s~n", [atom_to_list(Function), length(Arguments), TargetArity, encoded(Arguments), encoded(Outcome)]).

encoded(Value) -> base64:encode(term_to_binary(Value, [{minor_version,2}])).
