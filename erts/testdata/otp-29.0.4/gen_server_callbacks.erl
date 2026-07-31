-module(gen_server_callbacks).
-behaviour(gen_server).
-export([exercise/0]).
-export([init/1,handle_call/3,handle_cast/2,handle_info/2,terminate/2,code_change/3]).

exercise() ->
    {ok, Pid} = gen_server:start(?MODULE, 1, []),
    Initial = gen_server:call(Pid, get),
    ok = gen_server:cast(Pid, {set, 9}),
    Updated = gen_server:call(Pid, get),
    Delayed = gen_server:call(Pid, {reply, acknowledged}),
    ok = gen_server:stop(Pid),
    {Initial, Updated, Delayed}.

init(State) -> {ok, State}.
handle_call(get, _From, State) -> {reply, State, State};
handle_call({reply, Value}, From, State) ->
    ok = gen_server:reply(From, Value),
    {noreply, State}.
handle_cast({set, Value}, _State) -> {noreply, Value}.
handle_info(_Message, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVersion, State, _Extra) -> {ok, State}.
