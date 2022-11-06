%%=================================================================================================================%%
%%
%%   Copyright (c) 2022 , Hachemaoui Sidi Mohammed <hachemaouisidimohammed@gmail.com> 
%%
%%    This program is under GNU General Public License v3, you may check the full license's
%%    terms and conditions in LICENSE file for more details.
%%
%%    Rights granted for use, distribution, modification, patent use, and private use of the software.
%%
%%    Requirements to disclose the source code, display the license and copyright notices, 
%%    state all changes, and name the libraries under the same license
%%
%%    You may copy, distribute and modify the software as long as you track changes/dates in source files. 
%%
%%    Any modifications to or software including (via compiler) GPL-licensed code must also be made available 
%%    under the GPLv3 along with build & install instructions.
%%
%%    Users can change or rework the code, but if they distribute these changes/modifications in binary form, 
%%    they’re also required to release these updates in source code form under the GPLv3 license.
%%
%%    As long as these modifications are also released under the GPLv3 license, they can be distributed to others.
%%
%%=================================================================================================================%%


-module(moqabase_interface).


-export([scale/2]).
-export([read/2]).
-export([server_state/0]).
-export([worker_state/1]).
-export([fragments/1]).
-export([procs/0]).


scale(Partition , NewNumberOfFragments) ->
	moqabase_server:set_scale_level(Partition , NewNumberOfFragments).


read(Partition , Key) ->
	BinKey = list_to_binary(Key),
	Fun = fun(P , K) -> mnesia:read(P , K) end,
	mnesia:activity(async_dirty , Fun , [Partition , BinKey] , mnesia_frag).
		

server_state() ->
	moqabase_server:get_state().


worker_state(ID) ->
	moqabase_pool_worker:get_state(ID).


fragments(Partition) ->
	moqabase_partition:get_number_of_fragments(Partition).


procs() ->
	moqabase_pool_sup:get_number_of_active_procs().


