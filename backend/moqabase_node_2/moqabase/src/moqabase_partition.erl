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


-module(moqabase_partition).


-export([init/1]).
-export([get_number_of_fragments/1]).
-export([scale_up/2]).
-export([scale_down/2]).
-export([write/1]).
-export([read/1]).
-export([delete/1]).
-export([store_operation/2]).
-export([do_self_missed_operations/1]).
-export([get_peer_missed_operations/1]).	
-export([release_peer_missed_operations/1]).



-type mnesia_result() :: {atomic , ok} | {aborted , Reason :: term()}.
-type scale_result() :: scale_done | scale_failed.



-include("../include/moqabase_partition.hrl").
-include("../include/servers.hrl").



init(Partition) ->
	try_create_table(Partition),
	PeerPartition = moqabase:get_peer_partition(Partition),
	try_create_table(PeerPartition),
	try_create_table(tmp),
	ok.


try_create_table(Partition) ->
	case create_table(Partition) of
		{atomic , ok} ->
			try_fragmentation(Partition);
		{aborted , {already_exists , Partition}} ->
			ok;
		{aborted , Reason} ->
			exit(Reason)
	end.


-spec create_table(atom()) -> mnesia_result().
create_table(Partition) ->
	case Partition of
		tmp -> 
			mnesia:create_table(tmp , [{attributes , record_info(fields , tmp)},
						   {disc_copies , [node()]}
						  ]);
		Partition ->
			mnesia:create_table(Partition , [{attributes , ?FIELDS},
							 {disc_copies , [node()]}
							])
	end.


-spec try_fragmentation(atom()) -> ok | mnesia_result().
try_fragmentation(Partition) ->
	case Partition of
		tmp ->
			ok;
		NotTmp ->
			activate_fragmentation(NotTmp)
	end.


activate_fragmentation(Partition) ->
	mnesia:change_table_frag(Partition , {activate , []}).


-spec get_number_of_fragments(atom()) -> pos_integer().
get_number_of_fragments(Partition) ->
	Info = mnesia:table_info(Partition , frag_properties),
	proplists:get_value(n_fragments , Info).


-spec scale_up(atom() , pos_integer()) -> scale_result().
scale_up(Partition , Rate) ->
	try_to_scale_up(Partition , Rate , 0).


try_to_scale_up(_Partition , 0 , _NumberOfAddedFragments) ->
	scale_done;


try_to_scale_up(Partition , Rate , NumberOfAddedFragments) ->
	case try_to_add_frag(Partition) of
		{atomic , ok} ->
			try_to_scale_up(Partition , Rate - 1 , NumberOfAddedFragments + 1);
		{aborted , Reason} ->
			{scale_failed , Reason , NumberOfAddedFragments}
	end.


try_to_add_frag(Partition) ->
	mnesia:change_table_frag(Partition , {add_frag , [node()]}).


-spec scale_down(atom() , pos_integer()) -> scale_result().
scale_down(Partition , Rate) ->
	try_to_scale_down(Partition , Rate , 0).


try_to_scale_down(_Partition , 0 , _NumberOfDeletedFragments) ->
	scale_done;


try_to_scale_down(Partition , Rate , NumberOfDeletedFragments) ->
	case try_to_delete_frag(Partition) of
		{atomic , ok} ->
			try_to_scale_down(Partition , Rate - 1 , NumberOfDeletedFragments + 1);
		{aborted , Reason} ->
			{scale_failed , Reason , NumberOfDeletedFragments}
	end.


try_to_delete_frag(Partition) ->
	mnesia:change_table_frag(Partition , del_frag).


-spec write(tuple()) -> ok.
write(Record) ->
	Fun = fun(R) -> mnesia:write(R) end,
	mnesia:activity(async_dirty , Fun , [Record] , mnesia_frag).


-spec delete( {atom() , atom()} ) -> ok.
delete(Oid) ->
	Fun = fun(O) -> mnesia:delete(O) end,
	mnesia:activity(async_dirty , Fun , [Oid] , mnesia_frag).


-spec read( {atom() , atom()} ) -> [] | [ tuple() ].
read(Oid) ->
	Fun = fun(O) -> mnesia:read(O) end,
	mnesia:activity(async_dirty , Fun , [Oid] , mnesia_frag).


-spec store_operation( tuple() , { write | delete , tuple() } ) -> ok.
store_operation(ID , {OP , RecordOrOid}) ->
	Key = {ID , element(2 , RecordOrOid)},
	TmpRecord =#tmp{tmp_id = Key , tmp_op = OP , tmp_data = RecordOrOid},
	mnesia:dirty_write(tmp , TmpRecord).


-spec do_self_missed_operations( [] | [ #tmp{} ] ) -> ok.
do_self_missed_operations([]) ->
	ok;


do_self_missed_operations([ MissedOperation | Tail ]) ->
	do_self_missed_operation(MissedOperation),
	do_self_missed_operations(Tail).


do_self_missed_operation(#tmp{tmp_op =  OP , tmp_data = RecordOrOid}) ->
	?MODULE:OP(RecordOrOid).


-spec get_peer_missed_operations( tuple() ) -> [] | [ #tmp{} ].
get_peer_missed_operations(ID) ->
	MatchHead = {tmp , {ID , '_'} , '_' , '_'},
	Guard = [],
	Result = ['$_'],
	MatchSpec = [ { MatchHead , Guard , Result } ],
	mnesia:dirty_select(tmp , MatchSpec).


-spec release_peer_missed_operations( [] | [ tuple() ] ) -> ok.
release_peer_missed_operations([]) ->
	ok;


release_peer_missed_operations([ Key | Tail ]) ->
	mnesia:dirty_delete(tmp , Key),
	release_peer_missed_operations(Tail).


 
