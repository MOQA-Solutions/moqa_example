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


-module(molqa_sup).


-export([start_link/0]).
-export([init/1]).


-spec start_link() -> {ok , pid()}.
start_link() ->
	supervisor:start_link({local , ?MODULE} , ?MODULE , []).


init([]) ->
	SupFlags =#{ strategy => one_for_one,
		     intensity => 1,
		     period => 5
		   },
	ChildSpecs = [
			#{id => molqaserver,
			  start => {molqa_worker , start_link , []},
			  restart => permanent,
			  shutdown => brutal_kill,
			  type => worker,
			  modules => [molqa_server]
			 }
		     ],
	{ok , {SupFlags , ChildSpecs}}.


