#!/usr/bin/env escript

main(_) ->
    T=gb_trees:from_list([{c,3},{a,1},{b,2}]), I=gb_trees:iterator(T), RI=gb_trees:iterator(T,reversed),
    Cases=[
      {empty,[]},{is_empty,[gb_trees:empty()]},{size,[T]},{lookup,[b,T]},{is_defined,[b,T]},
      {get,[b,T]},{update,[b,20,T]},{insert,[d,4,T]},{enter,[b,20,T]},{balance,[T]},
      {from_list,[[{c,3},{a,1},{b,2}]]},{from_orddict,[[{a,1},{b,2},{c,3}]]},
      {delete_any,[missing,T]},{delete,[b,T]},{take_any,[missing,T]},{take,[b,T]},
      {take_smallest,[T]},{smallest,[T]},{take_largest,[T]},{largest,[T]},
      {smaller,[b,T]},{larger,[b,T]},{to_list,[T]},{keys,[T]},{values,[T]},
      {iterator,[T]},{iterator,[T,reversed]},{iterator_from,[b,T]},{iterator_from,[b,T,reversed]},
      {next,[I]},{next,[RI]},{module_info,[]},{module_info,[exports]}],
    lists:foreach(fun emit/1,Cases).
emit({F,A}) -> O=try {ok,apply(gb_trees,F,A)} catch C:R->{raised,C,R} end, io:format("case|~s|~B|~s|~s~n",[atom_to_list(F),length(A),e(A),e(O)]).
e(T) -> base64:encode(term_to_binary(T,[{minor_version,2}])).
