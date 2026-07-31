-module(ordsets_callbacks).
-export([fold/0, filter/0, map/0, filtermap/0]).

fold() -> ordsets:fold(fun add/2, 0, ordsets:from_list([1, 2, 3])).
filter() -> ordsets:filter(fun even/1, ordsets:from_list([1, 2, 3, 4])).
map() -> ordsets:map(fun negate/1, ordsets:from_list([1, 2, 3])).
filtermap() -> ordsets:filtermap(fun transform/1, ordsets:from_list([1, 2, 3, 4])).

add(Value, Accumulator) -> Value + Accumulator.
even(Value) -> Value rem 2 =:= 0.
negate(Value) -> 0 - Value.
transform(1) -> false;
transform(2) -> {true, 20};
transform(_) -> true.
