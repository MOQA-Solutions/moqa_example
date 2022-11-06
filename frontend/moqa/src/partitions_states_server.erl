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


-module(partitions_states_server).


-export([start_link/1]).
-export([init/1]).
-export([handle_info/2]).
-export([handle_cast/2]).
-export([handle_call/3]).
-export([code_change/2]).
-export([terminate/2]).
-export([get_partitions_states/0]).
-export([get_state/0]).


-include("../include/moqa_timers.hrl").


-record(state , {

	partitions_states :: map()

	}).


-spec start_link(pos_integer()) -> {ok , pid()}.
start_link(NumberOfPartitions) ->
	gen_server:start_link({local , ?MODULE} , ?MODULE , [NumberOfPartitions] , []).


init([NumberOfPartitions]) ->
	{Partitions , PartitionsStates} = moqa_backend:get_partitions_states(NumberOfPartitions),
	Nodes = [moqa:partition_to_node(Partition) 
		 || Partition <- Partitions
		],
	[ true = erlang:monitor_node(Node , true)
	  || Node <- Nodes
	],
	State =#state{
		partitions_states = PartitionsStates
		},
	{ok , State}.


%%========================================================================================================================%%

%%						gen_server callback functions						  %%

%%========================================================================================================================%%


handle_info({nodedown , Node} , State =#state{
					partitions_states = PartitionsStates
					}
		) ->
	logger:debug(#{
			'1)Reason' => 'NODE DOWN',
			'2)Node' => Node
		}),
	Partition = moqa:node_to_partition(Node),
	NewPartitionsStates = PartitionsStates#{Partition => undefined},
	NewState = State#state{
			partitions_states = NewPartitionsStates
		},
	{noreply , NewState};


handle_info({update_partitions_states , Partition , NewNumberOfProcs} , 
	State =#state{
		partitions_states = PartitionsStates
		}) ->
	Node = moqa:partition_to_node(Partition),
	logger:debug(#{
			'1)Reason' => 'NODE UP',
			'2)Node' => Node
		}),
	true = erlang:monitor_node(Node , true),
	NewPartitionsStates = PartitionsStates#{Partition => NewNumberOfProcs},
	NewState = State#state{partitions_states = NewPartitionsStates},
	{noreply , NewState};


handle_info({From , get_partitions_states} , 
	State =#state{
		partitions_states = PartitionsStates
		}) ->
	Reply = {partitions_states , PartitionsStates},
	erlang:send(From , Reply),
	{noreply , State};


handle_info({From , ping} , State) ->
	Reply = {partitions_states_server , pong},
	erlang:send(From , Reply),
	{noreply , State};

	
handle_info(_Info , State) ->
	{noreply , State}.


%%+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%

			
handle_cast(_Cast , State) ->
	{noreply , State}.


%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


handle_call(get_state , _From , State) ->
	Reply = State,
	{reply , Reply , State};


handle_call(_Call , _From , State) ->
	{noreply , State}.


%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


code_change( _OldVsn , State) ->
	{ok , State}.


%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


terminate(Reason , State) ->

	{Reason , State}.


%%======================================================================================================================%%

%%						end of gen_server callback functions 					%%

%%======================================================================================================================%%


get_partitions_states() ->
	erlang:send(?MODULE , {self() , get_partitions_states}),
	receive
		{partitions_states , PartitionsStates} ->
			PartitionsStates
	after ?STANDARD_TIMEOUT ->
		exit('partitions server unavailable')
	end.
		

get_state() ->
	gen_server:call(?MODULE , get_state).

	
