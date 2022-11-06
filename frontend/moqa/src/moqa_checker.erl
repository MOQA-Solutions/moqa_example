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


-module(moqa_checker).


-export([check_environment_variables/0]).
-export([check_number_of_partitions/1]).
-export([check_server_not_connected_waiting_data/1]).
-export([check_server_connected_waiting_data/1]).

-include("../include/moqa_data.hrl").


-spec check_environment_variables() -> boolean().
check_environment_variables() ->
	case moqa:get_port_number() of
		{ok , PortNumber} when is_integer(PortNumber),
				       PortNumber > 0 ->
			case moqa:get_number_of_acceptors() of 
				{ok , NumberOfAcceptors} when is_integer(NumberOfAcceptors),
						   	      NumberOfAcceptors > 0 ->
					true;
				_ ->
					false
			end;
		_ ->
			false
	end.


-spec check_number_of_partitions(any()) -> boolean().
check_number_of_partitions(NumberOfPartitions) when is_integer(NumberOfPartitions),
						    NumberOfPartitions > 0 ->
	true;


check_number_of_partitions( _ ) ->
	false.


-spec check_server_not_connected_waiting_data(moqalib_checker:moqa_data()) -> boolean().
check_server_not_connected_waiting_data(#signup{}) ->
	true;


check_server_not_connected_waiting_data(#connect{}) ->
	true;


check_server_not_connected_waiting_data( _ ) ->
	false.


-spec check_server_connected_waiting_data(moqalib_checker:moqa_data()) -> boolean().
check_server_connected_waiting_data(#state{}) ->
	true;


check_server_connected_waiting_data(#deactivate{}) ->
	true;


check_server_connected_waiting_data(#disconnect{}) ->
	true;


check_server_connected_waiting_data(#publish{}) ->
	true;


check_server_connected_waiting_data(#puback{}) ->
	true;


check_server_connected_waiting_data(#pubcomp{}) ->
	true;


check_server_connected_waiting_data(#pubcompack{}) ->
	true;


check_server_connected_waiting_data(#subscribe{}) ->
	true;


check_server_connected_waiting_data(#suback{}) ->
	true;


check_server_connected_waiting_data(#subcnl{}) ->
	true;


check_server_connected_waiting_data(#subresp{}) ->
	true;


check_server_connected_waiting_data(#subrespack{}) ->
	true;


check_server_connected_waiting_data(#unsubscribe{}) ->
	true;


check_server_connected_waiting_data(#block{}) ->
	true;


check_server_connected_waiting_data(#unblock{}) ->
	true;


check_server_connected_waiting_data(#ping{}) ->
	true;


check_server_connected_waiting_data( _ ) ->
	false.



