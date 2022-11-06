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


-module(moqa_worker).


-export([start_link/1]).
-export([init/1]).
-export([callback_mode/0]).
-export([not_connected/3]).
-export([connected/3]).
-export([terminate/3]).


-include("../include/moqa_timers.hrl").
-include("../include/moqa_data.hrl").
-include("../include/client_info_data.hrl").
-include("../include/moqa_worker_data.hrl").


-spec start_link(port()) -> pid().
start_link(Socket) ->
	{ok , Pid} = gen_statem:start_link(?MODULE , [Socket] , []),
	Pid.


init([Socket]) ->
	BackendPartitionsStates = moqa_backend:get_partitions_states(),
	Data =#data{
		socket = Socket,
		backend_partitions_states = BackendPartitionsStates,
		status = not_connected  
		},
	{ok , not_connected , Data}.


callback_mode() ->
	state_functions.


%%=========================================================================================================================%%

%%						gen_statem callback functions		       				   %%

%%=========================================================================================================================%%


not_connected(info , {tcp , Socket , BinPacket} , Data =#data{socket = Socket}) ->
	try moqalib_parser:parse(BinPacket) of
		MoqaData ->
			case moqa_checker:check_server_not_connected_waiting_data(MoqaData) of
				true ->
					Packet = MoqaData,
					try_to_signup_or_connect(Packet , Data);
				_ ->
					{stop , 'unexpected data from client'}
			end
	catch
		error:Error ->
			{stop , Error};
		exit:Exit ->
			{stop , Exit}
	end;


not_connected(info , {tcp_closed , Socket} , #data{socket = Socket}) ->
	{stop , 'socket closed'};


not_connected(info , _Info , Data) ->
	{keep_state , Data};


not_connected(cast , _Cast , Data) ->
	{keep_state , Data}.


%%+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


connected(info , {timeout , Timer , {'expired timeout' , 'keep alive'}}  , 
	#data{
		timer = Timer
		}) ->
	{stop , 'expired keep alive timeout'};


connected(info , {timeout , _Timer , {'expired timeout' , Username}} , 
	#data{
		user = Username
		}) ->
	{stop , 'client connexion problem'};


connected(info , {timeout , Timer , {'expired timeout' , Key}} , 
	Data =#data{
		socket = Socket,
		backend_partitions_states = BackendPartitionsStates
		}) ->
	case dequeue(Key , Data) of
		{{_SentBinPacket , SentMoqaData} = SentPacket , Timer , _Pid , NewData} ->
			Destination = element(4 , SentMoqaData),
			ok = send_offline_packet(Destination , SentPacket , BackendPartitionsStates),
			ok = send_ack(SentMoqaData , Socket),
			{keep_state , NewData};
		_ ->
			{keep_state , Data}
	end;
	

connected(info , {tcp , Socket , BinPacket} , 
	Data =#data{
		socket = Socket,
		keep_alive = KeepAlive,
		timer = Timer
		}) ->
	try moqalib_parser:parse(BinPacket) of
		MoqaData ->
			case moqa_checker:check_server_connected_waiting_data(MoqaData) of
				true ->
					NewTimer = restart_timer(Timer , KeepAlive),
					NewData = Data#data{timer = NewTimer},
					Packet = {BinPacket , MoqaData},
					connected_handle_client_packet(Packet , NewData);
				_ ->
					{stop , 'unexpected data from client'}
			end
	catch
		error:Error ->
			{stop , Error};
		exit:Exit ->
			{stop , Exit}
	end;


connected(info , {From , {'new packet' , OnlinePacket}} , Data) ->
	send_packet_to_client_and_enqueue(From , OnlinePacket , Data);


connected(info , {From , {'new ack' , OnlineAck}} , Data) ->
	dequeue_and_send_ack_to_client(From , OnlineAck , Data);


connected(info , {From , {'new notification' , Notification}} , Data) ->
	Data0 = connected_handle_server_notification(From , Notification , Data),
	{keep_state , Data0};


connected(info , {tcp_closed , Socket} , #data{socket = Socket}) ->
	{stop , 'socket closed'};


connected(info , _Info , Data) ->
	{keep_state , Data};


connected(cast , _Cast , Data) ->
	{keep_state , Data};


connected({call , _From} , _Call , Data) ->
	{keep_state , Data}.

			
%%+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


terminate(Reason , connected , #data{
				user = Username,
				online_users = OnlineUsers
				}
		) ->
	Notification = {Reason , Username},
	ok = send_notifications(Notification , OnlineUsers),
	ok = send_notification(Notification , moqa_server);


terminate(Reason , State , Data) ->
	{Reason , State , Data}.


%%=============================================================================================================================%%

%%						end of gen_statem callback functions		       			       %%

%%=============================================================================================================================%%


try_to_signup_or_connect(MoqaData , Data =#data{socket = Socket}) ->
	{Reply , NewData} = not_connected_handle_client_packet(MoqaData , Data),
	ClientReply = moqalib_encoder:encode_ack(MoqaData , Reply),	
	gen_tcp:send(Socket , ClientReply),
	case Reply of
		1 ->
			handle_unterminated_operation(NewData);
		0 ->
			{keep_state , Data}
	end.


-spec not_connected_handle_client_packet( #signup{} | #connect{} , #data{} ) -> { 0 | 1 , #data{} }.
not_connected_handle_client_packet(#signup{
					keep_alive = KeepAlive, 
					username = Username, 
					password = Password
					} , 
	Data =#data{
		backend_partitions_states = BackendPartitionsStates
		}) ->

	{Worker , Res} = moqa_backend:read_backend_record(Username , BackendPartitionsStates),
	{Reply , NewData} = case Res of
		[] ->
			ok = add_new_user(Worker , {Username , Password} , BackendPartitionsStates),
			Broker = #{},
			{ 1 , Data#data{
				user = Username,
				keep_alive = KeepAlive * 1000,
				roster_users_states =#{},
				client_roster =#{},
				packets_queue = [],
				subscriptions_queue = #{},
				unterminated_operation = undefined,
				online_users = [],
				broker = Broker
				}
			} ;
		[_Record] ->
			Key = Username,
			ok = moqa_backend:release_backend_worker(Worker , Key),
			{0 , Data}
	end,
	{Reply , NewData};


not_connected_handle_client_packet(#connect{
					username = Username
					} = Packet , 
	Data =#data{
		backend_partitions_states = BackendPartitionsStates
		}) ->
	{Worker , Res} = moqa_backend:read_backend_record(Username , BackendPartitionsStates),
	Key = Username,
	ok = moqa_backend:release_backend_worker(Worker , Key),
	{Reply , NewData} = case Res of
		[] ->
			{0 , Data};
		[Record] ->
			try_to_connect_user(Packet , Record , Data)
	end,
	{Reply , NewData}.


-spec add_new_user(pid() , {nonempty_binary() , nonempty_binary()} , map()) -> ok.
add_new_user(Pid , {Username , Password} , BackendPartitionsStates) ->
	Roster = [],
	BlackList = [],
	PacketsQueue = [],
	SubscriptionsQueue = #{},
	UnterminatedOperation = undefined,
	UserTuple = {Username , Password , Roster , BlackList , PacketsQueue , SubscriptionsQueue , UnterminatedOperation},
	moqa_backend:write_backend_record(Pid , UserTuple , BackendPartitionsStates).


-spec try_to_connect_user(#connect{} , tuple() , #data{}) -> { 0 | 1 , #data{} }.
try_to_connect_user(#connect{
			keep_alive =  KeepAlive , 
			username = Username , 
			password = Password
			}, 
		{_Partition , Username , Password , Roster , _BlackList , PacketsQueue , SubscriptionsQueue , UnterminatedOperation} , 
		Data ) ->		
	Fun = 
		fun(UsernameFromRoster , {Acc1 , Acc2 , Acc3}) -> 
			case moqa_server:get_user_state(UsernameFromRoster) of
				undefined ->
					{ Acc1 , 
					  Acc2#{UsernameFromRoster => off} ,
					  Acc3#{UsernameFromRoster => ?BINOFF}
					};
				Pid when is_pid(Pid) ->
					{ [Pid | Acc1] , 
					  Acc2#{UsernameFromRoster => Pid} , 
					  Acc3#{UsernameFromRoster => ?BINON}
					};
				LastSeen ->
					{Acc1 , 
					 Acc2#{UsernameFromRoster => LastSeen}, 
					 Acc3#{UsernameFromRoster => LastSeen}
					}
			end
		end,
	{OnlineUsers , RosterUsersStates , ClientRoster} = lists:foldl(Fun , { [] , #{} , #{}} , Roster),
	Broker =#{},
	Reply = 1,
	NewData = Data#data{
		user = Username,
		keep_alive = KeepAlive * 1000,
		roster_users_states = RosterUsersStates,
		client_roster = ClientRoster,
		online_users = OnlineUsers,
		packets_queue = PacketsQueue,
		subscriptions_queue = SubscriptionsQueue,
		unterminated_operation = UnterminatedOperation,
		broker = Broker
		},
	{Reply , NewData};


try_to_connect_user(_Packet , _Record , Data) ->
	Reply = 0,
	NewData = Data,
	{Reply , NewData}.


handle_unterminated_operation(Data =#data{
				unterminated_operation = undefined
				}
		) ->
	handle_packets_queue(Data);


handle_unterminated_operation(Data =#data{
				backend_partitions_states = BackendPartitionsStates,
				user = Username,
				unterminated_operation = UnterminatedOperation
				}
		) ->
	Data0 = handle_unterminated_operation(UnterminatedOperation , Data), 
	NewData = Data0#data{unterminated_operation = undefined},
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , undefined , Username , BackendPartitionsStates),
	handle_packets_queue(NewData).


handle_unterminated_operation({{_BinPacket , #deactivate{}} , _ } = Packet , Data) ->
	do_deactivate(Packet , Data);


handle_unterminated_operation({_BinPacket , #subscribe{}} = Packet , Data) ->
	do_subscribe(Packet , Data);


handle_unterminated_operation({_BinPacket , #subresp{}} = Packet , Data) ->
	do_subresp(Packet , Data);


handle_unterminated_operation({_Binpacket , #subcnl{}} = Packet , Data) ->
	do_subcnl(Packet , Data);


handle_unterminated_operation({_Binpacket , #unsubscribe{}} = Packet , Data) ->
	do_unsubscribe(Packet , Data);


handle_unterminated_operation({_BinPacket , #block{}} = Packet , Data) ->
	do_block(Packet , Data).
	

handle_packets_queue(Data =#data{ packets_queue = [] }) ->
	NewData = Data#data{packets_queue = undefined},
	almost_connected(NewData);


handle_packets_queue(Data =#data{ packets_queue = [H | Tail] }) ->
	Reply = handle_packet(H , Data),
	case Reply of
		done ->
			NewData = Data#data{packets_queue = Tail},
			handle_packets_queue(NewData);
		{error , Error} ->
			{stop , Error}
	end.


-spec handle_packet( {nonempty_binary() , moqalib_checker:moqa_data()} , #data{} ) -> done | {error , _}.
handle_packet({SentBinPacket , SentMoqaData} , 
	#data{ 
		socket = Socket ,
		user = Username ,
		backend_partitions_states = BackendPartitionsStates
		}) ->
	gen_tcp:send(Socket , SentBinPacket),
	Res = waiting_ack_from_client(Socket , SentMoqaData),
	case Res of
		{'ack packet' , _  } ->
			ok  = moqa_backend:update_backend_record({remove , packets_queue} , head , Username , BackendPartitionsStates),
			done;
		_ ->
			Res
	end.


-spec waiting_ack_from_client(port() , moqalib_checker:moqa_data()) ->
				{'ack packet' , {nonempty_binary() , moqalib_checker:moqa_data()}} |
				{error , _}.
waiting_ack_from_client(Socket , SentMoqaData) ->
	receive
		{tcp , Socket , BinPacket} ->
			try moqalib_parser:parse(BinPacket) of
				MoqaData ->
					case moqalib_checker:check_waiting_ack(MoqaData , SentMoqaData) of
						true ->
							{'ack packet' , {BinPacket , MoqaData}};
						_ ->
							{error , 'unexpected data'}
					end
			catch
				error:Error ->
					{error , Error};
				exit:Exit ->
					{error , Exit}
			end
	after ?SERVER_CLIENT_TIMEOUT ->
		{error , 'client offline'}
	end.


almost_connected(Data=#data{
			socket = Socket,
			user = Username ,
			keep_alive = KeepAlive ,
			client_roster = ClientRoster,
			subscriptions_queue = SubscriptionsQueue,
			online_users = OnlineUsers
			}
		) ->
	Notification = {presence , Username},
	ok = send_notifications(Notification , OnlineUsers),
	ok = send_notification(Notification , moqa_server),
	Subscriptions =#subscriptions{
				updates = SubscriptionsQueue
		},
	ClientInfo1 = moqalib_encoder:encode_packet(Subscriptions),
	gen_tcp:send(Socket , ClientInfo1),
	Roster =#roster{
		updates = ClientRoster
		},
	ClientInfo2 = moqalib_encoder:encode_packet(Roster),
	gen_tcp:send(Socket , ClientInfo2),
	Timer = erlang:start_timer(KeepAlive , self() , {'expired timeout' , 'keep alive'}),
	NewData = Data#data{
			timer = Timer, 
			status = connected, 
			client_roster = undefined
			},
	{next_state , connected , NewData}.


connected_handle_client_packet({_BinPacket , #state{}} , Data =#data{socket = Socket}) ->
	gen_tcp:send(Socket , term_to_binary(Data)),
	{keep_state , Data};


connected_handle_client_packet({_BinPacket , #disconnect{}} = Packet , Data) ->
	NewData = do_disconnect(Packet , Data),
	{next_state , not_connected , NewData};


connected_handle_client_packet({_BinPacket , #deactivate{}} = Packet , 
	Data =#data{
		backend_partitions_states = BackendPartitionsStates,
		user = Username
		}) ->
	Subscribers = moqa:get_subscribers(Data),
	Requests = moqa:get_subscriptions_requests(Data),
	UnterminatedOperation = {Packet , {Subscribers , Requests}},
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , UnterminatedOperation , Username , BackendPartitionsStates),
	NewData = do_deactivate(UnterminatedOperation , Data),
	{next_state , not_connected , NewData};


connected_handle_client_packet({_BinPacket , #publish{}} = Packet , Data) ->
	NewData = do_publish(Packet , Data),
	{keep_state , NewData};


connected_handle_client_packet({_BinPacket , #pubcomp{}} = Packet , Data) ->
	NewData = do_pubcomp(Packet , Data),
	{keep_state , NewData};


connected_handle_client_packet({_BinPacket , #subscribe{}} = Packet , 
	Data =#data{
		backend_partitions_states = BackendPartitionsStates,
		user = Username
		}) ->
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , Packet , Username , BackendPartitionsStates),
	NewData = do_subscribe(Packet , Data),
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , undefined , Username , BackendPartitionsStates),
	{keep_state , NewData};


connected_handle_client_packet({_BinPacket , #subcnl{}} = Packet , 
	Data =#data{
		backend_partitions_states = BackendPartitionsStates,
		user = Username
		}) ->
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , Packet , Username , BackendPartitionsStates),
	NewData = do_subcnl(Packet , Data),
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , undefined , Username , BackendPartitionsStates),
	{keep_state , NewData};


connected_handle_client_packet({_BinPacket , #subresp{}} = Packet , 
	Data =#data{
		backend_partitions_states = BackendPartitionsStates,
		user = Username
		}) ->
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , Packet , Username , BackendPartitionsStates),
	NewData = do_subresp(Packet , Data),
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , undefined , Username , BackendPartitionsStates),
	{keep_state , NewData};


connected_handle_client_packet({_BinPacket , #unsubscribe{}} = Packet , 
	Data =#data{
		backend_partitions_states = BackendPartitionsStates,
		user = Username
		}) ->
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , Packet , Username , BackendPartitionsStates),
	NewData = do_unsubscribe(Packet , Data),
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , undefined , Username , BackendPartitionsStates),
	{keep_state , NewData};


connected_handle_client_packet({_BinPacket , #block{}} = Packet , 
	Data =#data{
		backend_partitions_states = BackendPartitionsStates,
		user = Username
		}) ->
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , Packet , Username , BackendPartitionsStates),
	NewData = do_block(Packet , Data),
	ok = moqa_backend:update_backend_record({new , unterminated_operation} , undefined , Username , BackendPartitionsStates),
	{keep_state , NewData};


connected_handle_client_packet({_BinPacket , #unblock{}} = Packet , Data) ->
	ok = do_unblock(Packet , Data),
	{keep_state , Data};



connected_handle_client_packet({_BinPacket , #ping{}} = Packet , Data) ->
	ok = do_ping(Packet , Data),
	{keep_state , Data};


connected_handle_client_packet({_BinPacket , 
		{_AckPacket , PacketIdentifier , Destination}
			} = Packet , 
		Data) ->
	Key = {Destination , PacketIdentifier},
	OnlineAck = {Key , Packet},
	dequeue_and_send_ack_to_server(OnlineAck , Data).


-spec do_deactivate({nonempty_binary() , #deactivate{}} , #data{}) -> #data{}.
do_deactivate({ {_BinPacket , #deactivate{} = MoqaData} , { Subscribers , Requests}} , 
	Data =#data{
		socket = Socket,
		backend_partitions_states = BackendPartitionsStates,
		user = Username
		}) ->
	{Worker , Res} = moqa_backend:read_backend_record(Username , BackendPartitionsStates),
	ok = moqa_backend:release_backend_worker(Worker , Username),
	NewData = case Res of
			[_Record] ->
				_Data0 = unsubscribe_all_users(Subscribers , Data),
				_Data1 = subcnl_all_requests(Requests , Data),
				{Worker , _} = moqa_backend:read_backend_record(Username , BackendPartitionsStates),
				ok = moqa_backend:delete_backend_record(Worker , Username , BackendPartitionsStates),
				init_data(Data);
			[] ->
				Data
		  end,					
	ok = send_ack(MoqaData , Socket),	     
	NewData.


-spec do_disconnect({nonempty_binary() , #disconnect{}} , #data{}) -> #data{}.
do_disconnect({_BinPacket , #disconnect{} = MoqaData} , 
	Data =#data{
		socket = Socket,
		user = Username,
		online_users = OnlineUsers
		}) ->
	Notification = {disconnect , Username},
	ok = send_notifications(Notification , OnlineUsers),
	ok = send_notification(Notification , moqa_server),
	NewData = init_data(Data),
	ok = send_ack(MoqaData , Socket),
	NewData.


-spec do_publish({nonempty_binary() , #publish{}} , #data{}) -> #data{}.
do_publish({_BinPacket , #publish{
			packet_identifier = PacketIdentifier,
			source = Username,
			destination = Destination
			} = MoqaData
		} = Packet ,  
	Data =#data{
		socket = Socket,
		backend_partitions_states = BackendPartitionsStates,
		user = Username,
		roster_users_states = RosterUsersStates
		}) ->
	{Worker , Res} = moqa_backend:read_backend_record(Destination , BackendPartitionsStates),
	case Res of
		[] ->
			ok = moqa_backend:release_backend_worker(Worker , Destination),
			ok = send_ack(MoqaData , Socket),
			Data;
		[Record] ->
			{ _ , _ , _ , _ , BlackList , _ , _ , _ } = Record,
			case lists:member(Username  , BlackList) of
				true ->
					ok = moqa_backend:release_backend_worker(Worker , Destination),
					ok = send_ack(MoqaData , Socket),
					Data;
				_ ->
					Key = {Username , PacketIdentifier},
					OnlinePacket = {Key , Packet},	
					case maps:find(Destination , RosterUsersStates) of
						{ok , Pid} when is_pid(Pid) ->
							ok = moqa_backend:release_backend_worker(Worker , Destination),
							send_packet_to_server_and_enqueue(Pid , OnlinePacket , Data);
						{ok , _LastSeen} ->
							ok = send_offline_packet(Worker , Record , Packet , BackendPartitionsStates),
							ok = send_ack(MoqaData , Socket),
							Data;

						error ->
							case moqa_server:get_user_state(Destination) of
								Pid when is_pid(Pid) ->
									ok = moqa_backend:release_backend_worker(Worker , Destination),
									send_packet_to_server_and_enqueue(Pid , OnlinePacket , Data);
								_ ->
									ok = send_offline_packet(Worker , Record , Packet , BackendPartitionsStates),
									ok = send_ack(MoqaData , Socket),
									Data
							end
					end
			end
	end.


-spec do_pubcomp({nonempty_binary() , #pubcomp{}} , #data{}) -> #data{}.
do_pubcomp({_BinPacket , #pubcomp{
				packet_identifier = PacketIdentifier,
				destination = Destination
				} = MoqaData
		} = Packet ,
	Data =#data{
		socket = Socket,
		backend_partitions_states = BackendPartitionsStates,
		user = Username,
		roster_users_states = RosterUsersStates
		}) ->
	case maps:get(Destination , RosterUsersStates) of
		Pid when is_pid(Pid) ->
			Key = {Username , PacketIdentifier},
			OnlinePacket = {Key , Packet},
			send_packet_to_server_and_enqueue(Pid , OnlinePacket , Data);
		_ ->
			ok = send_offline_packet(Destination , Packet , BackendPartitionsStates),
			ok = send_ack(MoqaData , Socket),
			Data
	end.


-spec do_subscribe({nonempty_binary() , #subscribe{}} , #data{}) -> #data{}.
do_subscribe({_SentBinPacket , #subscribe{
				packet_identifier = PacketIdentifier,
				source = Username, 
				destination = Destination
					} = MoqaData
		} = Packet , 
	Data =#data{
		socket = Socket,
		backend_partitions_states = BackendPartitionsStates,
		user = Username,
		subscriptions_queue = SubscriptionsQueue
		}) ->
	{Worker , Res} = moqa_backend:read_backend_record(Destination , BackendPartitionsStates),
	ok = moqa_backend:release_backend_worker(Worker , Destination),
	case Res of
		[] ->
			ok = send_ack(MoqaData , Socket),
			Data;
		[Record] ->
			{ _ , _ , _ , _ , BlackList , _ , _ , _ } = Record,
			case lists:member(Username , BlackList) of
				true ->
					ok = send_ack(MoqaData , Socket),
					Data;
				_ ->
					ok = moqa_backend:update_backend_record({add_subscription , subscriptions_queue} , {Destination , ?BINOUT} , Username , BackendPartitionsStates),
					ok = moqa_backend:update_backend_record({add_subscription , subscriptions_queue} , {Username , ?BININ}  , Destination , BackendPartitionsStates),
					NewSubscriptionsQueue = SubscriptionsQueue#{Destination => ?BINOUT},
					NewData = Data#data{subscriptions_queue = NewSubscriptionsQueue},
					case moqa_server:get_user_state(Destination) of
						Pid when is_pid(Pid) ->
							Notification = {subscription_request , Username},
							ok = send_notification(Notification , Pid),
							Key = {Username , PacketIdentifier},
							OnlinePacket = {Key , Packet},
							send_packet_to_server_and_enqueue(Pid , OnlinePacket , NewData);
						_ ->
							ok = send_offline_packet(Destination , Packet , BackendPartitionsStates),
							ok = send_ack(MoqaData , Socket),
							NewData
					end
			end
	end.


-spec do_subcnl({nonempty_binary() , #subcnl{}} , #data{}) -> #data{}.
do_subcnl({_BinPacket , #subcnl{
			destination = Destination
			} = MoqaData
		} , 
	Data =#data{
		socket = Socket
		}) ->
	NewData = subcnl_user(Destination , Data),
	ok = send_ack(MoqaData , Socket),
	NewData.


-spec do_subresp({nonempty_binary() , #subresp{}} , #data{}) -> #data{}.
do_subresp({_BinPacket , #subresp{
			packet_identifier = PacketIdentifier,
			source =  Username, 
			destination = Destination, 
			response = Response
				} = MoqaData 
		} = Packet ,
	Data =#data{
		socket = Socket,
		backend_partitions_states = BackendPartitionsStates,
		user = Username
		}) ->
	case Response of
		1 ->
			ok = moqa_backend:update_backend_record({remove_subscription , subscriptions_queue} , Destination , Username , BackendPartitionsStates),
			ok = moqa_backend:update_backend_record({remove_subscription , subscriptions_queue} , Username , Destination , BackendPartitionsStates),			
			NewData = subscribe(Destination , Data),
			case maps:get(Destination , NewData#data.roster_users_states) of
				Pid when is_pid(Pid) ->
					Updates = #{Destination => ?BINON},
					Roster =#roster{updates = Updates},
					ClientInfo = moqalib_encoder:encode_packet(Roster),
					gen_tcp:send(Socket , ClientInfo),
					Notification = {subscription_accepted , Username},
					ok = send_notification(Notification , Pid),
					Key = {Username , PacketIdentifier},
					OnlinePacket = {Key , Packet},
					send_packet_to_server_and_enqueue(Pid , OnlinePacket , NewData);
				LastSeenOrUndefined ->
					Updates = #{Destination => LastSeenOrUndefined},
					Roster =#roster{updates = Updates},
					ClientInfo = moqalib_encoder:encode_packet(Roster),
					gen_tcp:send(Socket , ClientInfo),
					ok = send_offline_packet(Destination , Packet , BackendPartitionsStates),
					ok = send_ack(MoqaData , Socket),
					NewData
				end;
		0 ->	
			NewData = subcnl_user(Destination , Data),		
			ok = send_ack(MoqaData , Socket),
			NewData
	end.

					
-spec do_unsubscribe({nonempty_binary() , #unsubscribe{}} , #data{}) -> #data{}.
do_unsubscribe({_BinPacket , #unsubscribe{ 
					destination = Destination
					} = MoqaData
				} ,
	Data =#data{
		socket = Socket
		}) ->
	NewData = unsubscribe_user(Destination , Data),
	ok = send_ack(MoqaData , Socket),
	NewData.


-spec do_block({nonempty_binary() , #block{}} , #data{}) -> #data{}.
do_block({_BinPacket , #block{
			destination = Destination
			} = MoqaData
		} , 
	Data =#data{
		socket = Socket,
		backend_partitions_states = BackendPartitionsStates,
		user = Username,
		roster_users_states = RosterUsersStates,
		subscriptions_queue = SubscriptionsQueue
		}) ->
	{Worker , Res} = moqa_backend:read_backend_record(Destination , BackendPartitionsStates),
	ok = moqa_backend:release_backend_worker(Worker , Destination),
	case Res of
		[] ->
			ok = send_ack(MoqaData , Socket),
			Data;

		[_Record] ->
			NewData = case maps:find(Destination , RosterUsersStates) of
					{ok , _Val} ->
						unsubscribe_user(Destination , Data);
					error ->
						case maps:find(Destination , SubscriptionsQueue) of
							{ok , _Val} ->
								subcnl_user(Destination , Data);
							error ->
								Data
						end
				end,
			ok = moqa_backend:update_backend_record({add , black_list} , Destination , Username , BackendPartitionsStates),
			ok = send_ack(MoqaData , Socket),
			NewData
	end.

	
-spec do_unblock({nonempty_binary() , #unblock{}} , #data{}) -> ok.
do_unblock({_BinPacket , #unblock{
				destination = Destination
				} = MoqaData
			} ,
		#data{
			socket = Socket,
			backend_partitions_states = BackendPartitionsStates,
			user = Username
			}
		) ->	
	ok = moqa_backend:update_backend_record({remove , black_list} , Destination , Username , BackendPartitionsStates),
	ok = send_ack(MoqaData , Socket),
	ok.


-spec do_ping({nonempty_binary() , #ping{}} , #data{}) -> ok.
do_ping({_BinPacket , #ping{} = MoqaData} , 
	#data{
		socket = Socket
		}) ->		
	ok = send_ack(MoqaData , Socket),
	ok.


-spec subscribe(nonempty_binary() , #data{}) -> #data{}.
subscribe(Destination , Data =#data{
				backend_partitions_states = BackendPartitionsStates,
				user = Username,
				roster_users_states = RosterUsersStates,
				online_users = OnlineUsers,
				subscriptions_queue = SubscriptionsQueue
				}
		) ->
	ok = moqa_backend:update_backend_record({add , roster} , Destination , Username , BackendPartitionsStates),
	ok = moqa_backend:update_backend_record({add , roster} , Username , Destination , BackendPartitionsStates),
	{NewRosterUsersStates , NewOnlineUsers} = case moqa_server:get_user_state(Destination) of
		undefined ->
			{RosterUsersStates#{Destination => off} , OnlineUsers};
		Pid when is_pid(Pid) ->
			{RosterUsersStates#{Destination => Pid} , [Pid | OnlineUsers]};
		LastSeen ->
			{RosterUsersStates#{Destination => LastSeen} , OnlineUsers}
	end,
	NewSubscriptionsQueue = maps:remove(Destination , SubscriptionsQueue),
	NewData = Data#data{
		roster_users_states = NewRosterUsersStates,
		online_users = NewOnlineUsers,
		subscriptions_queue = NewSubscriptionsQueue	 
		},
	NewData.


-spec unsubscribe(nonempty_binary() , #data{}) -> #data{}.
unsubscribe(Destination , Data =#data{
				backend_partitions_states = BackendPartitionsStates,
				user = Username,
				roster_users_states = RosterUsersStates,
				online_users = OnlineUsers
				}
		) ->
	ok = moqa_backend:update_backend_record({remove , roster} , Destination , Username , BackendPartitionsStates),
	ok = moqa_backend:update_backend_record({remove , roster} , Username , Destination , BackendPartitionsStates),
	DestinationState = maps:get(Destination , RosterUsersStates , undefined),
	NewRosterUsersStates = maps:remove(Destination , RosterUsersStates),
	NewOnlineUsers = lists:delete(DestinationState , OnlineUsers),
	NewData = Data#data{
		roster_users_states = NewRosterUsersStates,
		online_users = NewOnlineUsers
		},	
	NewData.


-spec subcnl_user(nonempty_binary() , #data{}) -> #data{}.
subcnl_user(Destination , Data =#data{
				backend_partitions_states = BackendPartitionsStates,
				user = Username ,
				subscriptions_queue = SubscriptionsQueue
			}
		) ->
	ok = moqa_backend:update_backend_record({remove_subscription , subscriptions_queue} , Destination , Username , BackendPartitionsStates),
	ok = moqa_backend:update_backend_record({remove_subscription , subscriptions_queue} , Username , Destination , BackendPartitionsStates),
	NewSubscriptionsQueue = maps:remove(Destination , SubscriptionsQueue),
	NewData = Data#data{subscriptions_queue = NewSubscriptionsQueue},
	case moqa_server:get_user_state(Destination) of
		Pid when is_pid(Pid) ->
			Notification = {subscription_canceled , Username},
			ok = send_notification(Notification , Pid);
		_ ->
			ok
	end,
	NewData.


-spec unsubscribe_user(nonempty_binary() , #data{}) -> #data{}.
unsubscribe_user(Destination , Data =#data{
				user = Username
				}
		) ->
	Res = moqa_server:get_user_state(Destination),
	NewData = unsubscribe(Destination , Data),
	case Res of
		Pid when is_pid(Pid) ->
			Notification = {unsubscribe , Username},
			ok = send_notification(Notification , Pid);
		_ ->
			ok
	end,
	NewData.	


-spec connected_handle_server_notification(pid() , {atom() , nonempty_binary()} , #data{}) -> #data{}.
connected_handle_server_notification(From , {deactivate , User} , Data) ->
	connected_handle_server_notification(From , {unsubscribe , User} , Data);


connected_handle_server_notification(From , {presence , User} , 
	Data =#data{
		socket = Socket,
		roster_users_states = RosterUsersStates,
		online_users = OnlineUsers
		}) ->
	NewRosterUsersStates = RosterUsersStates#{User => From},
	NewOnlineUsers = [From | OnlineUsers],
	Updates =#{User => ?BINON},
	Roster =#roster{updates = Updates},
	ClientInfo = moqalib_encoder:encode_packet(Roster),
	gen_tcp:send(Socket , ClientInfo),
	NewData =Data#data{
		roster_users_states = NewRosterUsersStates,
		online_users = NewOnlineUsers
		},
	NewData;


connected_handle_server_notification(_From , {subscription_request , User} , 
	Data =#data{
		socket = Socket,
		subscriptions_queue = SubscriptionsQueue
		}) ->
	NewSubscriptionsQueue = SubscriptionsQueue#{User => ?BININ},
	Updates = #{User => ?BININ},
	Subscriptions =#subscriptions{updates = Updates},
	ClientInfo = moqalib_encoder:encode_packet(Subscriptions),
	gen_tcp:send(Socket , ClientInfo),
	NewData = Data#data{subscriptions_queue = NewSubscriptionsQueue},
	NewData;


connected_handle_server_notification(From , {subscription_accepted , User} , 
	Data =#data{
		socket = Socket,
		roster_users_states = RosterUsersStates,
		online_users = OnlineUsers,
		subscriptions_queue = SubscriptionsQueue
		}) ->
	NewRosterUsersStates = RosterUsersStates#{User => From},
	NewOnlineUsers = [From | OnlineUsers],
	NewSubscriptionsQueue = maps:remove(User , SubscriptionsQueue),
	Updates1 =#{User => ?BINON},
	Roster =#roster{updates = Updates1},
	ClientInfo1 = moqalib_encoder:encode_packet(Roster),
	gen_tcp:send(Socket , ClientInfo1),
	Updates2 =#{User => ?BINUNDEFINED},
	Subscriptions =#subscriptions{updates = Updates2},
	ClientInfo2 = moqalib_encoder:encode_packet(Subscriptions),
	gen_tcp:send(Socket , ClientInfo2),
	NewData = Data#data{
		roster_users_states = NewRosterUsersStates,
		online_users = NewOnlineUsers,
		subscriptions_queue = NewSubscriptionsQueue
		},
	NewData;


connected_handle_server_notification(_From , {subscription_canceled , User} , 
	Data =#data{
		socket = Socket,
		subscriptions_queue = SubscriptionsQueue
		}) ->
	NewSubscriptionsQueue = maps:remove(User , SubscriptionsQueue),
	Updates =#{User => ?BINUNDEFINED},
	Subscriptions =#subscriptions{updates = Updates},
	ClientInfo = moqalib_encoder:encode_packet(Subscriptions),
	gen_tcp:send(Socket , ClientInfo),
	NewData = Data#data{subscriptions_queue = NewSubscriptionsQueue},
	NewData;

	
connected_handle_server_notification(_From , {unsubscribe , User} , 
	Data =#data{
		socket = Socket,
		roster_users_states = RosterUsersStates,
		online_users = OnlineUsers
		}) ->
	UserState = maps:get(User , RosterUsersStates , undefined),
	NewRosterUsersStates = maps:remove(User , RosterUsersStates),
	NewOnlineUsers = lists:delete(UserState , OnlineUsers),
	Updates =#{User => ?BINUNDEFINED},
	Roster =#roster{updates = Updates},
	ClientInfo = moqalib_encoder:encode_packet(Roster),
	gen_tcp:send(Socket , ClientInfo),
	NewData = Data#data{
		roster_users_states = NewRosterUsersStates,
		online_users = NewOnlineUsers
		},
	NewData;


connected_handle_server_notification(_From , { _DisconnectReason , User} , 
	Data =#data{
		socket = Socket,
		roster_users_states = RosterUsersStates,
		online_users = OnlineUsers
		}) ->
	LastSeen = erlang:universaltime(),
	UserState = maps:get(User , RosterUsersStates),
	NewRosterUsersStates = RosterUsersStates#{User => LastSeen},
	NewOnlineUsers = lists:delete(UserState , OnlineUsers),
	Updates =#{User => LastSeen},
	Roster =#roster{updates = Updates},
	ClientInfo = moqalib_encoder:encode_packet(Roster),
	gen_tcp:send(Socket , ClientInfo),
	NewData = Data#data{
		roster_users_states = NewRosterUsersStates,
		online_users = NewOnlineUsers
		},
	NewData.

	
-spec send_ack(moqalib_checker:moqa_data() , port()) -> ok.
send_ack(MoqaData , Socket) ->
	ClientReply = moqalib_encoder:encode_ack(MoqaData),
	gen_tcp:send(Socket , ClientReply),
	ok.


-spec init_data(#data{}) -> #data{}.
init_data(Data) ->
	Data#data{
		status = not_connected,
		user = undefined,
		keep_alive = undefined,
		roster_users_states = undefined,
		client_roster = undefined,
		online_users = undefined,
		packets_queue = undefined,
		subscriptions_queue = undefined,
		broker = undefined,
		timer = undefined
		}.


-spec restart_timer(reference() , pos_integer()) -> reference().
restart_timer(Timer , KeepAlive) ->
	erlang:cancel_timer(Timer),
	erlang:start_timer(KeepAlive , self() , {'expired timeout' , 'keep alive'}).


-spec send_online_packet({nonempty_binary() , moqalib_checker:moqa_data()} , pid()) -> ok.
send_online_packet(Packet , Pid) ->
	erlang:send(Pid , packet(Packet)),
	ok.


-spec send_online_ack({nonempty_binary() , moqalib_checker:moqa_data()} , pid()) -> ok.
send_online_ack(Packet , Pid) ->
	erlang:send(Pid , ack(Packet)),
	ok.


-spec send_offline_packet(pid() , tuple() , {nonempty_binary() , moqalib_checker:moqa_data()} , map()) -> ok.
send_offline_packet(Pid , Record , Packet , BackendPartitionsStates)
	when is_tuple(Record) 
		->
	UserTuple = moqa:update_record_field({add , packets_queue} , Packet , Record),
	moqa_backend:write_backend_record(Pid , UserTuple , BackendPartitionsStates),
	ok.


-spec send_offline_packet(nonempty_binary() , {nonempty_binary() , moqalib_checker:moqa_data()} , map()) -> ok.
send_offline_packet(Destination , Packet , BackendPartitionsStates) ->
	moqa_backend:update_backend_record({add , packets_queue} , Packet , Destination , BackendPartitionsStates),
	ok.

				
-spec send_notifications(tuple() , [ pid() ]) -> ok.
send_notifications(Notification , OnlineUsers) ->
[send_notification(Notification , Pid) || Pid <- OnlineUsers],
ok.


-spec send_notification(tuple() , moqa_server | pid()) -> ok.
send_notification(Notification , moqa_server) ->
	moqa_server:notification(notification(Notification)),
	ok;


send_notification(Notification , Server) ->
	erlang:send(Server , notification(Notification)),
	ok.


notification(Notification) ->
	{self() , {'new notification' , Notification}}.


packet(Packet) ->
	{self() , {'new packet' ,  Packet}}.


ack(Packet) ->
	{self() , {'new ack' , Packet}}.


-spec unsubscribe_all_users( [ nonempty_binary() ] , #data{} ) -> #data{}.
unsubscribe_all_users([] , Data) ->
	Data;


unsubscribe_all_users([Destination | Tail] , Data) ->
	NewData = unsubscribe_user(Destination , Data),
	unsubscribe_all_users(Tail , NewData).


-spec subcnl_all_requests( [ nonempty_binary() ] , #data{} ) -> #data{}.
subcnl_all_requests([] , Data) ->
	Data;


subcnl_all_requests([Destination | Tail] , Data) ->
	NewData = subcnl_user(Destination , Data),
	subcnl_all_requests(Tail , NewData).

		
-spec enqueue({nonempty_binary() , pos_integer} , {nonempty_binary() , moqalib_checker:moqa_data()} , reference() , pid() , #data{})
				-> #data{}.
enqueue(Key , Packet , Timer , Pid , Data =#data{broker = Broker}) ->
	NewBroker = Broker#{Key => {Packet , Timer , Pid}},
	NewData = Data#data{broker = NewBroker},
	NewData.


-spec dequeue({nonempty_binary , pos_integer} , #data{}) -> 
			{ {nonempty_binary() , moqalib_checker:moqa_data()} , reference() , pid() , #data{} } |
			error.
dequeue(Key , Data =#data{broker = Broker}) ->
	case maps:take(Key , Broker) of
		{{Packet , Timer , Pid} , NewBroker} ->
			NewData = Data#data{broker = NewBroker},
			{Packet , Timer , Pid , NewData};
		error ->
			error	
	end.	


send_packet_to_server_and_enqueue(Pid , {Key , Packet} = OnlinePacket , Data) ->
	ok = send_online_packet(OnlinePacket , Pid),
	Timer = erlang:start_timer(?SERVER_SERVER_TIMEOUT , self() , {'expired timeout' , Key}),
	enqueue(Key , Packet , Timer , Pid , Data).


dequeue_and_send_ack_to_client(Pid , {Key , {BinPacket , MoqaData}} , 
	Data =#data{
		socket = Socket
		}) ->
	case dequeue(Key , Data) of
		{{_SentBinPacket , SentMoqaData} , Timer , Pid , NewData} ->
			case moqalib_checker:check_waiting_ack(MoqaData , SentMoqaData) of
				true ->
					erlang:cancel_timer(Timer),
					gen_tcp:send(Socket , BinPacket),
					{keep_state , NewData};
				_ ->
					{stop , 'unexpected data from server'}
			end;
		_ ->
			{keep_state , Data}
	end.


send_packet_to_client_and_enqueue(Pid , {Key , {BinPacket , _MoqaData} = Packet} , 
	Data =#data{
		socket = Socket,
		user = Username
		}) ->
	gen_tcp:send(Socket , BinPacket),
	Timer = erlang:start_timer(?SERVER_CLIENT_TIMEOUT , self() , {'expired timeout' , Username}),
	NewData = enqueue(Key , Packet , Timer , Pid , Data),
	{keep_state , NewData}.


dequeue_and_send_ack_to_server({Key , {_BinPacket , MoqaData}} = OnlineAck , Data) ->
	{{_SentBinPacket , SentMoqaData} , Timer , Pid , NewData} = dequeue(Key , Data),
	case moqalib_checker:check_waiting_ack(MoqaData , SentMoqaData) of
		true ->
			erlang:cancel_timer(Timer),
			ok = send_online_ack(OnlineAck , Pid),
			{keep_state , NewData};
		_ ->
			{stop , 'unexpected data from client'}
	end.



