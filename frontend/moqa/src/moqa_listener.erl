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


-module(moqa_listener).


-export([init_acceptors/2]).
-export([start_acceptor/1]).
-export([init/1]).
-export([handle_info/2]).
-export([handle_cast/2]).
-export([handle_call/3]).
-export([code_change/3]).
-export([terminate/2]).


-include("../include/moqa_timers.hrl").


-record(state , { 

	parent :: pid(),

	listen_socket :: port()

		}).		  


-spec init_acceptors(pos_integer() , port()) -> [ pid() ].
init_acceptors(NumberOfAcceptors , ListenSocket) ->
	[start_acceptor(ListenSocket) || _ <- lists:seq(1 , NumberOfAcceptors)].


-spec start_acceptor(port()) -> pid().
start_acceptor(ListenSocket) ->
	{ok , Pid} = gen_server:start_link(?MODULE , [self() , ListenSocket] , []),
	Pid.


init([Parent , ListenSocket]) ->
	process_flag(trap_exit , true),
	State =#state{
		parent = Parent,
		listen_socket = ListenSocket
		},
	erlang:send(self() , accept),
	{ok , State}.


%%================================================================================================================%%

%%					  gen_server callback functions		      			  	  %%

%%================================================================================================================%%


handle_info({'EXIT' , Parent , Reason} , State =#state{parent = Parent}) ->
	{stop , {'parent exit' , Reason} , State};


handle_info(accept , State =#state{
				listen_socket = ListenSocket	
		}) ->
	case gen_tcp:accept(ListenSocket) of
		{ok , Socket} ->
			Pid = moqa_worker:start_link(Socket),
			gen_tcp:controlling_process(Socket , Pid),
			erlang:send(self() , accept),
			{noreply , State};
		{error , Reason} ->
			exit(Reason)
	end;	


handle_info(_Info , State) ->
	{noreply , State}.


%%+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


handle_cast(_Cast , State) ->

	{noreply , State}.


%%+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


handle_call(_Call , _From , State) ->

	{noreply , State}.


%%+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


code_change(_OldVsn , State , _) ->

	{ok , State}.


%%+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


terminate(Reason , State) ->

	{Reason , State}.


%%===============================================================================================================%%

%%				   end of gen_server callback functions		      			  	 %%

%%===============================================================================================================%%

