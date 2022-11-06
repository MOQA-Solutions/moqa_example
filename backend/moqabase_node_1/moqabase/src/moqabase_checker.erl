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


-module(moqabase_checker).


-export([check_environment_variables/0]).
-export([check_partition_number/1]).
-export([check_partition/2]).
-export([check_scale_requirements/2]).
-export([get_frontend_node_state/3]).


-include("../include/servers.hrl").
-include("../include/moqabase_timers.hrl").


-spec check_environment_variables() -> boolean().
check_environment_variables() ->
	case moqabase:get_number_of_procs_per_fragment() of
		{ok , NumberOfProcsPerFragment} when is_integer(NumberOfProcsPerFragment),
						     NumberOfProcsPerFragment > 0 ->
			case moqabase:get_frontend_nodes() of
				{ok , FrontendNodes} when is_list(FrontendNodes),
							  length(FrontendNodes) > 0 ->
					true;
				_ ->
					false
			end;
		_ ->
			false
	end.


-spec check_partition_number(pos_integer()) -> boolean().
check_partition_number(PartitionNumber) 
	when is_integer(PartitionNumber),
	     PartitionNumber > 0 
		->
	Partition = moqabase:integer_to_atom(PartitionNumber),
	Server = ?MOQABASE_SERVER,
	PartitionNode = moqabase:partition_to_node(Partition),
	ServerAddress = {Server , PartitionNode},
	case ping(ServerAddress) of
		pang  ->
			case PartitionNumber of
				1 ->
					true;
				_ ->			
					PrecedentPartitionNumber = PartitionNumber - 1,
					PrecedentPartition = moqabase:integer_to_atom(PrecedentPartitionNumber),
					PrecedentPartitionNode = moqabase:partition_to_node(PrecedentPartition),
					PrecedentPartitionServerAddress = {Server , PrecedentPartitionNode},
					case ping(PrecedentPartitionServerAddress) of
						pong ->
							true;
						pang ->						       
							false
					end
			end;
		pong -> 
			false
	end;


check_partition_number( _ ) ->
	false.


-spec check_scale_requirements(atom() , list()) -> boolean().
check_scale_requirements(PeerNode , FrontendNodes) ->
	case check_peer_node(PeerNode) of
		true ->
			case check_frontend_nodes(FrontendNodes) of
				true ->
					true;
				_ ->
					false
			end;
		_ ->
			false
	end.


-spec check_peer_node(atom()) -> boolean().
check_peer_node(PeerNode) ->
	Server = ?MOQABASE_SERVER,
	ServerAddress = {Server , PeerNode},
	case ping(ServerAddress) of
		pong ->
			true;
		pang ->
			false
	end.


-spec check_frontend_nodes(list()) -> boolean().
check_frontend_nodes(FrontendNodes) ->
	Server = ?PARTITIONS_SERVER,
	NodesStates = get_frontend_nodes_states(FrontendNodes , Server),
	case lists:member(on , NodesStates) of
		true ->
			false;
		false ->
			true
	end.


-spec get_frontend_nodes_states(list() , atom()) -> [ on | off ]. 
get_frontend_nodes_states(FrontendNodes , Server) ->
	[spawn(?MODULE , get_frontend_node_state , [self() , FrontendNode , Server])
	 || FrontendNode <- FrontendNodes
	],
	NodesStates = [],
	_ = erlang:start_timer(?STANDARD_TIMEOUT , self() , 'end of receive'),
	do_receive(NodesStates).


do_receive(NodesStates) ->
	receive
		{node_state , State} ->
			NewNodesStates = [State | NodesStates],
			do_receive(NewNodesStates);
		{timeout , _Timer , 'end of receive'} ->
			NodesStates
	end.


get_frontend_node_state(Parent , Node , Server) ->
	ServerAddress = {Server , Node},
	case ping(ServerAddress) of
		pong ->
			erlang:send(Parent , {node_state , on});
		pang ->
			erlang:send(Parent , {node_state , off})
	end.


-spec ping( {atom() , atom()} ) ->  pong | pang.
ping(ServerAddress) ->
	erlang:send(ServerAddress , {self() , ping}),
	receive
		{moqabase_server , pong} ->
			pong;
		{partitions_states_server , pong} ->
			pong
	after ?PING_TIMEOUT  ->
		pang
	end.


-spec check_partition(tuple() , atom()) -> boolean().
check_partition(RecordOrOid , Partition) ->
	case element(1 , RecordOrOid) of
		Partition ->
			true;
		_ ->
			false
	end.


	
