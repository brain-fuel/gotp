#!/usr/bin/env escript

main(_) ->
    code:add_patha("/workspace/erts/testdata/otp-29.0.4"),
    lists:foreach(fun emit/1, [{fold,3},{filter,2},{map,2},{filtermap,2}]).
emit({Function, Arity}) ->
    Outcome = try {ok, apply(ordsets_callbacks, Function, [])} catch Class:Reason -> {raised, Class, Reason} end,
    io:format("case|~s|0|~s|~B|~s|~s~n", [atom_to_list(Function), atom_to_list(Function), Arity, encoded([]), encoded(Outcome)]).
encoded(Term) -> base64:encode(term_to_binary(Term, [{minor_version, 2}])).
