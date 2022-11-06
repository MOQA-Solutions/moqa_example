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


-module(molqa_interface).


-export([signup/2]).
-export([connect/2]).
-export([deactivate/0]).
-export([disconnect/0]).
-export([publish/2]).
-export([subscribe/1]).
-export([subcnl/1]).
-export([subresp/2]).
-export([unsubscribe/1]).
-export([block/1]).
-export([unblock/1]).
-export([get_client_state/0]).
-export([get_server_state/0]).


signup(Username , Password) ->
	Args = [Username , Password],
	action(signup , Args).


connect(Username , Password) ->
	Args = [Username , Password],
	action(connect , Args).


deactivate() ->
	Args = [],
	action(deactivate , Args).


disconnect() ->
	Args = [],
	action(disconnect , Args).


publish(Destination , Message) ->
	Args = [Destination , Message],
	action(publish , Args).


subscribe(Destination) ->
	Args = [Destination],
	action(subscribe , Args).


subcnl(Destination) ->
	Args = [Destination],
	action(subcnl , Args).


subresp(Destination , Response) ->
	Args = [Destination , Response],
	action(subresp , Args).


unsubscribe(Destination) ->
	Args = [Destination],
	action(unsubscribe , Args).



block(Destination) ->
	Args = [Destination],
	action(block , Args).


unblock(Destination) ->
	Args = [Destination],
	action(unblock , Args).


get_client_state() ->
	molqa_worker:get_client_state().



get_server_state() ->
	molqa_worker:get_server_state().


action(Type , Args) ->
	molqa_worker:send_client_action(Type , Args).




