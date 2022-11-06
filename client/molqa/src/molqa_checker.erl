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


-module(molqa_checker).


-export([check_environment_variables/0]).
-export([check_client_not_connected_packet_type/1]).
-export([check_client_connected_packet_type/1]).
-export([check_client_before_connected_waiting_data/1]).
-export([check_client_connected_waiting_data/1]).


-include("../include/moqa_data.hrl").


-define(NOT_CONNECTED_TYPES , [signup , connect]).
-define(CONNECTED_TYPES , [deactivate , disconnect , publish , subscribe , subcnl , subresp , unsubscribe , block , unblock]).


-spec check_environment_variables() -> boolean().
check_environment_variables() ->
	case molqa:get_port_number() of 
		{ok , PortNumber} when is_integer(PortNumber),
				       PortNumber > 0 ->
			case molqa:get_keep_alive() of
				{ok , KeepAlive} when is_integer(KeepAlive),
						      KeepAlive > 0 ->
					true;
				_ ->
					false
			end;
		_ ->
			false
	end.


-spec check_client_before_connected_waiting_data(moqalib_checker:moqa_data()) -> boolean().
check_client_before_connected_waiting_data(#roster{}) ->
	true;


check_client_before_connected_waiting_data(#subscriptions{}) ->
	true;


check_client_before_connected_waiting_data(#deactivack{}) ->
	true;


check_client_before_connected_waiting_data(#suback{}) ->
	true;


check_client_before_connected_waiting_data(#subrespack{}) ->
	true;


check_client_before_connected_waiting_data(#subcnlack{}) ->
	true;


check_client_before_connected_waiting_data(#unsuback{}) ->
	true;


check_client_before_connected_waiting_data(#blockack{}) ->
	true;


check_client_before_connected_waiting_data(#publish{}) ->
	true;


check_client_before_connected_waiting_data(#pubcomp{}) ->
	true;


check_client_before_connected_waiting_data(#subscribe{}) ->
	true;


check_client_before_connected_waiting_data(#subresp{}) ->
	true;


check_client_before_connected_waiting_data( _ ) ->
	false.


-spec check_client_connected_waiting_data(moqalib_checker:moqa_data()) -> boolean().
check_client_connected_waiting_data(#roster{}) ->
	true;


check_client_connected_waiting_data(#subscriptions{}) ->
	true;


check_client_connected_waiting_data(#disconnack{}) ->
	true;


check_client_connected_waiting_data(#deactivack{}) ->
	true;


check_client_connected_waiting_data(#publish{}) ->
	true;


check_client_connected_waiting_data(#puback{}) ->
	true;


check_client_connected_waiting_data(#pubcomp{}) ->
	true;


check_client_connected_waiting_data(#pubcompack{}) ->
	true;


check_client_connected_waiting_data(#subscribe{}) ->
	true;


check_client_connected_waiting_data(#suback{}) ->
	true;


check_client_connected_waiting_data(#subcnlack{}) ->
	true;


check_client_connected_waiting_data(#subresp{}) ->
	true;


check_client_connected_waiting_data(#subrespack{}) ->
	true;


check_client_connected_waiting_data(#unsuback{}) ->
	true;


check_client_connected_waiting_data(#blockack{}) ->
	true;


check_client_connected_waiting_data(#unblockack{}) ->
	true;


check_client_connected_waiting_data(#pingack{}) ->
	true;


check_client_connected_waiting_data( _ ) ->
	false.


-spec check_client_not_connected_packet_type(atom()) -> boolean().
check_client_not_connected_packet_type(Type) ->
	lists:member(Type , ?NOT_CONNECTED_TYPES).


check_client_connected_packet_type(Type) ->
	lists:member(Type , ?CONNECTED_TYPES).


