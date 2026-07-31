-module(gb_sets_callbacks).
-export([filter/0,map/0,filtermap/0,fold/0]).

value() -> gb_sets:from_list([1,2,3,4]).
filter() -> gb_sets:filter(fun even/1,value()).
map() -> gb_sets:map(fun negate/1,value()).
filtermap() -> gb_sets:filtermap(fun transform/1,value()).
fold() -> gb_sets:fold(fun add/2,0,value()).
even(V) -> V rem 2 =:= 0.
negate(V) -> 0 - V.
transform(1) -> false; transform(2) -> {true,20}; transform(_) -> true.
add(V,A) -> V + A.
