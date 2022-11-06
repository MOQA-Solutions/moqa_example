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


-module(moqabase_pool_sup).


-export([start_link/1]).
-export([init/1]).
-export([scale_up/2]).
-export([scale_down/2]).
-export([start_workers/2]).
-export([get_number_of_procs/0]).
-export([get_number_of_active_procs/0]).


-type scale_result() :: scale_done | {scale_failed , term()}.


-include("../include/moqabase_timers.hrl").
-include("../include/servers.hrl").


-spec start_link(atom()) -> {ok , pid()}.
start_link(Partition) ->
	supervisor:start_link({local , ?MODULE} , ?MODULE , [Partition]).


init([Partition]) ->
	NumberOfProcs = get_number_of_procs(),
	spawn(?MODULE , start_workers , [1 , NumberOfProcs]),
	SupFlags =#{
		strategy => simple_one_for_one,
		intensity => 1,
	 	period => 5 
		},
	ChildSpecs = [ 
			#{
				id => moqabasepoolworker,
				start => {moqabase_pool_worker , start_link , [Partition] },
				restart => permanent,
				shutdown => brutal_kill,
				type => worker,
				modules => [moqabase_pool_worker]
			}
		] , 
	{ok , {SupFlags , ChildSpecs}}.


-spec scale_up(pos_integer() , pos_integer()) -> scale_result().
scale_up(OldNumberOfProcs , NewNumberOfProcs) ->
	start_workers(OldNumberOfProcs + 1 , NewNumberOfProcs).


-spec scale_down(pos_integer() , pos_integer()) -> scale_result().
scale_down(OldNumberOfProcs , NewNumberOfProcs) ->
	shutdown_workers(NewNumberOfProcs + 1 , OldNumberOfProcs).


start_workers(FirstID , LastID) ->
	try_to_start_workers(FirstID , LastID).


try_to_start_workers(CurrentID , LastID) when CurrentID > LastID ->
	scale_done;


try_to_start_workers(CurrentID , LastID ) ->
	try start_worker(CurrentID) of
		{ok , _Child} ->
			try_to_start_workers(CurrentID + 1 , LastID)
	catch
		error:Error ->
			{scale_failed , Error}
	end.


start_worker(ID) ->
	supervisor:start_child(?MODULE , [moqabase:integer_to_atom(ID)]).


shutdown_workers(LastID , FirstID) ->
	try_to_shutdown_workers(LastID , FirstID).


try_to_shutdown_workers(LastID , CurrentID) when CurrentID < LastID ->
	scale_done;


try_to_shutdown_workers(LastID , CurrentID) ->
	try shutdown_worker(CurrentID) of
		ok ->
			try_to_shutdown_workers(LastID , CurrentID - 1)
	catch
		error:Error ->
			{scale_failed , Error}
	end.


shutdown_worker(ID) ->
	ProcRegName = moqabase:integer_to_atom(ID),
	Pid = erlang:whereis(ProcRegName),
	supervisor:terminate_child(?MODULE , Pid).


-spec get_number_of_procs() -> pos_integer().
get_number_of_procs() ->
	case moqabase_server:get_number_of_procs() of
		no_reply ->
			get_number_of_procs();
		NumberOfProcs ->
			NumberOfProcs
	end.


-spec get_number_of_active_procs() -> pos_integer().
get_number_of_active_procs() ->
	ProcsCount = supervisor:count_children(?MODULE),
	proplists:get_value(active , ProcsCount).


