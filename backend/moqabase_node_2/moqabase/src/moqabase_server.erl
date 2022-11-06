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


-module(moqabase_server).


-export([start_link/1]).
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([code_change/3]).
-export([terminate/2]).
-export([scale_command/2]).
-export([set_scale_level/2]).
-export([get_number_of_procs/0]).
-export([get_state/0]).


-include("../include/moqabase_timers.hrl").
-include("../include/servers.hrl").


-type do_scale_reply() :: {partition_scale_state() , procs_scale_state()}.

-type partition_scale_state() :: scale_already_exists | 
			         partition_scale_complete | 
  			         {partition_scale_incomplete , term()}.

-type procs_scale_state() :: scale_already_exists |
			     procs_scale_complete |
			     {procs_scale_incomplete , term()}.


-record(state , {

	self_partition :: atom(),

	peer_partition :: atom(),

	number_of_procs :: pos_integer(),

	number_of_procs_per_fragment :: pos_integer(),

	peer_node :: atom(),

	frontend_nodes :: [ atom() ]

		}).


-spec start_link(atom()) -> {ok , pid()}.
start_link(Partition) ->
	gen_server:start_link({local,?MODULE} , ?MODULE , [Partition] , []).


init([Partition]) ->
	SelfPartition = Partition,
	PeerPartition = moqabase:get_peer_partition(SelfPartition),
	NumberOfSelfFragments = moqabase_partition:get_number_of_fragments(SelfPartition),
	NumberOfPeerFragments = moqabase_partition:get_number_of_fragments(PeerPartition),
	NumberOfFragments = NumberOfSelfFragments + NumberOfPeerFragments,
	{ok , NumberOfProcsPerFragment} = moqabase:get_number_of_procs_per_fragment(),
	NumberOfProcs = NumberOfFragments * NumberOfProcsPerFragment,
	PeerNode = moqabase:partition_to_node(PeerPartition),
	{ok , FrontendNodes} = moqabase:get_frontend_nodes(),
	FrontendServer = ?PARTITIONS_SERVER,
	ok = broadcast_scale_to_frontend_nodes(SelfPartition , NumberOfProcs , FrontendNodes , FrontendServer),
	State =#state{ 
		self_partition = SelfPartition,
		peer_partition = PeerPartition,
		number_of_procs = NumberOfProcs , 
		number_of_procs_per_fragment = NumberOfProcsPerFragment ,
		peer_node = PeerNode,
		frontend_nodes = FrontendNodes
		},
	{ok , State}.


%%=================================================================================================================================%%

%%						gen_server callback functions 		      			     		   %%

%%=================================================================================================================================%%


handle_call({set_scale_level , {Partition , NewNumberOfFragments}} , _From , 
	State =#state{
		self_partition = Partition
		}) ->
	io:format("~p~n\n" , ["scale in progress...."]),
	do_scale(self , Partition , NewNumberOfFragments , State);


handle_call({set_scale_level , _} , _From , State) ->
	Reply = "scale not authorised",
	{reply , Reply , State};


handle_call({set_scale_level , peer_command , {PeerPartition , NewNumberOfFragments}} , _From ,
	State =#state{
		peer_partition = PeerPartition
		}) ->
	do_scale(peer , PeerPartition , NewNumberOfFragments , State);


handle_call(get_state , _From , State) ->
	Reply = State,
	{reply , Reply , State};


handle_call(_Call , _From , State) ->
	{noreply , State}.


%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


handle_info({From , get_number_of_procs} , 
	State =#state{
		number_of_procs = NumberOfProcs
		}) ->
	erlang:send(From , {number_of_procs , NumberOfProcs}),
	{noreply , State};


handle_info({From , ping} , State) ->
	erlang:send(From , {moqabase_server , pong}),
	{noreply , State};


handle_info(_Info , State) ->
	{noreply , State}.


%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


handle_cast(_Cast , State) ->
	{noreply , State}.


%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


code_change(_OldVsn , State , _) ->

	{ok , State}.


%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++%%


terminate(_Reason , _State) ->

	ok.


%%================================================================================================================================%%

%%				   		end of gen_server callback functions 		      		     		  %%

%%================================================================================================================================%%


do_scale(self , Partition , NewNumberOfFragments , 
	State =#state{
		peer_node = PeerNode,
		frontend_nodes = FrontendNodes
		}) ->
	case moqabase_checker:check_scale_requirements(PeerNode , FrontendNodes) of
		true ->	
			do_scale(Partition , NewNumberOfFragments , State);
		_ ->	
			Reply = 'scale failed',
			{reply , Reply , State}
	end;


do_scale(peer , Partition , NewNumberOfFragments , State) ->
	do_scale(Partition , NewNumberOfFragments , State).


-spec do_scale(atom() , pos_integer() , State) -> {reply , Reply , NewState} when
						  Reply :: do_scale_reply(),
						  State ::#state{},
						  NewState ::#state{}.


do_scale(Partition , NewNumberOfFragments , State) ->
	OldNumberOfFragments = moqabase_partition:get_number_of_fragments(Partition),
	Rate = NewNumberOfFragments - OldNumberOfFragments,
	Scale = if (Rate > 0) -> scale_up;	
		   (Rate < 0) -> scale_down;
		true	      -> no_scale
		end,
	{Reply , NewState} = scale(State , Scale , Partition , abs(Rate) , NewNumberOfFragments),
	{reply , Reply , NewState}.
	

scale(State , no_scale , _ , _ , _) ->
	Reply = {scale_already_exists , scale_already_exists},
	{Reply , State};


scale(State =#state{ 
		self_partition = SelfPartition,
		number_of_procs = NumberOfProcs,
		number_of_procs_per_fragment = NumberOfProcsPerFragment ,
		peer_node = PeerNode
		} , 
		Scale , Partition , Rate , NewNumberOfFragments) ->
	{ConfirmedRate , ConfirmedNewNumberOfFragments , PartitionScaleState} = 
		case moqabase_partition:Scale(Partition , Rate) of
			scale_done -> 
				{Rate , 
				 NewNumberOfFragments , 
				 partition_scale_complete
				};
			{scale_failed , Reason , NewRate} ->
				{NewRate , 
				 moqabase_partition:get_number_of_fragments(Partition) ,
				 {partition_scale_incomplete , Reason}
				}
		end,
	ProcsRate = NumberOfProcsPerFragment * ConfirmedRate,
	NewNumberOfProcs = case Scale of 
				scale_up ->
					 NumberOfProcs + ProcsRate;
				_ -> 
					 NumberOfProcs - ProcsRate
			   end,
	{ConfirmedNewNumberOfProcs , ProcsScaleState} = 
		case moqabase_pool_sup:Scale(NumberOfProcs , NewNumberOfProcs) of
			scale_done ->
				{NewNumberOfProcs , procs_scale_complete};
			{scale_failed , Error} ->
				{moqabase_pool_sup:get_number_of_active_procs(),
				 {procs_scale_failed , Error}
				}
		end,
	ScaleSource = case (Partition =:= SelfPartition) of
		true ->
			rpc:call(PeerNode , ?MODULE , scale_command , [Partition , ConfirmedNewNumberOfFragments]),
			self;
		_ -> 
			peer
	end,
	NewState = State#state{
			number_of_procs = ConfirmedNewNumberOfProcs
		},
	Reply = {PartitionScaleState , ProcsScaleState},
	logger:debug(#{
			'1)Reason' => 'NEW SCALE',
			'2)partition' => Partition,
			'3)origin' => ScaleSource,
			'4)new_number_of_fragments' => ConfirmedNewNumberOfFragments,
			'5)total_number_of_procs' => ConfirmedNewNumberOfProcs
		}),
	{Reply , NewState}.


-spec broadcast_scale_to_frontend_nodes(atom() , pos_integer() , list() , atom()) -> ok.
broadcast_scale_to_frontend_nodes(Partition , NewNumberOfProcs , FrontendNodes , FrontendServer) ->
	[broadcast_scale_to_frontend_node(Partition , NewNumberOfProcs , FrontendNode , FrontendServer) 
	 || FrontendNode <- FrontendNodes],
	ok.


broadcast_scale_to_frontend_node(Partition , NewNumberOfProcs , FrontendNode , FrontendServer) ->
	FrontendAddress = {FrontendServer , FrontendNode},
	erlang:send(FrontendAddress , {update_partitions_states , Partition , NewNumberOfProcs}). 


scale_command(Partition , NewNumberOfFragments) ->
	gen_server:call(?MODULE , {set_scale_level , peer_command  , {Partition , NewNumberOfFragments}}).


set_scale_level(Partition , NewNumberOfFragments) ->
	gen_server:call(?MODULE , {set_scale_level , {Partition , NewNumberOfFragments}} , ?SCALE_TIMEOUT).


get_state() ->
	gen_server:call(?MODULE , get_state).


get_number_of_procs() ->
	erlang:send(?MODULE , {self() , get_number_of_procs}),
	receive
		{number_of_procs , NumberOfProcs} ->
			NumberOfProcs
	after ?STANDARD_TIMEOUT ->
		no_reply
	end.

		

