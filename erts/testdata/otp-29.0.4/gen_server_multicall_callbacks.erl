-module(gen_server_multicall_callbacks).
-behaviour(gen_server).

-export([
    start_named/2,
    stop_named/1,
    multi_call_2/1,
    multi_call_3/1,
    multi_call_4/1,
    mixed_missing_name/1,
    unavailable_node/1,
    crashing_server/1,
    timeout_late_cleanup/1,
    duplicate_nodes/1,
    empty_nodes/0,
    reply_order/1,
    property_multi_call/2
]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_named(Name, Mode) -> gen_server:start({local, Name}, ?MODULE, Mode, []).
stop_named(Name) -> case whereis(Name) of undefined -> ok; Pid -> gen_server:stop(Pid) end.

multi_call_2(Nodes) ->
    normalize(gen_server:multi_call(multicall_all, identify), Nodes).

multi_call_3(Nodes) ->
    normalize(gen_server:multi_call(all_nodes(Nodes), multicall_three, identify), Nodes).

multi_call_4(Nodes) ->
    normalize(gen_server:multi_call(all_nodes(Nodes), multicall_four, identify, infinity), Nodes).

mixed_missing_name([Healthy, Missing | _]) ->
    normalize(gen_server:multi_call([Healthy, Missing], multicall_mixed, identify, infinity), [Healthy, Missing]).

unavailable_node(_Nodes) ->
    normalize(gen_server:multi_call(['unavailable@nohost'], multicall_absent, identify, 0), []).

crashing_server([Crash | _]) ->
    normalize(gen_server:multi_call([Crash], multicall_crash, identify, infinity), [Crash]).

timeout_late_cleanup([Late | _]) ->
    Result = normalize(gen_server:multi_call([Late], multicall_late, identify, 0), [Late]),
    receive after 30 -> ok end,
    Clean = receive _ -> contaminated after 0 -> clean end,
    {Result, Clean}.

duplicate_nodes([Node | _]) ->
    normalize(gen_server:multi_call([Node, Node], multicall_duplicate, identify, infinity), [Node]).

empty_nodes() -> normalize(gen_server:multi_call([], multicall_empty, identify, infinity), []).

reply_order(Nodes) ->
    normalize_order(gen_server:multi_call(all_nodes(Nodes), multicall_order, identify, infinity), Nodes).

property_multi_call(Nodes, Targets) ->
    Result = normalize_order(gen_server:multi_call(Targets, multicall_property, identify, infinity), Nodes),
    Clean = receive _ -> contaminated after 0 -> clean end,
    {Result, Clean}.

all_nodes(Nodes) -> [node() | Nodes].

normalize({Replies, BadNodes}, Nodes) ->
    {lists:sort([{role(Node, Nodes), normalize_reply(Reply, Nodes)} || {Node, Reply} <- Replies]),
     lists:sort([role(Node, Nodes) || Node <- BadNodes])}.

normalize_order({Replies, BadNodes}, Nodes) ->
    {[{role(Node, Nodes), normalize_reply(Reply, Nodes)} || {Node, Reply} <- Replies],
     [role(Node, Nodes) || Node <- BadNodes]}.

normalize_reply({served, Node}, Nodes) -> {served, role(Node, Nodes)};
normalize_reply(Reply, _Nodes) -> Reply.

role(Node, _Nodes) when Node =:= node() -> local;
role(Node, [Node | _]) -> first;
role(Node, [_First, Node | _]) -> second;
role('unavailable@nohost', _Nodes) -> unavailable;
role(_Node, _Nodes) -> other.

init(Mode) -> {ok, Mode}.

handle_call(identify, _From, crash) -> exit(multicall_crash);
handle_call(identify, From, late) ->
    spawn(fun() -> receive after 20 -> gen_server:reply(From, {served, node()}) end end),
    {noreply, late};
handle_call(identify, _From, State) -> {reply, {served, node()}, State}.

handle_cast(_Request, State) -> {noreply, State}.
handle_info(_Info, State) -> {noreply, State}.
