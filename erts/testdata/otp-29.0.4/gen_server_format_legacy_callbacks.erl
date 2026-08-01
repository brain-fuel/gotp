-module(gen_server_format_legacy_callbacks).
-behaviour(gen_server).

-export([status_callback/0]).
-export([init/1, handle_call/3, handle_cast/2, format_status/2]).

status_callback() ->
    {ok, Pid} = gen_server:start({local, format_status_legacy}, ?MODULE, 17, []),
    Status = sys:get_status(Pid),
    ok = gen_server:stop(Pid),
    normalize(Status).

init(State) -> {ok, State}.
handle_call(get, _From, State) -> {reply, State, State}.
handle_cast(_Message, State) -> {noreply, State}.
format_status(_Opt, [_PDict, State]) -> [{data, [{"Legacy state", {legacy_state, State}}]}].

normalize({status, Pid, Module, [PDict | Rest]}) ->
    {status, normalize(Pid), normalize(Module), [lists:sort(normalize(PDict)) | normalize(Rest)]};
normalize(Term) when is_pid(Term) -> pid;
normalize(Term) when is_reference(Term) -> reference;
normalize(Term) when is_tuple(Term) -> list_to_tuple([normalize(Value) || Value <- tuple_to_list(Term)]);
normalize(Term) when is_list(Term) -> [normalize(Value) || Value <- Term];
normalize(Term) when is_map(Term) -> maps:map(fun(_Key, Value) -> normalize(Value) end, Term);
normalize(Term) -> Term.
