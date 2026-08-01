-module(gen_statem_async_handle_event_callbacks).
-behaviour(gen_statem).
-export([wait1/0,wait2/0,receive1/0,receive2/0,send4_wait_collection/0,receive_collection/0,reqids_add_list/0,collection_retain/0,wait_timeout_retry/0,receive_abandon_late/0,crashed_server/0,dead_server/0,named_server/0,out_of_order/0,check_direct/0,check_collection/0,mailbox_clean/0,property_collection/2]).
-export([init/1,callback_mode/0,handle_event/4]).
wait1()->gen_statem_async_fixture:run(?MODULE,wait1). wait2()->gen_statem_async_fixture:run(?MODULE,wait2).
receive1()->gen_statem_async_fixture:run(?MODULE,receive1). receive2()->gen_statem_async_fixture:run(?MODULE,receive2).
send4_wait_collection()->gen_statem_async_fixture:run(?MODULE,send4_wait_collection). receive_collection()->gen_statem_async_fixture:run(?MODULE,receive_collection).
reqids_add_list()->gen_statem_async_fixture:run(?MODULE,reqids_add_list). collection_retain()->gen_statem_async_fixture:run(?MODULE,collection_retain).
wait_timeout_retry()->gen_statem_async_fixture:run(?MODULE,wait_timeout_retry). receive_abandon_late()->gen_statem_async_fixture:run(?MODULE,receive_abandon_late).
crashed_server()->gen_statem_async_fixture:run(?MODULE,crashed_server). dead_server()->gen_statem_async_fixture:run(?MODULE,dead_server).
named_server()->gen_statem_async_fixture:run(?MODULE,named_server). out_of_order()->gen_statem_async_fixture:run(?MODULE,out_of_order).
check_direct()->gen_statem_async_fixture:run(?MODULE,check_direct). check_collection()->gen_statem_async_fixture:run(?MODULE,check_collection).
mailbox_clean()->gen_statem_async_fixture:run(?MODULE,mailbox_clean). property_collection(O,D)->gen_statem_async_fixture:property_collection(?MODULE,O,D).
init([])->gen_statem_async_fixture:init(). callback_mode()->handle_event_function. handle_event(T,E,S,D)->gen_statem_async_fixture:event(T,E,S,D).
