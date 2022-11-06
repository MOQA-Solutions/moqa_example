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


-module(moqa_logger).


-export([init/0]).


-spec init() -> ok.
init() ->
	logger:set_primary_config(level , debug),
	logger:set_handler_config(default , level , notice),
	Config1 =#{
		   config => #{
			       file => "logging/info_logging.log",
  			       max_no_bytes => 10 * 1024 * 1024,
		 	       max_no_files => 10,
			       sync_mode_qlen => 100,
			       drop_mode_qlen => 1000,
 		               flush_qlen =>2000
			      },		  
		  level => info,
		  filters => [
			      { just_info_logs , {fun logger_filters:level/2 , {stop , neq , info}} }
			     ]
		 },
	Config2 =#{
		   config => #{
			       file => "logging/debug_logging.log",
 			       max_no_bytes => 10 * 1024 * 1024,
			       max_no_files => 10,
			       sync_mode_qlen => 100,
			       drop_mode_qlen => 1000,
			       flush_qlen => 2000
			      },
		   level => debug,
		   filters => [
			       { just_debug_logs , {fun logger_filters:level/2 , {stop , neq , debug}} }
			      ],
		   formatter => { logger_formatter , #{
						       single_line => false,
						       legacy_header => true
						      }
				}
		  },	
	logger:add_handler(info_logging_handler , logger_std_h , Config1),
	logger:add_handler(debug_logging_handler , logger_std_h , Config2),
	ok.

