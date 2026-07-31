#!/usr/bin/env escript

main(_) ->
    Q = queue:from_list([a, b, c]), R = queue:from_list([d, e]),
    Cases = [
        {is_queue, [Q]}, {is_empty, [queue:new()]}, {len, [Q]}, {to_list, [Q]},
        {from_list, [[a,b,c]]}, {member, [b,Q]}, {in_r, [z,Q]}, {out_r, [Q]},
        {get, [Q]}, {get_r, [Q]}, {peek, [Q]}, {peek_r, [Q]}, {drop, [Q]}, {drop_r, [Q]},
        {reverse, [Q]}, {join, [Q,R]}, {split, [2,Q]}, {delete, [b,Q]}, {delete_r, [b,Q]},
        {cons, [z,Q]}, {head, [Q]}, {tail, [Q]}, {snoc, [z,Q]}, {daeh, [Q]},
        {last, [Q]}, {liat, [Q]}, {lait, [Q]}, {init, [Q]}, {out, [Q]}, {in, [z,Q]},
        {new, []}, {module_info, []}, {module_info, [exports]}
    ],
    lists:foreach(fun emit/1, Cases).
emit({Function, Arguments}) ->
    Outcome = try {ok, apply(queue, Function, Arguments)} catch Class:Reason -> {raised, Class, Reason} end,
    io:format("case|~s|~B|~s|~s~n", [atom_to_list(Function), length(Arguments), encoded(Arguments), encoded(Outcome)]).
encoded(Term) -> base64:encode(term_to_binary(Term, [{minor_version, 2}])).
