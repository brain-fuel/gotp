#!/usr/bin/env escript

main(_) ->
    A = gb_sets:from_list([3,1,2,1]), B = gb_sets:from_list([2,4]),
    I = gb_sets:iterator(A), RI = gb_sets:iterator(A, reversed),
    Cases = [
        {is_empty,[gb_sets:new()]}, {size,[A]}, {is_equal,[A,gb_sets:from_list([1,2,3])]},
        {singleton,[7]}, {insert,[4,A]}, {balance,[A]}, {from_ordset,[[1,2,3]]},
        {del_element,[2,A]}, {delete_any,[8,A]}, {delete,[2,A]},
        {take_smallest,[A]}, {smallest,[A]}, {take_largest,[A]}, {largest,[A]},
        {smaller,[2,A]}, {larger,[2,A]}, {iterator,[A]}, {iterator,[A,reversed]},
        {iterator_from,[2,A]}, {iterator_from,[2,A,reversed]}, {next,[I]}, {next,[RI]},
        {union,[A,B]}, {union,[[A,B]]}, {intersection,[A,B]}, {intersection,[[A,B]]},
        {is_disjoint,[A,gb_sets:singleton(8)]}, {difference,[A,B]}, {is_subset,[B,gb_sets:union(A,B)]},
        {is_set,[A]}, {add,[4,A]}, {subtract,[A,B]}, {add_element,[4,A]},
        {is_element,[2,A]}, {to_list,[A]}, {is_member,[2,A]}, {new,[]}, {empty,[]},
        {from_list,[[3,1,2,1]]}, {module_info,[]}, {module_info,[exports]}
    ], lists:foreach(fun emit/1, Cases).
emit({Function,Arguments}) ->
    Outcome = try {ok,apply(gb_sets,Function,Arguments)} catch Class:Reason -> {raised,Class,Reason} end,
    io:format("case|~s|~B|~s|~s~n",[atom_to_list(Function),length(Arguments),encoded(Arguments),encoded(Outcome)]).
encoded(Term) -> base64:encode(term_to_binary(Term,[{minor_version,2}])).
