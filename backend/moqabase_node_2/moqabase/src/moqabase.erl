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


-module(moqabase).


-export([get_number_of_procs_per_fragment/0]).
-export([get_frontend_nodes/0]).
-export([integer_to_atom/1]).
-export([atom_to_integer/1]).
-export([get_peer_partition/1]).
-export([partition_to_node/1]).
-export([get_peer_node/1]).
-export([get_keys/1]).


-include("../include/moqabase_partition.hrl").


-type get_env_result() :: {ok , any()} | undefined.


-spec get_number_of_procs_per_fragment() -> get_env_result().
get_number_of_procs_per_fragment() ->
	application:get_env(moqabase , number_of_procs_per_fragment).


-spec get_frontend_nodes() -> get_env_result().
get_frontend_nodes() ->
	application:get_env(moqabase , frontend_nodes).


-spec integer_to_atom(integer()) -> atom().
integer_to_atom(Number) ->
	list_to_atom(integer_to_list(Number)).


-spec atom_to_integer(atom()) -> integer(). 
atom_to_integer(Atom) ->
	list_to_integer(atom_to_list(Atom)).


-spec partition_to_node(atom()) -> atom().
partition_to_node(Partition) ->

	%%  - In our case, we have just 1 island (2 nodes)
	
	%%  - For more islands, you should update this function 

	case Partition of 
		'1' -> 
			'ghani1@ABDELGHANI' ;
		'2' -> 
			'ghani2@ABDELGHANI';
		_ ->			       
			exit('unknown node')
	end.


-spec get_peer_node(atom()) -> atom().
get_peer_node(Partition) ->
	PeerPartition = get_peer_partition(Partition),
	partition_to_node(PeerPartition).


-spec get_peer_partition(atom()) -> atom().
get_peer_partition(Partition) ->
	PartitionNumber = atom_to_integer(Partition),
	PeerPartitionNumber = case (PartitionNumber rem 2) of
					0 -> PartitionNumber - 1;
					_ -> PartitionNumber + 1
		      	      end,
	integer_to_atom(PeerPartitionNumber).


-spec get_keys( [ #tmp{} ] ) -> [ tuple() ].
get_keys(PeerMissedOperations) ->
	get_keys(PeerMissedOperations , []).


get_keys([] , Keys) ->
	Keys;


get_keys([ #tmp{ tmp_id = Key } | Tail ] , Keys) ->
	get_keys(Tail ,  [ Key | Keys ]).


