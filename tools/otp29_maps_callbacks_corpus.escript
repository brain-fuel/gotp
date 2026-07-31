#!/usr/bin/env escript

main(_) ->
    code:add_patha("/workspace/erts/testdata/otp-29.0.4"),
    Cases = [
        {intersect_with, intersect_with, 3},
        {update_with3, update_with, 3},
        {update_with4, update_with, 4},
        {filtermap, filtermap, 2},
        {filter, filter, 2},
        {merge_with, merge_with, 3},
        {groups_from_list2, groups_from_list, 2},
        {groups_from_list3, groups_from_list, 3},
        {foreach, foreach, 2},
        {map, map, 2},
        {fold, fold, 3}
    ],
    lists:foreach(fun emit/1, Cases).

emit({Wrapper, Target, TargetArity}) ->
    Outcome = try {ok, apply(maps_callbacks, Wrapper, [])}
              catch Class:Reason -> {raised, Class, Reason}
              end,
    io:format("case|~s|0|~s|~B|~s|~s~n", [atom_to_list(Wrapper), atom_to_list(Target), TargetArity, encoded([]), encoded(Outcome)]).

encoded(Term) -> base64:encode(term_to_binary(Term, [{minor_version, 2}])).
