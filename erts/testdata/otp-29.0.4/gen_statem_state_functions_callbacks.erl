-module(gen_statem_state_functions_callbacks).
-behaviour(gen_statem).
-export([lifecycle/0,construction/0,events/0,timeouts/0,event_timeout/0,system/0,termination/0,replies/0,hibernate/0,switch/0,callback_stack/0,enter4/0,enter5/0,enter6/0,linked_parent/0,invalid_action/0,invalid_timeout/0,invalid_next_event/0,crash/0,malformed/0,trace/1,enter_init/2]).
-export([init/1,callback_mode/0,idle/3,active/3,terminate/3,code_change/4]).
lifecycle()->gen_statem_fixture:run(?MODULE,lifecycle).
construction()->gen_statem_fixture:run(?MODULE,construction).
events()->gen_statem_fixture:run(?MODULE,events).
timeouts()->gen_statem_fixture:run(?MODULE,timeouts).
event_timeout()->gen_statem_fixture:run(?MODULE,event_timeout).
system()->gen_statem_fixture:run(?MODULE,system).
termination()->gen_statem_fixture:run(?MODULE,termination).
crash()->gen_statem_fixture:run(?MODULE,crash).
malformed()->gen_statem_fixture:run(?MODULE,malformed).
replies()->gen_statem_fixture:run(?MODULE,replies).
hibernate()->gen_statem_fixture:run(?MODULE,hibernate).
switch()->gen_statem_fixture:run(?MODULE,switch).
callback_stack()->gen_statem_fixture:run(?MODULE,callback_stack).
enter4()->gen_statem_fixture:run(?MODULE,enter4).
enter5()->gen_statem_fixture:run(?MODULE,enter5).
enter6()->gen_statem_fixture:run(?MODULE,enter6).
linked_parent()->gen_statem_fixture:run(?MODULE,linked_parent).
invalid_action()->gen_statem_fixture:run(?MODULE,invalid_action).
invalid_timeout()->gen_statem_fixture:run(?MODULE,invalid_timeout).
invalid_next_event()->gen_statem_fixture:run(?MODULE,invalid_next_event).
init(A)->gen_statem_fixture:init(A).
callback_mode()->[state_functions,state_enter].
idle(T,E,D)->gen_statem_fixture:event(T,E,idle,D).
active(T,E,D)->gen_statem_fixture:event(T,E,active,D).
terminate(Reason,_State,{Owner,_N,_L})->Owner!{terminated,self(),Reason},ok.
code_change(_V,S,{O,N,L},Extra)->{ok,S,{O,N+Extra,[code_change|L]}}.

trace(Ops)->gen_statem_fixture:trace(?MODULE,Ops).

enter_init(Starter,Arity) ->
 proc_lib:init_ack(Starter,{ok,self()}), Data={Starter,0,[]},
 case Arity of
  4->gen_statem:enter_loop(?MODULE,[],idle,Data);
  5->gen_statem:enter_loop(?MODULE,[],idle,Data,[{next_event,internal,entered}]);
  6->gen_statem:enter_loop(?MODULE,[],idle,Data,self(),[{next_event,internal,entered}])
 end.
