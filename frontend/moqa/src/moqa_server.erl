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


-module(moqa_server).


-export([start_link/0]).
-export([init/1]).
-export([handle_info/2]).
-export([handle_cast/2]).
-export([handle_call/3]).
-export([code_change/3]).
-export([terminate/2]).
-export([get_state/0]).
-export([get_user_state/1]).
-export([notification/1]).


-include("../include/moqa_timers.hrl").


-record(state ,{ 

	parent :: pid(),

	listen_socket :: port(),

	acceptors :: list(),

	users_states :: map()

		}).
		 

-spec start_link() -> {ok , pid()}.
start_link() ->
	gen_server:start_link({local , ?MODULE} , ?MODULE , [self()] , []).


init([Parent]) ->
	process_flag(trap_exit , true),
	{ok , Port} = moqa:get_port_number(),
	{ok , NumberOfAcceptors} = moqa:get_number_of_acceptors(),
	Options = [binary , {active , true} , {packet , 4} , {backlog , 1024} , {nodelay , true}],
	case gen_tcp:listen(Port , Options) of
		{ok , ListenSocket} ->
			Acceptors = moqa_listener:init_acceptors(NumberOfAcceptors , ListenSocket),
			State =#state{ 
				parent = Parent,
				listen_socket = ListenSocket,
				acceptors = Acceptors,
				users_states = #{}
			     	     },
			{ok , State};
		{error , Reason} ->
			{stop , Reason}
	end.


%%=====================================================================================================================================%%

%%							gen_server callback functions		      			    	       %%

%%=====================================================================================================================================%%


handle_info({'EXIT' , Parent , Reason} , State =#state{parent = Parent}) ->
	{stop , {'parent exit' , Reason} , State};


handle_info({'EXIT' , Pid , Reason} , State =#state{
						listen_socket = ListenSocket,
						acceptors = Acceptors
						}) ->
	logger:debug(#{
			'Reason' => {'ACCEPTOR EXIT' , Reason}
		}),
	NewAcceptor = moqa_listener:start_acceptor(ListenSocket),
	NewAcceptors = [NewAcceptor|lists:delete(Pid , Acceptors)],
	NewState = State#state{acceptors = NewAcceptors},
	{noreply , NewState};


handle_info({From , {'new notification' , {presence , Username}}} , State =#state{users_states = UsersStates}) ->
	NewUsersStates = UsersStates#{Username => From},
	NewState = State#state{users_states = NewUsersStates},
	{noreply , NewState};


handle_info({_From , {'new notification' , {deactivate , Username}}} , State =#state{users_states = UsersStates}) ->
	NewUsersStates = maps:remove(Username , UsersStates),
	NewState = State#state{users_states = NewUsersStates},
	{noreply , NewState};


handle_info({_From , {'new notification' , {_Reason , Username}}} , State =#state{users_states = UsersStates}) ->
	LastSeen = erlang:universaltime(),
	NewUsersStates = UsersStates#{Username => LastSeen},
	NewState = State#state{users_states = NewUsersStates},
	{noreply , NewState};


handle_info({From , {get_user_state , Username}} , 
	State =#state{
		users_states = UsersStates
		}) ->
	Reply = case maps:find(Username , UsersStates) of
			{ok , Val} ->
				Val;
			error ->
				undefined
		end,
	erlang:send(From , {user_state , Reply}),
	{noreply , State};

	
handle_info(_Info , State) ->
	{noreply , State}.


%%+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


handle_cast(_Cast , State) ->
	{noreply , State}.


%%+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


handle_call(get_state , _From , State) ->
	Reply = State,
	{reply , Reply , State};


handle_call(_Call , _From , State) ->
	Reply = no_reply,
	{reply , Reply , State}.


%%+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


code_change( _OldVsn , State , _ ) ->
	{ok , State}.


%%+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


terminate(Reason , State) ->
	{Reason , State}.


%%======================================================================================================================================%%

%%						end of gen_server callback functions		      			    		%%

%%======================================================================================================================================%%


get_state() ->
	gen_server:call(?MODULE , get_state).


-spec get_user_state(nonempty_binary()) -> pid() | tuple() | undefined.
get_user_state(Username) ->
	erlang:send(?MODULE , {self() , {get_user_state , Username}}),
	receive
		{user_state , UserState} ->
			UserState
	after ?STANDARD_TIMEOUT ->
		exit('moqa server unavailable')
	end.

		
notification(Notification) ->
	erlang:send(?MODULE , Notification).

