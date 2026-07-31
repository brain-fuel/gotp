#!/usr/bin/env escript

main(_) ->
    code:add_patha("/workspace/erts/testdata/otp-29.0.4"),
    Outcome = try {ok, gen_server_callbacks:exercise()}
              catch Class:Reason -> {raised, Class, Reason}
              end,
    io:format("case|exercise|~s~n", [encoded(Outcome)]).

encoded(Term) -> base64:encode(term_to_binary(Term, [{minor_version, 2}])).
