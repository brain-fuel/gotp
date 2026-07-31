#!/usr/bin/env escript

main(_) ->
    R1=make_ref(), R2=make_ref(), C0=gen_server:reqids_new(),
    C1=gen_server:reqids_add(R1,first,C0), C2=gen_server:reqids_add(R2,second,C1),
    Cases=[
      {reqids_new,[]},{reqids_size,[C0]},{reqids_size,[C2]},
      {reqids_add,[R1,first,C0]},{reqids_to_list,[C2]},
      {behaviour_info,[callbacks]},{behaviour_info,[optional_callbacks]},
      {module_info,[]},{module_info,[exports]}],
    lists:foreach(fun emit/1,Cases).
emit({F,A}) -> O=try {ok,apply(gen_server,F,A)} catch C:R->{raised,C,R} end, io:format("case|~s|~B|~s|~s~n",[atom_to_list(F),length(A),e(A),e(O)]).
e(T) -> base64:encode(term_to_binary(T,[{minor_version,2}])).
