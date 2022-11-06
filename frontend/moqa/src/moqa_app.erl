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


-module(moqa_app).


-behaviour(application).

-export([start/2]).
-export([stop/1]).


-spec start(_ , [pos_integer()]) -> {ok , pid()}.
start(_Type , [NumberOfPartitions]) ->
	io:format("~p~n\n" , ["moqa starting in progress...."]),
	case moqa_checker:check_environment_variables() of
		true ->
			try_to_init(NumberOfPartitions);
		_ ->
			exit('wrong environment variables')
	end.


-spec stop(_) -> ok.
stop(_) ->
	ok.


try_to_init(NumberOfPartitions)  ->
	case moqa_checker:check_number_of_partitions(NumberOfPartitions) of
		true ->
			moqa_logger:init(),
			Res =  moqa_sup:start_link(NumberOfPartitions),
			Res;
		false ->
			exit('wrong number of partitions')
	end.



