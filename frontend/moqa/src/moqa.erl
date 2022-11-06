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


-module(moqa).


-export([get_number_of_acceptors/0]).
-export([get_port_number/0]).
-export([get_secondary_partition/1]).
-export([integer_to_atom/1]).
-export([atom_to_integer/1]).
-export([partition_to_node/1]).
-export([node_to_partition/1]).
-export([update_record_field/3]).
-export([get_subscribers/1]).
-export([get_subscriptions_requests/1]).


-include("../include/servers.hrl").
-include("../include/moqa_timers.hrl").
-include("../include/moqa_worker_data.hrl").


-spec get_number_of_acceptors() -> {ok , term()} | undefined .
get_number_of_acceptors() ->
	application:get_env(moqa , number_of_acceptors).


-spec get_port_number() -> {ok , term()} | undefined. 
get_port_number() ->
	application:get_env(moqa , port_number).


-spec get_secondary_partition(atom()) -> atom().
get_secondary_partition(PrimaryPartition) ->
	PrimaryPartitionNumber = atom_to_integer(PrimaryPartition),
	SecondaryPartitionNumber = get_secondary_partition_number(PrimaryPartitionNumber),
	integer_to_atom(SecondaryPartitionNumber).


-spec get_secondary_partition_number(pos_integer()) -> pos_integer().
get_secondary_partition_number(PrimaryPartitionNumber) ->
	if (PrimaryPartitionNumber rem 2 == 0) -> PrimaryPartitionNumber - 1;
	true				       -> PrimaryPartitionNumber + 1
	end.


-spec integer_to_atom(pos_integer()) -> atom().
integer_to_atom(Number) ->
	list_to_atom(integer_to_list(Number)).


-spec atom_to_integer(atom()) -> pos_integer().
atom_to_integer(Atom) ->
	list_to_integer(atom_to_list(Atom)).


-spec partition_to_node(atom()) -> atom().
partition_to_node(Partition) ->

		%%  - In this case we have just 1 island (2 nodes), if you have more islands 
		
		%%    you should update this function

	case Partition of
		'1' -> 
			'ghani1@ABDELGHANI';
		'2' -> 
			'ghani2@ABDELGHANI';
		_ ->
			 exit('unknown partition')
	end.


-spec node_to_partition(atom()) -> atom().
node_to_partition(Node) ->
	case Node of
		'ghani1@ABDELGHANI' ->
			'1';
		'ghani2@ABDELGHANI' ->
			'2';
		_ ->
			exit('unknown node')
	end.


-spec update_record_field({atom() , atom()} , term() , tuple()) -> tuple().
update_record_field({OP , password} , OPPassword ,
	{_Partition , Username , _Password , Roster , BlackList , PacketsQueue , SubscriptionsQueue , UnterminatedOperation}) ->
	{Username , update_field(OP , OPPassword) , Roster, BlackList , PacketsQueue , SubscriptionsQueue , UnterminatedOperation};


update_record_field({OP , roster} , OPUsername , 
	{_Partition , Username , Password , Roster , BlackList , PacketsQueue , SubscriptionsQueue , UnterminatedOperation}) ->
	{Username , Password , update_field(OP , OPUsername , Roster) , BlackList , PacketsQueue , SubscriptionsQueue , UnterminatedOperation};


update_record_field({OP , black_list} , OPUsername , 
	{_Partition , Username , Password , Roster , BlackList , PacketsQueue , SubscriptionsQueue , UnterminatedOperation}) ->
	{Username , Password , Roster , update_field(OP , OPUsername , BlackList) , PacketsQueue , SubscriptionsQueue , UnterminatedOperation};


update_record_field({OP , packets_queue} , OPPacket , 
	{_Partition , Username , Password , Roster , BlackList , PacketsQueue , SubscriptionsQueue , UnterminatedOperation}) ->
	{Username , Password , Roster , BlackList , update_field(OP , OPPacket , PacketsQueue) , SubscriptionsQueue , UnterminatedOperation};


update_record_field({OP , subscriptions_queue} , OPRequest , 
	{_Partition , Username , Password , Roster , BlackList , PacketsQueue , SubscriptionsQueue , UnterminatedOperation}) ->
	{Username , Password , Roster , BlackList , PacketsQueue , update_field(OP , OPRequest , SubscriptionsQueue) , UnterminatedOperation};


update_record_field({OP , unterminated_operation} , OPOperation , 
	{_Partition , Username , Password , Roster , BlackList , PacketsQueue , SubscriptionsQueue , _UnterminatedOperation}) ->
	{Username , Password , Roster , BlackList , PacketsQueue , SubscriptionsQueue , update_field(OP , OPOperation)}.


update_field(new , NewValue) ->
	NewValue.


update_field(add_subscription , {Destination , RequestWay} , SubscriptionsQueue) ->
	SubscriptionsQueue#{Destination => RequestWay};


update_field(add , OPVal , List) ->
	case lists:member(OPVal , List) of
		true ->
			List;
		false ->
			[OPVal | List]
	end;


update_field(remove_subscription , Destination , SubscriptionsQueue) ->
	maps:remove(Destination , SubscriptionsQueue);


update_field(remove , head , [_H | Tail]) ->
	Tail;


update_field(remove , OPVal , List) ->
	lists:delete(OPVal , List).


-spec get_subscribers( #data{} ) -> [ nonempty_binary() ].
get_subscribers(#data{
			roster_users_states = RosterUsersStates
			}
		) ->
	maps:keys(RosterUsersStates).


-spec get_subscriptions_requests( #data{} ) -> [ nonempty_binary() ].
get_subscriptions_requests(#data{
				subscriptions_queue = SubscriptionsQueue
				}
		) ->
	maps:keys(SubscriptionsQueue).


