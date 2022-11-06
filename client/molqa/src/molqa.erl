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


-module(molqa).


-export([get_port_number/0]).
-export([get_keep_alive/0]).
-export([get_packet_identifier/1]).


-spec get_port_number() -> {ok , term()} | undefined.
get_port_number() ->
	application:get_env(molqa , port_number).


-spec get_keep_alive() -> {ok , term()} | undefined.
get_keep_alive() ->
	application:get_env(molqa , keep_alive).


-spec get_packet_identifier( [pos_integer()] ) -> {pos_integer() , [ pos_integer() ] | [] }. 
get_packet_identifier([H | Tail]) ->
	{H , Tail}.


