#!/usr/bin/env escript
%%! -noshell

main(_) ->
    true = string:find(erlang:system_info(system_version), "erts-17.0.4") =/= nomatch,
    io:format("# OTP-29.0.4 erts-17.0.4 erlang:29.0.4-alpine@sha256:a6e2d0c34adb0038f98953d89d82a501a26b8905027a8e840bf8851531de75d8~n"),
    Cases = [
        {append, [[[1,2],[3],[]]]}, {append, [[1,2],[3,4]]},
        {concat, [[alpha,"-",42]]}, {delete, [2,[1,2,3,2]]},
        {droplast, [[1,2,3]]}, {duplicate, [3,a]},
        {enumerate, [[a,b,c]]}, {enumerate, [4,[a,b]]}, {enumerate, [4,3,[a,b,c]]},
        {flatlength, [[1,[2,[3]],4]]}, {flatten, [[1,[2,[3]],4]]}, {flatten, [[1,[2]],[3,4]]},
        {join, [x,[a,b,c]]},
        {keydelete, [b,1,[{a,1},{b,2},{b,3}]]}, {keyfind, [b,1,[{a,1},{b,2}]]},
        {keymember, [b,1,[{a,1},{b,2}]]}, {keyreplace, [b,1,[{a,1},{b,2}],{b,9}]},
        {keysearch, [b,1,[{a,1},{b,2}]]}, {keystore, [c,1,[{a,1},{b,2}],{c,3}]},
        {keytake, [b,1,[{a,1},{b,2},{c,3}]]},
        {keymerge, [1,[{a,1},{c,3}],[{b,2},{d,4}]]}, {keysort, [1,[{c,3},{a,1},{b,2}]]},
        {ukeymerge, [1,[{a,1},{c,3}],[{a,9},{b,2}]]}, {ukeysort, [1,[{b,2},{a,1},{b,9}]]},
        {last, [[a,b,c]]}, {max, [[3,1,2]]}, {member, [2,[1,2,3]]}, {merge, [[[1,3],[2,4],[]]]},
        {merge, [[1,3],[2,4]]}, {merge3, [[1,4],[2,5],[3,6]]}, {min, [[3,1,2]]},
        {nth, [2,[a,b,c]]}, {nthtail, [2,[a,b,c,d]]}, {prefix, [[a,b],[a,b,c]]},
        {reverse, [[a,b,c]]}, {reverse, [[a,b],[c,d]]},
        {rkeymerge, [1,[{c,3},{a,1}],[{d,4},{b,2}]]}, {rmerge, [[4,2],[3,1]]},
        {rmerge3, [[6,3],[5,2],[4,1]]}, {rukeymerge, [1,[{c,3},{a,1}],[{d,4},{b,2}]]},
        {rumerge, [[4,2],[3,1]]}, {rumerge3, [[6,3],[5,2],[4,1]]},
        {seq, [1,5]}, {seq, [5,1,-2]}, {sort, [[3,1,2,1]]}, {split, [2,[a,b,c,d]]},
        {sublist, [[a,b,c,d],2]}, {sublist, [[a,b,c,d],2,2]}, {subtract, [[1,2,3,2],[2,3]]},
        {suffix, [[b,c],[a,b,c]]}, {sum, [[1,2,3,4]]},
        {umerge, [[[1,3],[2,3],[]]]}, {umerge, [[1,3],[2,3]]}, {umerge3, [[1,4],[2,4],[3,5]]},
        {uniq, [[a,b,a,c,b]]}, {unzip, [[{a,1},{b,2}]]}, {unzip3, [[{a,1,x},{b,2,y}]]},
        {usort, [[3,1,2,1,3]]}, {zip, [[a,b],[1,2]]}, {zip, [[a,b],[1],trim]},
        {zip3, [[a,b],[1,2],[x,y]]}, {zip3, [[a,b],[1],[x,y],trim]},
        {module_info, []}, {module_info, [exports]}
    ],
    lists:foreach(fun emit/1, Cases).

emit({Function, Arguments}) ->
    Outcome = try {ok, apply(lists, Function, Arguments)}
              catch Class:Reason -> {raised, Class, Reason}
              end,
    io:format("case|~s|~B|~s|~s~n", [atom_to_list(Function), length(Arguments), encoded(Arguments), encoded(Outcome)]).

encoded(Value) -> base64:encode(term_to_binary(Value, [{minor_version,2}])).
