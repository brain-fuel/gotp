#!/usr/bin/env escript

main(_) ->
    A = ordsets:from_list([3, 1, 2, 1]), B = ordsets:from_list([2, 4]),
    Cases = [
        {new, []}, {is_set, [A]}, {size, [A]}, {is_empty, [[]]},
        {is_equal, [A, ordsets:from_list([1, 2, 3])]},
        {union, [[A, B]]}, {intersection, [[A, B]]},
        {is_disjoint, [A, ordsets:from_list([8, 9])]}, {is_subset, [B, ordsets:union(A, B)]},
        {intersection, [A, B]}, {union, [A, B]}, {subtract, [A, B]},
        {del_element, [2, A]}, {add_element, [4, A]}, {is_element, [2, A]},
        {to_list, [A]}, {from_list, [[3, 1, 2, 1]]},
        {module_info, []}, {module_info, [exports]}
    ],
    lists:foreach(fun emit/1, Cases).

emit({Function, Arguments}) ->
    Outcome = try {ok, apply(ordsets, Function, Arguments)} catch Class:Reason -> {raised, Class, Reason} end,
    io:format("case|~s|~B|~s|~s~n", [atom_to_list(Function), length(Arguments), encoded(Arguments), encoded(Outcome)]).
encoded(Term) -> base64:encode(term_to_binary(Term, [{minor_version, 2}])).
