-module(gen_server_async_callbacks).
-behaviour(gen_server).

-export([
    success_send_wait/0,
    success_send_receive/0,
    send4_wait_collection/0,
    receive_collection/0,
    wait_timeout_retry/0,
    receive_abandon_late/0,
    crashed_server/0,
    named_server/0,
    out_of_order/0,
    check_direct/0,
    check_collection/0,
    property_collection/1
]).
-export([init/1, handle_call/3, handle_cast/2, handle_continue/2, handle_info/2]).

success_send_wait() ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    ReqId = gen_server:send_request(Pid, {reply, success}),
    Result = gen_server:wait_response(ReqId, infinity),
    ok = gen_server:stop(Pid),
    Result.

success_send_receive() ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    ReqId = gen_server:send_request(Pid, {reply, received}),
    Result = gen_server:receive_response(ReqId, infinity),
    ok = gen_server:stop(Pid),
    Result.

send4_wait_collection() ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    ReqIds = gen_server:send_request(Pid, {reply, collected}, label, gen_server:reqids_new()),
    {{reply, collected}, label, Remaining} = gen_server:wait_response(ReqIds, infinity, true),
    ok = gen_server:stop(Pid),
    {gen_server:reqids_size(ReqIds), gen_server:reqids_size(Remaining)}.

receive_collection() ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    ReqIds = gen_server:send_request(Pid, {reply, collected}, label, gen_server:reqids_new()),
    {{reply, collected}, label, Remaining} = gen_server:receive_response(ReqIds, infinity, true),
    ok = gen_server:stop(Pid),
    {gen_server:reqids_size(ReqIds), gen_server:reqids_size(Remaining)}.

wait_timeout_retry() ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    ReqId = gen_server:send_request(Pid, defer),
    timeout = gen_server:wait_response(ReqId, 0),
    released = gen_server:call(Pid, release),
    Result = gen_server:wait_response(ReqId, infinity),
    ok = gen_server:stop(Pid),
    Result.

receive_abandon_late() ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    ReqId = gen_server:send_request(Pid, defer),
    timeout = gen_server:receive_response(ReqId, 0),
    released = gen_server:call(Pid, release),
    Clean = receive _ -> contaminated after 0 -> clean end,
    ok = gen_server:stop(Pid),
    Clean.

crashed_server() ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    ReqId = gen_server:send_request(Pid, crash),
    case gen_server:wait_response(ReqId, infinity) of
        {error, {async_crash, Pid}} -> exact_async_crash;
        Other -> {unexpected, Other}
    end.

named_server() ->
    Name = gen_server_async_named,
    {ok, Pid} = gen_server:start({local, Name}, ?MODULE, [], []),
    ReqId = gen_server:send_request(Name, {reply, named}),
    Result = gen_server:receive_response(ReqId, infinity),
    ok = gen_server:stop(Pid),
    Result.

out_of_order() ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    C0 = gen_server:reqids_new(),
    C1 = gen_server:send_request(Pid, {ordered, first}, first, C0),
    C2 = gen_server:send_request(Pid, {ordered, second}, second, C1),
    {{reply, second}, second, C3} = gen_server:wait_response(C2, infinity, true),
    {{reply, first}, first, C4} = gen_server:wait_response(C3, infinity, true),
    ok = gen_server:stop(Pid),
    {gen_server:reqids_size(C2), gen_server:reqids_size(C3), gen_server:reqids_size(C4)}.

check_direct() ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    ReqId = gen_server:send_request(Pid, {reply, checked}),
    no_reply = gen_server:check_response(unrelated, ReqId),
    Result = receive Msg -> gen_server:check_response(Msg, ReqId) end,
    ok = gen_server:stop(Pid),
    Result.

check_collection() ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    ReqIds = gen_server:send_request(Pid, {reply, checked}, checked_label, gen_server:reqids_new()),
    no_reply = gen_server:check_response(unrelated, ReqIds, true),
    {{reply, checked}, checked_label, Remaining} = receive Msg -> gen_server:check_response(Msg, ReqIds, true) end,
    ok = gen_server:stop(Pid),
    gen_server:reqids_size(Remaining).

property_collection(Order) ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    C0 = gen_server:reqids_new(),
    Collection = lists:foldl(
        fun(Label, Acc) -> gen_server:send_request(Pid, {hold, Label}, Label, Acc) end,
        C0,
        lists:seq(1, length(Order))),
    released = gen_server:call(Pid, {release_order, Order}),
    {Labels, Sizes} = collect_responses(Collection, [], []),
    ok = gen_server:stop(Pid),
    {Labels, Sizes}.

collect_responses(Collection, Labels, Sizes) ->
    case gen_server:reqids_size(Collection) of
        0 -> {lists:reverse(Labels), lists:reverse(Sizes)};
        _ ->
            {{reply, Label}, Label, Remaining} = gen_server:wait_response(Collection, infinity, true),
            collect_responses(Remaining, [Label | Labels], [gen_server:reqids_size(Remaining) | Sizes])
    end.

init([]) -> {ok, none}.

handle_call({reply, Value}, _From, State) -> {reply, Value, State};
handle_call(defer, From, _State) -> {noreply, {deferred, From}};
handle_call(release, _From, {deferred, Deferred}) ->
    gen_server:reply(Deferred, late),
    {reply, released, none};
handle_call(crash, _From, _State) -> exit(async_crash);
handle_call({ordered, first}, From, _State) -> {noreply, {ordered, From}};
handle_call({ordered, second}, _From, {ordered, First}) ->
    {reply, second, First, {continue, release_first}};
handle_call({hold, Label}, From, State) -> {noreply, [{Label, From} | list_state(State)]};
handle_call({release_order, Order}, _From, State) ->
    lists:foreach(fun(Label) -> {Label, From} = lists:keyfind(Label, 1, State), gen_server:reply(From, Label) end, Order),
    {reply, released, none}.

handle_cast(_Request, State) -> {noreply, State}.
handle_continue(release_first, First) ->
    gen_server:reply(First, first),
    {noreply, none}.
handle_info(_Info, State) -> {noreply, State}.

list_state(none) -> [];
list_state(State) -> State.
