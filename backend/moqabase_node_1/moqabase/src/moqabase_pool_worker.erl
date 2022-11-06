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


-module(moqabase_pool_worker).


-export([start_link/2]).
-export([init/1]).
-export([callback_mode/0]).
-export([loop_peer_off/3]).
-export([loop_peer_on/3]).
-export([terminate/3]).
-export([get_state/1]).


-include("../include/moqabase_pool_worker_data.hrl").
-include("../include/moqabase_timers.hrl").


-spec start_link(atom() , pos_integer()) -> {ok , pid()}.
start_link(SelfPartition , ID) ->
	gen_statem:start_link({local , ID} , ?MODULE , [SelfPartition , ID] , []).


init([SelfPartition , ID]) ->
	PeerNode = moqabase:get_peer_node(SelfPartition),
	PeerWorker = ID,
	PeerAddress = {PeerWorker , PeerNode},
	Data =#data{
		id = ID,
		self_partition = SelfPartition,
		peer_address = PeerAddress,
		locker =#{},
		statement = off
		},
	ping(PeerAddress),
	{ok , loop_peer_off , Data}.


callback_mode() ->
	state_functions.
	

%%==============================================================================================================%%

%%					gen_statem callback functions		      				%%

%%==============================================================================================================%%


loop_peer_off(info , {From , pong} , 
	Data =#data{
		id = ID
		}) ->
	case handshake_client_side(ID , From) of
		done ->
			NewData = Data#data{
					peer_pid = From,
					statement = on
				},
			flush_messages(),
			{next_state , loop_peer_on , NewData};
		failure ->
			flush_messages(),
			{keep_state , Data}
	end;


loop_peer_off(info , Info , Data) ->	
	handle_common_infos(Info , ?FUNCTION_NAME , Data);


loop_peer_off(cast , _Cast , Data) ->
	{keep_state , Data};


loop_peer_off({call , _From} , _Call , Data) ->
	{keep_state , Data}.


%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


loop_peer_on(info , {From , {OP , Oid}} , 
	Data =#data{
		peer_pid = From
		})
	when OP =:= write;
	     OP =:= delete
		->
	ok = moqabase_partition:OP(Oid),
	erlang:send(From , {self() , replication_done}),
	{keep_state , Data};


loop_peer_on(info , {_From , {OP , RecordOrOid}} = Info , 
	Data =#data{
		self_partition = SelfPartition, 
		peer_pid = Pid
		})
	when OP =:= read;
	     OP =:= write;
	     OP =:= delete
		->
	case moqabase_checker:check_partition(RecordOrOid , SelfPartition) of
		true -> 
			handle_common_infos(Info , ?FUNCTION_NAME , Data);
		_ -> 
			ping(Pid), 
			receive
				{Pid , pong} -> 
					{keep_state , Data}
			after ?STANDARD_TIMEOUT ->
				NewData = Data#data{
						peer_pid = undefined,
						statement = off
						},
				{next_state , loop_peer_off , NewData}
			end
	end;


loop_peer_on(info , Info , Data) ->
	handle_common_infos(Info , ?FUNCTION_NAME , Data);


loop_peer_on(cast , _Cast , Data) ->
	{keep_state , Data};


loop_peer_on({call , _From} , _Call , Data) ->
	{keep_state , Data}.


%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


terminate(Reason , State , Data) ->
	{Reason , State , Data}.


%%==============================================================================================================%%

%%					end of gen_statem callback functions					%%

%%==============================================================================================================%%


handle_common_infos({timeout , Timer , {'expired timeout' , Key}} , _State ,
	Data =#data{
		locker = Locker
		}) ->
	NewData = case maps:take(Key , Locker) of
			{ {_Pid , Timer} , NewLocker } ->
				Data#data{
					locker = NewLocker
					};
			error ->
				Data
		  end,
	{keep_state , NewData};	


handle_common_infos({From , {release , Key}} , _State , 
	Data =#data{
		locker = Locker
		}) ->
	NewData = case maps:take(Key , Locker) of
			{ { From , Timer} , NewLocker } ->
				erlang:cancel_timer(Timer),
				Data#data{
					locker = NewLocker
					};
			error ->
				Data
		 end,
	{keep_state , NewData};				


handle_common_infos({From , get_state} , _State ,  Data) ->
	erlang:send(From , Data),
	{keep_state , Data};


handle_common_infos({From , ping} , _State , Data) ->
	erlang:send(From , {self() , pong}),
	{keep_state , Data};


handle_common_infos({From , start_handshake_protocol} , _State ,
	Data =#data{
		id = ID
		}) ->
	case handshake_server_side(ID , From) of
		done ->
			NewData = Data#data{
				peer_pid = From,
				statement = on
				},
			flush_messages(),
			{next_state , loop_peer_on , NewData};
		failure ->
			NewData = Data#data{
					peer_pid = undefined,
					statement = off
				},
			flush_messages(),
			{next_state , loop_peer_off , NewData}
	end;


handle_common_infos({From , {read , Oid}} , _State , 
	Data =#data{
		locker = Locker
		}) ->
	Key = element(2 , Oid),
	case maps:find(Key , Locker) of
		{ok , _Val} ->
			{keep_state , Data , [postpone]};
		error ->
			Reply = reply({self() , moqabase_partition:read(Oid)}),
			erlang:send(From , Reply),
			Timer = erlang:start_timer(?STANDARD_TIMEOUT , self() , {'expired timeout' , Key}),
			NewLocker = Locker#{ Key => { From , Timer} },
			NewData = Data#data{
					locker = NewLocker
				},
			{keep_state , NewData}
	end;


handle_common_infos({From , {OP , RecordOrOid} = Operation} , State , 
	Data =#data{
		locker = Locker
		}) ->
	Key = element(2 , RecordOrOid),
	case maps:take(Key , Locker) of
		{ {From , Timer} , NewLocker} ->
			erlang:cancel_timer(Timer),
			Reply = reply(moqabase_partition:OP(RecordOrOid)),
			erlang:send(From , Reply),
			NewData = Data#data{
					locker = NewLocker
				},
			after_operation(Operation , State , NewData);
		error ->
			{keep_state , Data}
	end;


handle_common_infos(_Info , _State , Data) ->
	{keep_state , Data}. 


after_operation(Operation , loop_peer_off ,
	Data =#data{
		id = ID
		}) ->
	ok = moqabase_partition:store_operation(ID , Operation),
	{keep_state , Data};


after_operation(Operation , loop_peer_on , 
	Data =#data{
		id = ID,
		peer_pid = Pid
		}) ->
	PeerCommand = {self() , Operation},
	erlang:send(Pid , PeerCommand),
	receive
		{Pid , replication_done} ->
			{keep_state , Data}
		after ?STANDARD_TIMEOUT ->
			ok = moqabase_partition:store_operation(ID , Operation),
			NewData = Data#data{
					peer_pid = undefined,
					statement = off
				},
			{next_state , loop_peer_off , NewData}
	end.


-spec ping({atom() , atom()} | pid()) -> ok.
ping(PeerAddressOrPid) ->
	erlang:send(PeerAddressOrPid , {self() , ping}).


-spec handshake_client_side(atom() , pid()) -> done.
handshake_client_side(ID , Pid) ->
	erlang:send(Pid , {self() , start_handshake_protocol}),
	receive
		start_handshake_protocol ->
			erlang:send(Pid , get_missed_operations),
			receive
				{missed_operations , SelfMissedOperations} ->
					ok = moqabase_partition:do_self_missed_operations(SelfMissedOperations),
					erlang:send(Pid , done),
					receive
						get_missed_operations ->
							PeerMissedOperations = moqabase_partition:get_peer_missed_operations(ID),
							erlang:send(Pid , {missed_operations , PeerMissedOperations}),
							receive
								done -> 
									Keys = moqabase:get_keys(PeerMissedOperations),
									ok = moqabase_partition:release_peer_missed_operations(Keys),
									done	
							after ?HANDSHAKE_WRITE_TIMEOUT ->
								failure
							end
					after ?HANDSHAKE_RELEASE_TIMEOUT -> 
						failure
					end
			after ?HANDSHAKE_READ_TIMEOUT ->
				failure
			end
	after ?STANDARD_TIMEOUT ->
		failure
	end.


-spec handshake_server_side(atom() , pid()) -> done.
handshake_server_side(ID , Pid) ->
	erlang:send(Pid , start_handshake_protocol),
	receive
		get_missed_operations ->
			PeerMissedOperations = moqabase_partition:get_peer_missed_operations(ID),
			erlang:send(Pid , {missed_operations , PeerMissedOperations}),
			receive
				done ->
					Keys = moqabase:get_keys(PeerMissedOperations),
					ok = moqabase_partition:release_peer_missed_operations(Keys),
					erlang:send(Pid , get_missed_operations),
					receive
						{missed_operations , SelfMissedOperations} ->
							ok = moqabase_partition:do_self_missed_operations(SelfMissedOperations),
							erlang:send(Pid , done),
							done
					after ?HANDSHAKE_READ_TIMEOUT ->
						failure
					end
			after ?HANDSHAKE_WRITE_TIMEOUT ->
				failure
			end	
	after ?STANDARD_TIMEOUT ->
		failure
	end.


get_state(WorkerRef) ->
	erlang:send(WorkerRef , {self() , get_state}),
	receive
		Reply -> 
			Reply

	after ?PING_TIMEOUT -> 
		no_reply
	end.


reply(Reply) ->
	{'moqabase reply' , Reply}.


flush_messages() ->
	receive
		_ ->
			ok
	after 0 ->
		ok
	end,
	ok.



