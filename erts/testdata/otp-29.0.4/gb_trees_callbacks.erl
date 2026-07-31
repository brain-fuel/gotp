-module(gb_trees_callbacks).
-export([map/0]).
map() -> gb_trees:map(fun transform/2,gb_trees:from_list([{a,1},{b,2}])).
transform(a,V) -> V+10; transform(_,V) -> V+20.
