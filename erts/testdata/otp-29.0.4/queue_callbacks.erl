-module(queue_callbacks).
-export([filter/0, filtermap/0, fold/0, any/0, all/0, delete_with/0, delete_with_r/0]).

queue_value() -> queue:from_list([1,2,3,4]).
filter() -> queue:filter(fun even/1, queue_value()).
filtermap() -> queue:filtermap(fun transform/1, queue_value()).
fold() -> queue:fold(fun add/2, 0, queue_value()).
any() -> queue:any(fun even/1, queue_value()).
all() -> queue:all(fun positive/1, queue_value()).
delete_with() -> queue:delete_with(fun even/1, queue_value()).
delete_with_r() -> queue:delete_with_r(fun even/1, queue_value()).

even(Value) -> Value rem 2 =:= 0.
positive(Value) -> Value > 0.
transform(1) -> false;
transform(2) -> {true, 20};
transform(_) -> true.
add(Value, Accumulator) -> Value + Accumulator.
