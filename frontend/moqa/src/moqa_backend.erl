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


-module(moqa_backend).


-export([update_backend_record/4]).
-export([read_backend_record/2]).
-export([write_backend_record/3]).
-export([delete_backend_record/3]).
-export([release_backend_worker/2]).
-export([get_partitions_states/0]).
-export([get_partitions_states/1]).
-export([get_partition_state/3]).

-include("../include/moqa_timers.hrl").
-include("../include/moqa_worker_data.hrl").
-include("../include/servers.hrl").


send_backend_command({read , Key} = Command , BackendPartitionsStates) ->
	NumberOfBackendPartitions = maps:size(BackendPartitionsStates),
	PrimaryPartition = get_primary_partition(Key , NumberOfBackendPartitions),
	Request = create_request(Command , PrimaryPartition),
	case maps:get(PrimaryPartition , BackendPartitionsStates) of
		undefined -> 
			switch_to_secondary_partition(PrimaryPartition , Key , Request , BackendPartitionsStates);
		Val ->
			try_read_from_server(PrimaryPartition , Val , Key , Request) 
	end;


send_backend_command({release , _Key} = Command , Pid) ->
	Request = create_request(Command),
	release_server(Pid , Request).

	
send_backend_command({write , Tuple} = Command , Pid , BackendPartitionsStates) ->
	Key = element(1 , Tuple),
	NumberOfBackendPartitions = maps:size(BackendPartitionsStates),
	PrimaryPartition = get_primary_partition(Key , NumberOfBackendPartitions),
	Request = create_request(Command , PrimaryPartition),
	try_write_to_server(Pid , Request);


send_backend_command({delete , Key} = Command , Pid , BackendPartitionsStates) ->
	NumberOfBackendPartitions = maps:size(BackendPartitionsStates),
	PrimaryPartition = get_primary_partition(Key , NumberOfBackendPartitions),
	Request = create_request(Command , PrimaryPartition),
	try_delete_from_server(Pid , Request).


switch_to_secondary_partition(PrimaryPartition , Key , Request , BackendPartitionsStates) ->
	SecondaryPartition = moqa:get_secondary_partition(PrimaryPartition),
	case maps:get(SecondaryPartition , BackendPartitionsStates) of
		undefined -> 
			{stop , 'server not available'};
		Val ->
			try_read_from_server(SecondaryPartition , Val , Key , Request) 
	end.


try_read_from_server(Partition , NumberOfProcs ,  Key , Request) ->
	Worker = get_worker(Key , NumberOfProcs),
	Node = moqa:partition_to_node(Partition),
	WorkerAddress = {Worker , Node},
	erlang:send(WorkerAddress , Request),
	do_receive().


try_write_to_server(Pid , Request) ->
	erlang:send(Pid , Request),
	do_receive().


try_delete_from_server(Pid , Request) ->
	erlang:send(Pid , Request),
	do_receive().


release_server(Pid , Request) ->
	erlang:send(Pid , Request),
	ok.


-spec get_primary_partition(any() , pos_integer()) -> atom().
get_primary_partition(Key , NumberOfPartitions) ->
	PrimaryPartitionNumber = erlang:phash2(Key , NumberOfPartitions) + 1,
	moqa:integer_to_atom(PrimaryPartitionNumber).


-spec get_worker(any() , pos_integer()) -> atom().
get_worker(Key , NumberOfProcs) ->
	WorkerNumber = erlang:phash2(Key , NumberOfProcs) + 1,
	moqa:integer_to_atom(WorkerNumber).


do_receive() ->
	receive					
	{'moqabase reply' , Reply} -> 
		Reply
	after ?STANDARD_TIMEOUT ->
		{stop , 'server unavailable'}
	end.


-spec update_backend_record({atom() , atom()} , term() , nonempty_binary() , map()) -> ok. 
update_backend_record(Operation , OPValue , Username ,  BackendPartitionsStates) ->
	{Pid , [Record]} = read_backend_record(Username , BackendPartitionsStates),
	UserTuple = moqa:update_record_field(Operation , OPValue , Record),
	write_backend_record(Pid , UserTuple , BackendPartitionsStates).


-spec read_backend_record(nonempty_binary() , map()) -> [ tuple() ] | [].
read_backend_record(Username , BackendPartitionsStates) ->
	Key = Username,
	send_backend_command({read , Key} , BackendPartitionsStates).


-spec write_backend_record(pid() , tuple() , map()) -> ok.
write_backend_record(Pid , UserTuple , BackendPartitionsStates) ->
	send_backend_command({write , UserTuple} , Pid , BackendPartitionsStates).


-spec delete_backend_record(pid() , nonempty_binary() , map()) -> ok.
delete_backend_record(Pid , Username , BackendPartitionsStates) ->
	Key = Username,
	send_backend_command({delete , Key} , Pid , BackendPartitionsStates).


-spec release_backend_worker(pid() , nonempty_binary()) -> ok.
release_backend_worker(Pid , Username) ->
	Key = Username,
	send_backend_command({release , Key} , Pid).


-spec create_request({ read | write | delete | release , nonempty_binary() | tuple() } , atom()) 
			-> { pid() , { read | write | delete | release , nonempty_binary() | tuple()} }.
create_request({read , Key} , Partition) ->
	Oid = {Partition , Key},
	{self() , {read , Oid}};


create_request({write , Tuple} , Partition) ->
	Record = list_to_tuple( [ Partition | tuple_to_list( Tuple ) ] ),
	{self() , {write , Record}};


create_request({delete , Key} , Partition) ->
	Oid = {Partition , Key},
	{self() , {delete , Oid}}.


create_request({release , Key}) ->
	{self() , {release , Key}}.


-spec get_partitions_states() -> map().
get_partitions_states() ->
	partitions_states_server:get_partitions_states().


-spec get_partitions_states(pos_integer()) -> { [ atom() ] , map() }.
get_partitions_states(NumberOfPartitions) ->
	Partitions = [ moqa:integer_to_atom(PartitionNumber)
		       || PartitionNumber <- lists:seq(1 , NumberOfPartitions)
		     ],
	Server = ?MOQABASE_SERVER,
	PartitionsStates = get_partitions_states(Partitions , Server),
	{Partitions , PartitionsStates}.
	

get_partitions_states(Partitions , Server) ->
	[ spawn(?MODULE , get_partition_state , [self() , Partition , Server]) 
	  || Partition <- Partitions
	],
	PartitionsStates =#{},
	_ = erlang:start_timer(?STANDARD_TIMEOUT , self() , 'end of receive'),
	do_receive(PartitionsStates).


do_receive(PartitionsStates) ->
	receive
		{partition_state , Partition , State} ->
			NewPartitionsStates = PartitionsStates#{Partition => State},
			do_receive(NewPartitionsStates);
		{timeout , _Timer , 'end of receive'} ->
			PartitionsStates
	end.


get_partition_state(Parent , Partition , Server) ->
	PartitionNode = moqa:partition_to_node(Partition),
	ServerAddress = {Server , PartitionNode},
	erlang:send(ServerAddress , {self() , get_number_of_procs}),
	receive
		{number_of_procs , NumberOfProcs} ->
			erlang:send(Parent , {partition_state , Partition , NumberOfProcs})
	after ?PING_TIMEOUT ->
			erlang:send(Parent , {partition_state , Partition , undefined})
	end.


