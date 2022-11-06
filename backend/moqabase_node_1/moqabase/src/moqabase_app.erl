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


-module(moqabase_app).


-behaviour(application).


-export([start/2]).
-export([stop/1]).
	
	
-spec start( _ , _ ) -> {ok , pid()}.
start(_Type , [PartitionNumber]) ->
	case moqabase_checker:check_environment_variables() of
		true ->
			io:format("~p~n\n" , ["moqabase starting in progress...."]),
			case mnesia:create_schema([node()]) of
				ok ->
					ok;
				{ error , { _ , { already_exists , _ } } } ->
					ok;
				{error , Error} ->
					exit(Error)
			end, 
			ok = mnesia:start(),
			try_to_init(PartitionNumber);
		_ ->
			exit('wrong environment variables')
	end.


-spec stop( _ ) -> ok.
stop(_State) ->
	ok.


try_to_init(PartitionNumber) ->
	case moqabase_checker:check_partition_number(PartitionNumber) of
		true ->
			moqabase_logger:init(),
			Partition = moqabase:integer_to_atom(PartitionNumber),
			ok =  moqabase_partition:init(Partition),
			Res = moqabase_sup:start_link(Partition),
			Res;
		_ ->
			exit('wrong partition number')
	end.


