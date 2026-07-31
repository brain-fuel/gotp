#!/usr/bin/env escript
main(_) -> code:add_patha("/workspace/erts/testdata/otp-29.0.4"), lists:foreach(fun emit/1,[{filter,2},{map,2},{filtermap,2},{fold,3}]).
emit({F,A}) -> O=try {ok,apply(gb_sets_callbacks,F,[])} catch C:R->{raised,C,R} end, io:format("case|~s|0|~s|~B|~s|~s~n",[atom_to_list(F),atom_to_list(F),A,e([]),e(O)]).
e(T) -> base64:encode(term_to_binary(T,[{minor_version,2}])).
