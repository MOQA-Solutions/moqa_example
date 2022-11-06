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


-module(molqa_worker).


-export([start_link/0]).
-export([init/1]).
-export([callback_mode/0]).
-export([not_connected/3]).
-export([before_connected/3]).
-export([connected/3]).
-export([send_client_action/2]).
-export([get_client_state/0]).
-export([get_server_state/0]).


-include("../include/molqa_timers.hrl").
-include("../include/molqa_worker_data.hrl").
-include("../include/moqa_data.hrl").
-include("../include/client_info_data.hrl").



%%==================================================================================================================%%

%% 						  Application Graphical Rules  					    %%

%%==================================================================================================================%%



%%	- "roster" data's field is a map of "User => State" entries
%%	-  if State == "on" that means User is actually online
%%	-  if State == "off" that means the User State is offline and its last time seen connected
%%	   is unknown
%%		- That can happens when the moqa server is restarted and User has not connected yet
%%	-  else State == LastSeen where LastSeen is the last time User was online
%%		- LastSeen is described by "last seen : Month/Day at Hour h Minute"	   
%%	-  the app must display graphically all States of all Users in the roster
%%		-  for example by putting a green circle on online users 
%%	-  the app must update constantly the display when "roster" updated
%%	-  the app must disable sending subscription requests to roster users (already friends)
%%	-  the app must enable unsubscribing from roster users



%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


%%	- "subscriptions" data's field is a map of "User => SubscriptionWay" entries
%%	- if SubscriptionWay == "in" that means we have received a subscription request from User
%%		- the app must disable sending subscription request to User
%%		- the app must enable accepting or rejecting this request 
%%			- for example by two buttons : accept and reject
%%	- else SubscriptionWay == "out" that means we have sent a subscription request to User
%%		- the app must disable sending more subscription requests to User
%%		- the app must enable canceling this request
%%			- for example by a button : cancel
%%	- the app must display graphically all subscription requests 
%%		- for example by ana icon : waiting requests
%%	- the app must update instantly the display when "subscriptions" updated


%%==================================================================================================================%%


%%==================================================================================================================%%


-spec start_link() -> {ok , pid()}.
start_link() ->
	{ok , PortNumber} = molqa:get_port_number(),
	{ok , KeepAlive} = molqa:get_keep_alive(),
	case gen_tcp:connect({127,0,0,1} , PortNumber , [binary , {active , true} , {packet , 4}]) of
		{ok , Socket} ->
			{ok , Pid} = gen_statem:start_link({local , ?MODULE} , ?MODULE , [Socket , KeepAlive] , []),
			gen_tcp:controlling_process(Socket , Pid),
			{ok , Pid};
		{error , Reason} ->
			exit(Reason)
	end.


init([Socket , KeepAlive]) ->
	Data =#data{
		socket = Socket,
		keep_alive = KeepAlive,
		status = not_connected
		},
	{ok , not_connected , Data}.


callback_mode() ->
	state_functions.


%%===================================================================================================================%%

%%						gen_statem callback functions		      			     %%

%%===================================================================================================================%%


not_connected(info , {'new packet' , {Type , Args}} , 
	Data =#data{
		socket = Socket
		}) ->
	case molqa_checker:check_client_not_connected_packet_type(Type) of
		true ->
			{{SentBinPacket , SentMoqaData} , Data0} = create_packet(Type , Args , Data),
			gen_tcp:send(Socket , SentBinPacket),
			Res = waiting_ack_from_server(Socket , SentMoqaData),
			case Res of
				{'ack packet' , {_BinPacket , MoqaData}} ->
					transition(MoqaData , element(4 , SentMoqaData) , Data0);
				_ ->
					{stop , Res}
			end;
		_ ->
			{stop , 'unexpected data from user'}
	end;


not_connected(info , {tcp , Socket , _BinPacket} , #data{socket = Socket}) ->
	{stop , 'unexpected data from server'};


not_connected(info , {tcp_closed , Socket} , #data{socket = Socket}) ->
	{stop , 'socket closed'};


not_connected(info , _Info , Data) ->
	{keep_state , Data};


not_connected(cast , _Cast , Data) ->
	{keep_state , Data};


not_connected({call , From} , get_client_state , Data) ->
	Reply = Data,
	{keep_state , Data , [{ reply , From , Reply}]};


not_connected({call , _From} , _Call , Data) ->
	{keep_state , Data}.


%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


before_connected(info , {tcp , Socket , BinPacket} , Data =#data{socket = Socket}) ->
	try moqalib_parser:parse(BinPacket) of
		MoqaData ->
			case molqa_checker:check_client_before_connected_waiting_data(MoqaData) of
				true ->
					before_connected_handle_server_packet(MoqaData , Data);
				_ ->
					{stop , 'unexpected data from server'}
			end
	catch
		error:Error ->
			{stop , Error};
		exit:Exit ->
			{stop , Exit}
	end;


before_connected(info , {tcp_closed , Socket} , #data{socket = Socket}) ->
	{stop , 'socket closed'};


before_connected(info , _Info , Data) ->
	{keep_state , Data};


before_connected(cast , _Cast , Data) ->
	{keep_state , Data};


before_connected({call , _From} , _Call , Data) ->
	{keep_state , Data}.


%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%				


connected(info , {timeout , _Timer , 'server offline'} , _Data) ->
	{stop , 'server offline'};


connected(info , {timeout , Timer , 'ping server'} , Data =#data{
				timer = Timer,
				packet_identifiers = PacketIdentifiers
				}
		) ->
	{PacketIdentifier , NewPacketIdentifiers} = molqa:get_packet_identifier(PacketIdentifiers),
	Data0 = Data#data{packet_identifiers = NewPacketIdentifiers},
	Ping =#ping{packet_identifier = PacketIdentifier},
	BinPacket = moqalib_encoder:encode_packet(Ping),
	MoqaData = Ping,
	Packet = {BinPacket , MoqaData},
	Key = PacketIdentifier,
	send_packet_to_server_and_enqueue(Key , Packet , Data0);

			 
connected(info , {tcp , Socket , BinPacket} , Data =#data{socket = Socket}) ->
	try moqalib_parser:parse(BinPacket) of
		MoqaData ->
			case molqa_checker:check_client_connected_waiting_data(MoqaData) of
				true ->
					Packet = MoqaData,
					connected_handle_server_packet(Packet , Data);
				_ ->
					{stop , 'unexpected data from server'}
			end
	catch
		error:Error ->
			{stop , Error};
		exit:Exit ->
			{stop , Exit}
	end;

					
connected(info , {'new packet' , {Type , Args}} , Data) ->
	case molqa_checker:check_client_connected_packet_type(Type) of
		true ->
			{{_BinPacket , MoqaData} = Packet , Data0} = create_packet(Type , Args , Data),
			Key = element(2 , MoqaData),
			send_packet_to_server_and_enqueue(Key , Packet , Data0);	
		_ ->
			{stop , 'unexpected data from client'}
	end;

			
connected(info , _Info , Data) ->
	{keep_state , Data};


connected(cast , _Cast , Data) ->
	{keep_state , Data};


connected({call , From} , get_client_state , Data) ->
	Reply = Data,
	{keep_state , Data , [ {reply , From , Reply} ]};


connected({call , From} , get_server_state , Data =#data{socket= Socket}) ->
	Reply = get_server_state(Socket),
	{keep_state , Data , [ {reply , From , Reply} ]};


connected({call , _From} , _Call , Data) ->
	{keep_state , Data}.


%%==================================================================================================================%%

%%					   end of gen_statem callback functions		      			    %%

%%==================================================================================================================%%


-spec waiting_ack_from_server(port() , moqalib_checker:moqa_data()) -> 
						{'ack packet' , {nonempty_binary() , moqalib_checker:moqa_data()}} |
						{error , _}.
waiting_ack_from_server(Socket , SentMoqaData) ->
	receive
		{tcp , Socket , BinPacket} ->
			try moqalib_parser:parse(BinPacket) of
				MoqaData ->
					case moqalib_checker:check_waiting_ack(MoqaData , SentMoqaData) of
						true ->
							{'ack packet' , {BinPacket , MoqaData}};
						_ ->
							{error , 'unexpected data from server'}
					end
			catch 
				error:Error ->
					{error , Error};
				exit:Exit ->
					{error , Exit}
			end
	after ?CLIENT_SERVER_TIMEOUT ->
		{error , 'server offline'}
	end.


transition(#signack{response = 1} , Username , Data =#data{keep_alive = KeepAlive}) ->
	NewKeepAlive = KeepAlive * 1000,
	Data0 = Data#data{
			user = Username , 
			offline_pubcomp_users = [],
			keep_alive = NewKeepAlive
		},
	io:format("~p~n" , ['user successfully signed up']),
	{next_state , before_connected , Data0};


transition(#signack{response = 0} , _Username , Data) ->
	io:format("~p~n" , ['signup failed']),
	{next_state , not_connected , Data};


transition(#connack{response = 1} , Username , Data =#data{keep_alive = KeepAlive}) ->
	NewKeepAlive = KeepAlive * 1000,
	Data0 = Data#data{
			user = Username , 
			offline_pubcomp_users = [],
			keep_alive = NewKeepAlive
		},
	io:format("~p~n" , ['user successfully connected']),
	{next_state , before_connected , Data0};


transition(#connack{response = 0} , _Username , Data) ->
	io:format("~p~n" , ['wrong username or password']),
	{next_state , not_connected , Data}.


before_connected_handle_server_packet(#roster{updates = Updates} , 
	Data =#data{
		keep_alive = KeepAlive,
		offline_pubcomp_users = OfflinePubcompUsers
		}) ->
	Roster = moqalib_parser:decode_updates(Updates),
	List = lists:seq(0 , 255),
	%%  - we can use identifiers up to 65535 but 256 will be more than sufficient
	PacketIdentifiers = [X 
			     || { _ , X} <- lists:sort([{rand:uniform() , Y}
							|| Y <- List
						       ])
			    ],
	Broker =#{},
	NewOfflinePubcompUsers = validate(OfflinePubcompUsers , Roster),
	Timer = erlang:start_timer(KeepAlive - ?STANDARD_TIMEOUT , self() , 'ping server'),
	Data0 = Data#data{
			status = connected,
			roster = Roster,
			timer = Timer,
			packet_identifiers = PacketIdentifiers,
			offline_pubcomp_users = NewOfflinePubcompUsers,
			broker = Broker
		},
	send_pubcomp_packets(Data0);


before_connected_handle_server_packet(#subscriptions{updates = Updates} , Data) ->
	Subscriptions = moqalib_parser:decode_updates(Updates),
	Data0 = Data#data{subscriptions = Subscriptions},	
	{keep_state , Data0};	


before_connected_handle_server_packet(#publish{
					source = Source,
					message = Message
				       } = MoqaData , 
	Data =#data{
		offline_pubcomp_users = OfflinePubcompUsers
		}) ->

	%%  - the app must show that we have a new published message from Source
	%%
	%%  - here I will just write it

	StrSource = binary_to_list(Source),
	StrMessage = binary_to_list(Message),
	io:format("~p~n" , ["new message from : " ++ StrSource]),
	io:format("~p~n" , [StrMessage]),
	NewOfflinePubcompUsers = try_add_user(Source , OfflinePubcompUsers),
	Data0 = Data#data{offline_pubcomp_users = NewOfflinePubcompUsers},
	ack_and_keep_state(before_connected , MoqaData , Data0);


before_connected_handle_server_packet(#pubcomp{source = Source} = MoqaData , Data) ->

	%%  - the app must show that last messages sent to Source have been received by Source
	%%
	%%  - "last messages" means messages sent after the last pubcomp packet was received from Source
	%%
	%%  - it is like facebook messenger blue filled circle
	%%
	%%  - here I will just write it

	StrSource = binary_to_list(Source),
	io:format("~p~n" , ["last messages sent to " ++ StrSource ++ 
		  " have been received by : " ++ StrSource]),
	ack_and_keep_state(before_connected , MoqaData , Data);


before_connected_handle_server_packet(#subscribe{source = Source} = MoqaData , Data) ->

	%%  - show in the app that you have a new subscription request from Source
	%%
	%%  - note this packet will not update data's "subscriptions" field, this last
	%%
	%%    will be updated by another packet "#subscriptions{}"
	%%
	%%  - here I will just write it

	StrSource = binary_to_list(Source),
	io:format("~p~n" , ["new subscription request from : " ++ StrSource]),
	ack_and_keep_state(before_connected , MoqaData , Data);


before_connected_handle_server_packet(#subresp{source = Source} = MoqaData , Data) ->

	%%  - show in the app that Source has accepted your subscription request and become a friend
	%%
	%%  - note this packet will not update data's "roster" field, this last
	%%
	%%    will be updated by another packet "#roster{}"
	%%
	%%  - here I will just write it

	StrSource = binary_to_list(Source),
	io:format("~p~n" , [StrSource ++ " has accepted your subscription request"]),
	ack_and_keep_state(before_connected , MoqaData , Data);


before_connected_handle_server_packet(_AckPacket , Data) ->

	%%  - this maybe an ack Packet corresponding to a previous unterminated operation

	{keep_state , Data}.


connected_handle_server_packet(#subscriptions{updates = Update} , 
	Data =#data{
		subscriptions = Subscriptions
		}) ->
	NewUpdate = moqalib_parser:decode_updates(Update),
	[{User , SubscriptionWay}] = maps:to_list(NewUpdate),
	NewSubscriptions = case SubscriptionWay of
				<<"undefined">> ->
					maps:remove(User , Subscriptions);
				_ ->
					Subscriptions#{User => SubscriptionWay}
			   end,
	Data0 = Data#data{subscriptions = NewSubscriptions},
	{keep_state , Data0};


connected_handle_server_packet(#roster{updates = Update} , 
	Data =#data{
		roster = Roster
		}) ->
	NewUpdate = moqalib_parser:decode_updates(Update),
	[{User , State}] = maps:to_list(NewUpdate),
	NewRoster = case State of
			<<"undefined">> ->
				maps:remove(User , Roster);
			_ ->
				Roster#{User => State}
		    end,
	Data0 = Data#data{roster = NewRoster},
	{keep_state , Data0};


connected_handle_server_packet(#publish{
				source = Source,
				message = Message
				} = MoqaData,
	Data =#data{
		socket = Socket,
		keep_alive = KeepAlive,
		roster = Roster,
		timer = Timer
		}) ->

	%%  - the same thing as described before 

	StrSource = binary_to_list(Source),
	io:format("~p~n" , ["new message from : " ++ StrSource]),
	io:format("~p~n" , [binary_to_list(Message)]),
	BinAckPacket = moqalib_encoder:encode_ack(MoqaData),
	gen_tcp:send(Socket , BinAckPacket),
	NewTimer = restart_timer(Timer , KeepAlive),
	Data0 = Data#data{timer = NewTimer},
	Data1 = case maps:find(Source , Roster) of
			{ok , _Val} ->
				send_pubcomp_packet(Source , Data0);
			_ ->
				Data0
		end,
	{keep_state , Data1};

	
connected_handle_server_packet(#pubcomp{source = Source} = MoqaData , Data) ->

	%%  - same thing as described before

	StrSource = binary_to_list(Source),
	io:format("~p~n" , ["last messages sent to " ++ StrSource ++ " have been received by : " 
		  ++ StrSource]),
	ack_and_keep_state(connected , MoqaData , Data);


connected_handle_server_packet(#subscribe{source = Source} = MoqaData , Data) ->

	%%  - same thing as described before

	StrSource = binary_to_list(Source),
	io:format("~p~n" , ["new subscription request from : " ++ StrSource]),
	ack_and_keep_state(connected , MoqaData , Data);


connected_handle_server_packet(#subresp{source = Source} = MoqaData , Data) ->

	%%  - same thing as described before

	StrSource = binary_to_list(Source),
	io:format("~p~n" , [StrSource ++ " has accepted your subscription request"]),
	ack_and_keep_state(connected , MoqaData , Data);


connected_handle_server_packet(AckPacket , Data) ->
	Key = element(2 , AckPacket),
	dequeue_and_release_identifier(Key , AckPacket , Data).


-spec try_add_user(nonempty_binary() , [nonempty_binary()]) -> [nonempty_binary()].
try_add_user(User , OfflinePubcompUsers) ->
	case lists:member(User , OfflinePubcompUsers) of
		true ->
			OfflinePubcompUsers;
		_ ->
			[User | OfflinePubcompUsers]
	end.


validate(Users , Roster) ->
	Fun = fun(ElementFromUsers , Acc) ->
		NewAcc = case maps:find(ElementFromUsers , Roster) of
				{ok , _Val} ->
					[ElementFromUsers | Acc];
				error ->
					Acc
			 end,
		NewAcc
	      end,
	lists:foldl(Fun , [] , Users).


ack_and_keep_state(State , MoqaData , Data =#data{
					socket = Socket,
					keep_alive = KeepAlive,
					timer = Timer

					}
		) ->
	ServerReply = moqalib_encoder:encode_ack(MoqaData),
	gen_tcp:send(Socket , ServerReply),
	Data0 = case State of
			connected ->
				NewTimer = restart_timer(Timer , KeepAlive),
				Data#data{timer = NewTimer};
			before_connected ->
				Data
		end,
	{keep_state , Data0}.


-spec restart_timer( reference() | undefined , pos_integer() ) -> reference().
restart_timer(Timer , KeepAlive) ->
	case Timer of
		undefined ->
			ok;
		_ ->
			erlang:cancel_timer(Timer)
	end,
	erlang:start_timer(KeepAlive - ?STANDARD_TIMEOUT , self() , 'ping server').


-spec enqueue(pos_integer() , moqalib_checker:moqa_data() , reference() , #data{}) -> #data{}.
enqueue(Key , Packet , Timer , Data =#data{
					broker = Broker
					}
		) ->
	NewBroker = Broker#{Key => {Packet , Timer}},
	Data#data{broker = NewBroker}.


-spec dequeue(pos_integer() , #data{}) -> {moqalib_checker:moqa_data() , reference() , #data{}} | error.
dequeue(Key , Data =#data{
		broker = Broker
		}) ->
	case maps:take(Key , Broker) of 
		{ {Packet , Timer} , NewBroker} ->
			NewData = Data#data{
					broker = NewBroker
					},
			{Packet , Timer , NewData};
		error ->
			error
	end.


send_packet_to_server_and_enqueue(Key , {BinPacket , MoqaData} , 
	Data =#data{
		socket = Socket,
		keep_alive = KeepAlive,
		timer = Timer
		}) ->
	gen_tcp:send(Socket , BinPacket),
	Timer1 = restart_timer(Timer , KeepAlive),
	Data0 = Data#data{timer = Timer1},
	Timer2 = erlang:start_timer(?CLIENT_SERVER_TIMEOUT , self() , 'server offline'),
	Data1 = enqueue(Key , MoqaData , Timer2 , Data0),
	{keep_state , Data1}.


dequeue_and_release_identifier(Key , MoqaData , Data =#data{
							packet_identifiers = PacketIdentifiers
							}
		) ->
	case dequeue(Key , Data) of
		{SentMoqaData , Timer , Data0} ->
			case moqalib_checker:check_waiting_ack(MoqaData , SentMoqaData) of
				true ->
					erlang:cancel_timer(Timer),
					NewPacketIdentifiers = [ Key | PacketIdentifiers ],
					Data1 = Data0#data{packet_identifiers = NewPacketIdentifiers},
					after_ack(SentMoqaData , Data1);
				_ ->
					{stop , 'unexpected data from server'}
			end;
		error ->
			{keep_state , Data}
	end.

		
send_pubcomp_packets(Data =#data{
			offline_pubcomp_users = []
			}
		) ->
	Data0 = Data#data{offline_pubcomp_users = undefined},
	{next_state, connected , Data0};


send_pubcomp_packets(Data =#data{offline_pubcomp_users = [User | OfflinePubcompUsers]}) ->
	Data0 = send_pubcomp_packet(User , Data),
	Data1 = Data0#data{offline_pubcomp_users = OfflinePubcompUsers},
	send_pubcomp_packets(Data1).


-spec send_pubcomp_packet(nonempty_binary() , #data{}) -> #data{}.
send_pubcomp_packet(Destination , Data =#data{
					socket = Socket,
					user = Username,
					keep_alive = KeepAlive,
					timer = Timer,
					packet_identifiers = PacketIdentifiers
					}
		) ->
	{PacketIdentifier , NewPacketIdentifiers} = molqa:get_packet_identifier(PacketIdentifiers),
	Pubcomp =#pubcomp{
			packet_identifier = PacketIdentifier,
			source = Username,
			destination = Destination
			},
	BinPacket = moqalib_encoder:encode_packet(Pubcomp),
	MoqaData = Pubcomp,
	Key = PacketIdentifier,
	gen_tcp:send(Socket , BinPacket),
	Timer1 = restart_timer(Timer , KeepAlive),
	NewData = Data#data{
			timer = Timer1,
			packet_identifiers = NewPacketIdentifiers
		},
	Timer2 = erlang:start_timer(?CLIENT_SERVER_TIMEOUT , self() , 'serveroffline'),
	enqueue(Key , MoqaData , Timer2 , NewData).


after_ack(#deactivate{} , Data) ->
	NewData = init_data(Data),

	%%  - the app must show the first home interface to signup or connect again
	%%
	%%  - here I will just write it
	
	io:format("~p~n" , ["user account has been deactivated successfully"]),
	{next_state , not_connected , NewData};

 
after_ack(#disconnect{} , Data) ->
	NewData = init_data(Data),

	%%  - the app must show the first home interface to signup or connect again
	%%
	%%  - here I will just write it

	io:format("~p~n" , ["user disconnected successfully"]),
	{next_state , not_connected , NewData};

				
after_ack(#publish{destination = Destination} , Data) ->

	%%  - show in the app that last messages sent to Destination 
	%%
	%%    have been received by the server (not yet by Destination)
	%%
	%%  - it is like facebook messenger empty circle
	%%
	%%  - here I will just write it

	StrDestination = binary_to_list(Destination),
	io:format("~p~n" , ["last messages sent to " ++ StrDestination ++ 
			    " have been received by : the server"
			   ]),
	{keep_state , Data};


after_ack(#pubcomp{} , Data) ->
	{keep_state , Data};


after_ack(#subscribe{destination = Destination} , 
	Data =#data{
		subscriptions = Subscriptions
		}) ->
	NewSubscriptions = Subscriptions#{Destination => ?BINOUT},
	Data0 = Data#data{subscriptions = NewSubscriptions},
	{keep_state , Data0};


after_ack(#subcnl{destination = Destination} ,
	Data =#data{
		subscriptions = Subscriptions
		}) ->
	NewSubscriptions = maps:remove(Destination , Subscriptions),
	Data0 = Data#data{subscriptions = NewSubscriptions},
	{keep_state , Data0};


after_ack(#subresp{destination = Destination} ,
	Data =#data{
		subscriptions = Subscriptions
		}) ->
	NewSubscriptions = maps:remove(Destination , Subscriptions),
	Data0 = Data#data{subscriptions = NewSubscriptions},
	{keep_state , Data0};


after_ack(#unsubscribe{destination = Destination} , 
	Data =#data{
		roster = Roster
		}) ->
	NewRoster = maps:remove(Destination , Roster),
	Data0 = Data#data{roster = NewRoster},
	{keep_state , Data0};


after_ack(#block{destination = Destination} ,
	Data =#data{
		roster = Roster,
		subscriptions = Subscriptions
		}) ->
	NewRoster = maps:remove(Destination , Roster),
	NewSubscriptions = maps:remove(Destination , Subscriptions),
	Data0 = Data#data{
			roster = NewRoster,
			subscriptions = NewSubscriptions
		},
	{keep_state , Data0};


after_ack(#unblock{} , Data) ->
	{keep_state , Data};


after_ack(#ping{} , Data) ->
	{keep_state , Data}.


-spec init_data(#data{}) -> #data{}.
init_data(Data =#data{keep_alive = KeepAlive}) ->
	Data#data{
		status = not_connected,
		user = undefined,
		keep_alive = KeepAlive div 1000,
		packet_identifiers = undefined,
		timer = undefined,
		roster = undefined,
		subscriptions = undefined,
		offline_pubcomp_users = undefined,
		broker = undefined
	}.


get_server_state(Socket) ->
	Bin = <<1:8>>,
	gen_tcp:send(Socket , Bin),
	receive
		{tcp , Socket , Reply} ->
			binary_to_term(Reply)
	after 3000 ->
		no_reply
	end.


-spec create_packet(atom() , list() , #data{}) -> { {nonempty_binary() , moqalib_checker:moqa_data()} , #data{} }.
create_packet(signup , [Username , Password] , Data =#data{keep_alive = KeepAlive}) ->
	BinUsername = list_to_binary(Username),
	BinPassword = list_to_binary(Password),
	PacketIdentifier = 1,
	Signup =#signup{
		packet_identifier = PacketIdentifier,
		keep_alive = KeepAlive,
		username = BinUsername,
		password = BinPassword

		},
	MoqaData = Signup,
	BinPacket = moqalib_encoder:encode_packet(MoqaData),
	Packet = {BinPacket , MoqaData},
	{Packet , Data};


create_packet(connect , [Username , Password] , Data =#data{keep_alive = KeepAlive}) ->
	BinUsername = list_to_binary(Username),
	BinPassword = list_to_binary(Password),
	PacketIdentifier = 2,
	Connect =#connect{
		packet_identifier = PacketIdentifier,
		keep_alive = KeepAlive,
		username = BinUsername,
		password = BinPassword
		},
	MoqaData = Connect,
	BinPacket = moqalib_encoder:encode_packet(MoqaData),
	Packet = {BinPacket , MoqaData},
	{Packet , Data};


create_packet(deactivate , [] , 
	Data =#data{
		packet_identifiers = PacketIdentifiers
		}) ->
	{PacketIdentifier , NewPacketIdentifiers} = molqa:get_packet_identifier(PacketIdentifiers),
	NewData = Data#data{packet_identifiers = NewPacketIdentifiers},
	Deactivate =#deactivate{
			packet_identifier = PacketIdentifier
		},
	MoqaData = Deactivate,
	BinPacket = moqalib_encoder:encode_packet(MoqaData),
	Packet = {BinPacket , MoqaData},
	{Packet , NewData};


create_packet(disconnect , [] , 
	Data =#data{
		packet_identifiers = PacketIdentifiers
		}) ->
	{PacketIdentifier , NewPacketIdentifiers} = molqa:get_packet_identifier(PacketIdentifiers),
	NewData = Data#data{packet_identifiers = NewPacketIdentifiers},
	Disconnect =#disconnect{
			packet_identifier = PacketIdentifier
		},
	MoqaData = Disconnect,
	BinPacket = moqalib_encoder:encode_packet(MoqaData),
	Packet = {BinPacket , MoqaData},
	{Packet , NewData};


create_packet(publish , [Destination , Message] , 
	Data =#data{
		user = Source,
		packet_identifiers = PacketIdentifiers
		}) ->
	BinSource = Source,
	BinDestination = list_to_binary(Destination),
	BinMessage = list_to_binary(Message),
	{PacketIdentifier , NewPacketIdentifiers} = molqa:get_packet_identifier(PacketIdentifiers),
	NewData = Data#data{packet_identifiers = NewPacketIdentifiers},
	Publish =#publish{
		packet_identifier = PacketIdentifier,
		source = BinSource,
		destination = BinDestination,
		message = BinMessage
		},
	MoqaData = Publish,
	BinPacket = moqalib_encoder:encode_packet(MoqaData),
	Packet = {BinPacket , MoqaData},
	{Packet , NewData};


create_packet(subscribe , [Destination] ,
	Data =#data{
		user = Source,
		packet_identifiers = PacketIdentifiers
		}) ->
	BinSource = Source,
	BinDestination = list_to_binary(Destination),
	{PacketIdentifier , NewPacketIdentifiers} = molqa:get_packet_identifier(PacketIdentifiers),
	NewData = Data#data{packet_identifiers = NewPacketIdentifiers},
	Subscribe =#subscribe{
			packet_identifier = PacketIdentifier,
			source = BinSource,
			destination = BinDestination
		},
	MoqaData = Subscribe,
	BinPacket = moqalib_encoder:encode_packet(MoqaData),
	Packet = {BinPacket , MoqaData},
	{Packet , NewData};


create_packet(subcnl , [Destination] ,
	Data =#data{
		packet_identifiers = PacketIdentifiers
		}) ->
	BinDestination = list_to_binary(Destination),
	{PacketIdentifier , NewPacketIdentifiers} = molqa:get_packet_identifier(PacketIdentifiers),
	NewData = Data#data{packet_identifiers = NewPacketIdentifiers},
	Subcnl =#subcnl{
		packet_identifier = PacketIdentifier,
		destination = BinDestination
		},
	MoqaData = Subcnl,
	BinPacket = moqalib_encoder:encode_packet(MoqaData),
	Packet = {BinPacket , MoqaData},
	{Packet , NewData};


create_packet(subresp , [Destination , Response] , 
	Data =#data{
		user = Source,
		packet_identifiers = PacketIdentifiers
		}) ->
	BinSource = Source,
	BinDestination = list_to_binary(Destination),
	{PacketIdentifier , NewPacketIdentifiers} = molqa:get_packet_identifier(PacketIdentifiers),
	NewData = Data#data{packet_identifiers = NewPacketIdentifiers},
	Subresp =#subresp{
		packet_identifier = PacketIdentifier,
		source = BinSource,
		destination = BinDestination,
		response = Response
		},
	MoqaData = Subresp,
	BinPacket = moqalib_encoder:encode_packet(MoqaData),
	Packet = {BinPacket , MoqaData},
	{Packet , NewData};


create_packet(unsubscribe , [Destination] , 
	Data =#data{
		packet_identifiers = PacketIdentifiers
		}) ->
	BinDestination = list_to_binary(Destination),
	{PacketIdentifier , NewPacketIdentifiers} = molqa:get_packet_identifier(PacketIdentifiers),
	NewData = Data#data{packet_identifiers = NewPacketIdentifiers},
	Unsubscribe =#unsubscribe{
			packet_identifier = PacketIdentifier,
			destination = BinDestination
		},
	MoqaData = Unsubscribe,
	BinPacket = moqalib_encoder:encode_packet(MoqaData),
	Packet = {BinPacket , MoqaData},
	{Packet , NewData};


create_packet(block , [Destination] ,
	Data =#data{
		packet_identifiers = PacketIdentifiers
		}) ->
	BinDestination = list_to_binary(Destination),
	{PacketIdentifier , NewPacketIdentifiers} = molqa:get_packet_identifier(PacketIdentifiers),
	NewData = Data#data{packet_identifiers = NewPacketIdentifiers},
	Block =#block{
		packet_identifier = PacketIdentifier,
		destination = BinDestination
		},
	MoqaData = Block,
	BinPacket = moqalib_encoder:encode_packet(MoqaData),
	Packet = {BinPacket , MoqaData},
	{Packet , NewData};


create_packet(unblock , [Destination] , 
	Data =#data{
		packet_identifiers = PacketIdentifiers
		}) ->
	BinDestination = list_to_binary(Destination),
	{PacketIdentifier , NewPacketIdentifiers} = molqa:get_packet_identifier(PacketIdentifiers),
	NewData = Data#data{packet_identifiers = NewPacketIdentifiers},
	Unblock =#unblock{
		packet_identifier = PacketIdentifier,
		destination = BinDestination
		},
	MoqaData = Unblock,
	BinPacket = moqalib_encoder:encode_packet(MoqaData),
	Packet = {BinPacket , MoqaData},
	{Packet , NewData}.


send_client_action(Type , Args) ->
	erlang:send(?MODULE , packet({Type , Args})).


packet(Packet) ->
	{'new packet' , Packet}.


get_client_state() ->
	gen_statem:call(?MODULE , get_client_state , ?STANDARD_TIMEOUT).


get_server_state() ->
	gen_statem:call(?MODULE , get_server_state , ?STANDARD_TIMEOUT).



		 
