#!/usr/bin/env escript

main(_) ->
    logger:set_primary_config(level, emergency),
    {ok, _} = net_kernel:start(['oracle@localhost', shortnames]),
    BeamDir = filename:absname("."),
    {ok, PeerA, NodeA} = peer:start_link(#{name => multi_a, args => ["-pa", BeamDir]}),
    {ok, PeerB, NodeB} = peer:start_link(#{name => multi_b, args => ["-pa", BeamDir]}),
    Nodes = [NodeA, NodeB],
    Cases = [
        {multi_call_2, [Nodes]},
        {multi_call_3, [Nodes]},
        {multi_call_4, [Nodes]},
        {mixed_missing_name, [Nodes]},
        {unavailable_node, [Nodes]},
        {crashing_server, [Nodes]},
        {timeout_late_cleanup, [Nodes]},
        {duplicate_nodes, [Nodes]},
        {empty_nodes, []},
        {reply_order, [Nodes]}
    ],
    lists:foreach(fun emit/1, Cases),
    peer:stop(PeerA), peer:stop(PeerB).

emit({Function, Arguments}) ->
    Nodes = case Arguments of [Found] when is_list(Found) -> Found; _ -> [] end,
    prepare(Function, Nodes),
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Outcome = try {ok, apply(gen_server_multicall_callbacks, Function, Arguments)}
                  catch Class:Reason -> {raised, Class, Reason}
                  end,
        Parent ! {self(), Outcome}
    end),
    Outcome = receive {Pid, Result} -> Result end,
    receive {'DOWN', Monitor, process, Pid, normal} -> ok end,
    io:format("case|~s|~s~n", [atom_to_list(Function), encode(Outcome)]),
    cleanup(Function, Nodes).

prepare(multi_call_2, Nodes) -> start_everywhere(multicall_all, normal, Nodes);
prepare(multi_call_3, Nodes) -> start_everywhere(multicall_three, normal, Nodes);
prepare(multi_call_4, Nodes) -> start_everywhere(multicall_four, normal, Nodes);
prepare(mixed_missing_name, [Healthy | _]) -> start_remote(Healthy, multicall_mixed, normal);
prepare(crashing_server, [Crash | _]) -> start_remote(Crash, multicall_crash, crash);
prepare(timeout_late_cleanup, [Late | _]) -> start_remote(Late, multicall_late, late);
prepare(duplicate_nodes, [Node | _]) -> start_remote(Node, multicall_duplicate, normal);
prepare(reply_order, Nodes) -> start_everywhere(multicall_order, normal, Nodes);
prepare(_, _) -> ok.

cleanup(multi_call_2, Nodes) -> stop_everywhere(multicall_all, Nodes);
cleanup(multi_call_3, Nodes) -> stop_everywhere(multicall_three, Nodes);
cleanup(multi_call_4, Nodes) -> stop_everywhere(multicall_four, Nodes);
cleanup(mixed_missing_name, [Healthy | _]) -> stop_remote(Healthy, multicall_mixed);
cleanup(timeout_late_cleanup, [Late | _]) -> stop_remote(Late, multicall_late);
cleanup(duplicate_nodes, [Node | _]) -> stop_remote(Node, multicall_duplicate);
cleanup(reply_order, Nodes) -> stop_everywhere(multicall_order, Nodes);
cleanup(_, _) -> ok.

start_everywhere(Name, Mode, Nodes) ->
    {ok, _} = gen_server_multicall_callbacks:start_named(Name, Mode),
    lists:foreach(fun(Node) -> start_remote(Node, Name, Mode) end, Nodes).

stop_everywhere(Name, Nodes) ->
    gen_server_multicall_callbacks:stop_named(Name),
    lists:foreach(fun(Node) -> stop_remote(Node, Name) end, Nodes).

start_remote(Node, Name, Mode) -> {ok, _} = rpc:call(Node, gen_server_multicall_callbacks, start_named, [Name, Mode]), ok.
stop_remote(Node, Name) -> rpc:call(Node, gen_server_multicall_callbacks, stop_named, [Name]), ok.

encode(Term) -> base64:encode(term_to_binary(Term, [{minor_version, 2}])).
