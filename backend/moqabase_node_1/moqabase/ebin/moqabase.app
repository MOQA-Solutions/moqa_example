{application , 'moqabase' , 

 [

	{description , "fault tolerant and highly scalable database server"},

	{vsn , "0.1"},

	{modules , ['moqabase' , 'moqabase_app' , 'moqabase_sup' , 'moqabase_partition' , 

		    'moqabase_pool_sup' , 'moqabase_pool_worker' , 'moqabase_server' , moqabase_logger ,

		     moqabase_checker , moqabase_interface 

		   ] },

	{applications , [kernel , stdlib , crypto]},

	{mod , {moqabase_app , [1]} },

	{env , [{number_of_procs_per_fragment , 100} , {frontend_nodes , ['ghani@ABDELGHANI']}

	       ]
	}

 ]}.


	

