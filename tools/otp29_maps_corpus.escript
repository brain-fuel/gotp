#!/usr/bin/env escript

main(_) ->
    Iterator = maps:iterator(#{b => 2, a => 1}, ordered),
    Cases = [
		{new, []},
		{intersect, [#{a => 1, b => 2}, #{b => 3, c => 4}]},
        {size, [#{a => 1, b => 2}]},
        {iterator, [#{b => 2, a => 1}]},
        {iterator, [#{b => 2, a => 1}, ordered]},
        {is_iterator_valid, [Iterator]},
        {without, [[a, missing], #{a => 1, b => 2}]},
        {to_list, [#{b => 2, a => 1}]},
        {next, [Iterator]},
        {with, [[b, missing], #{a => 1, b => 2}]},
        {from_keys, [[a, b], 7]},
        {take, [a, #{a => 1, b => 2}]},
        {values, [#{b => 2, a => 1}]},
        {update, [a, 3, #{a => 1, b => 2}]},
        {remove, [a, #{a => 1, b => 2}]},
        {put, [c, 3, #{a => 1, b => 2}]},
        {merge, [#{a => 1, b => 2}, #{b => 9, c => 3}]},
        {keys, [#{b => 2, a => 1}]},
        {is_key, [a, #{a => 1}]},
        {from_list, [[{a, 1}, {b, 2}, {a, 3}]]},
        {get, [a, #{a => 1}]},
        {get, [missing, #{a => 1}, fallback]},
        {find, [missing, #{a => 1}]},
        {module_info, []},
        {module_info, [exports]}
    ],
    lists:foreach(fun emit/1, Cases).

emit({Function, Arguments}) ->
    Outcome = try {ok, apply(maps, Function, Arguments)}
              catch Class:Reason -> {raised, Class, Reason}
              end,
    io:format("case|~s|~B|~s|~s~n", [atom_to_list(Function), length(Arguments), encoded(Arguments), encoded(Outcome)]).

encoded(Term) -> base64:encode(term_to_binary(Term, [{minor_version, 2}])).
