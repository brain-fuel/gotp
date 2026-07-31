#!/usr/bin/env escript
main(_) -> code:add_patha("/workspace/erts/testdata/otp-29.0.4"), O=try {ok,gb_trees_callbacks:map()} catch C:R->{raised,C,R} end, io:format("case|map|0|map|2|~s|~s~n",[e([]),e(O)]).
e(T) -> base64:encode(term_to_binary(T,[{minor_version,2}])).
