#!/usr/bin/env escript

main(_) ->
    Props = [enabled, {color, blue}, {path, [a, b]}, {path, c}, {color, red}, ignored],
    Cases = [
        {property, [{enabled, true}]}, {property, [enabled, false]},
        {compact, [[{enabled, true}, {color, blue}]]},
        {lookup, [color, Props]}, {lookup_all, [color, Props]},
        {is_defined, [enabled, Props]}, {get_all_values, [color, Props]},
        {append_values, [path, Props]}, {get_bool, [enabled, Props]},
        {get_keys, [Props]}, {delete, [color, Props]},
        {substitute_aliases, [[{color, colour}], Props]},
        {substitute_negations, [[{enabled, disabled}], Props]},
        {expand, [[{enabled, [fast, enabled]}], Props]},
        {normalize, [Props, [{aliases, [{color, colour}]}, {negations, [{enabled, disabled}]}]]},
        {split, [Props, [enabled, color]]},
        {to_map, [Props]}, {to_map, [Props, [{aliases, [{color, colour}]}]]},
        {from_map, [#{a => 1, b => 2}]},
        {get_value, [color, Props]}, {get_value, [missing, Props, fallback]},
        {unfold, [[enabled, {color, blue}]]},
        {module_info, []}, {module_info, [exports]}
    ],
    lists:foreach(fun emit/1, Cases).

emit({Function, Arguments}) ->
    Outcome = try {ok, apply(proplists, Function, Arguments)}
              catch Class:Reason -> {raised, Class, Reason}
              end,
    io:format("case|~s|~B|~s|~s~n", [atom_to_list(Function), length(Arguments), encoded(Arguments), encoded(Outcome)]).

encoded(Term) -> base64:encode(term_to_binary(Term, [{minor_version, 2}])).
