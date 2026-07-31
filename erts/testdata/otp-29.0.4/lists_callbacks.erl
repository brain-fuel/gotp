-module(lists_callbacks).

-export([
    all/1, any/1, dropwhile/1, filter/1, filtermap/1, flatmap/1,
    foldl/1, foldr/1, foreach/1, keymap/1, map/1, mapfoldl/1,
    mapfoldr/1, merge/2, partition/1, rmerge/2, rumerge/2, search/1,
    sort/1, splitwith/1, takewhile/1, umerge/2, uniq/1, usort/1,
    zf/1, zipwith/2, zipwith/3, zipwith3/3, zipwith3/4
]).

all(Values) -> lists:all(fun(Value) -> Value > 0 end, Values).
any(Values) -> lists:any(fun(Value) -> Value > 2 end, Values).
dropwhile(Values) -> lists:dropwhile(fun(Value) -> Value < 3 end, Values).
filter(Values) -> lists:filter(fun(Value) -> Value > 2 end, Values).
filtermap(Values) -> lists:filtermap(fun(Value) when Value > 2 -> {true, Value * 10}; (_) -> false end, Values).
flatmap(Values) -> lists:flatmap(fun(Value) -> [Value, Value] end, Values).
foldl(Values) -> lists:foldl(fun(Value, Acc) -> Value + Acc end, 0, Values).
foldr(Values) -> lists:foldr(fun(Value, Acc) -> Value - Acc end, 0, Values).
foreach(Values) -> lists:foreach(fun(Value) -> Value end, Values).
keymap(Values) -> lists:keymap(fun(Value) -> Value * 10 end, 2, Values).
map(Values) -> lists:map(fun(Value) -> Value * 2 end, Values).
mapfoldl(Values) -> lists:mapfoldl(fun(Value, Acc) -> {Value * 2, Acc + Value} end, 0, Values).
mapfoldr(Values) -> lists:mapfoldr(fun(Value, Acc) -> {Value * 2, Acc + Value} end, 0, Values).
merge(Left, Right) -> lists:merge(fun(A, B) -> A =< B end, Left, Right).
partition(Values) -> lists:partition(fun(Value) -> Value < 3 end, Values).
rmerge(Left, Right) -> lists:rmerge(fun(A, B) -> A >= B end, Left, Right).
rumerge(Left, Right) -> lists:rumerge(fun(A, B) -> A >= B end, Left, Right).
search(Values) -> lists:search(fun(Value) -> Value =:= 2 end, Values).
sort(Values) -> lists:sort(fun(A, B) -> A =< B end, Values).
splitwith(Values) -> lists:splitwith(fun(Value) -> Value < 3 end, Values).
takewhile(Values) -> lists:takewhile(fun(Value) -> Value < 3 end, Values).
umerge(Left, Right) -> lists:umerge(fun(A, B) -> A =< B end, Left, Right).
uniq(Values) -> lists:uniq(fun({Key, _}) -> Key end, Values).
usort(Values) -> lists:usort(fun(A, B) -> A =< B end, Values).
zf(Values) -> lists:zf(fun(Value) when Value > 2 -> {true, Value * 10}; (_) -> false end, Values).
zipwith(Left, Right) -> lists:zipwith(fun(A, B) -> A + B end, Left, Right).
zipwith(Left, Right, How) -> lists:zipwith(fun(A, B) -> A + B end, Left, Right, How).
zipwith3(First, Second, Third) -> lists:zipwith3(fun(A, B, C) -> A + B + C end, First, Second, Third).
zipwith3(First, Second, Third, How) -> lists:zipwith3(fun(A, B, C) -> A + B + C end, First, Second, Third, How).
