-module(maps_callbacks).
-export([intersect_with/0, update_with3/0, update_with4/0, filtermap/0,
         filter/0, merge_with/0, groups_from_list2/0, groups_from_list3/0,
         foreach/0, map/0, fold/0]).

intersect_with() -> maps:intersect_with(fun combine/3, #{a => 1, b => 2}, #{b => 3, c => 4}).
update_with3() -> maps:update_with(a, fun increment/1, #{a => 1}).
update_with4() -> maps:update_with(missing, fun increment/1, 8, #{a => 1}).
filtermap() -> maps:filtermap(fun filter_map/2, #{a => 1, b => 2, c => 3}).
filter() -> maps:filter(fun keep_even/2, #{a => 1, b => 2, c => 4}).
merge_with() -> maps:merge_with(fun combine/3, #{a => 1, b => 2}, #{b => 3, c => 4}).
groups_from_list2() -> maps:groups_from_list(fun parity/1, [1, 2, 3, 4]).
groups_from_list3() -> maps:groups_from_list(fun parity/1, fun square/1, [1, 2, 3, 4]).
foreach() -> maps:foreach(fun ignore_pair/2, #{a => 1, b => 2}).
map() -> maps:map(fun add_key_weight/2, #{a => 1, b => 2}).
fold() -> maps:fold(fun sum_entry/3, 0, #{a => 1, b => 2}).

combine(_, Left, Right) -> Left + Right.
increment(Value) -> Value + 1.
filter_map(a, Value) -> {true, Value * 10};
filter_map(b, _) -> false;
filter_map(_, _) -> true.
keep_even(_, Value) -> Value rem 2 =:= 0.
parity(Value) -> Value rem 2.
square(Value) -> Value * Value.
ignore_pair(_, _) -> ok.
add_key_weight(a, Value) -> Value + 10;
add_key_weight(_, Value) -> Value + 20.
sum_entry(_, Value, Accumulator) -> Value + Accumulator.
