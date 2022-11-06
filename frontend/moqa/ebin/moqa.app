{application , 'moqa' ,

 [

	{description , "full , small and fast chat server based on customised mqtt protocol"},

	{vsn , "0.1"},

	{modules , ['moqa_app' , 'moqa_sup' , 'moqa' , 'moqa_listener' , 'moqa_server' , 'partitions_states_server' , 

		    'moqa_checker' , 'moqa_logger' , 'moqa_interface' , 'moqa_backend' , 'moqa_worker'

		   ] },

	{applications , [kernel , stdlib , moqalib]},

	{mod , {moqa_app , [2]} },

	{env , [{port_number , 20} , {number_of_acceptors , 2} ] }

 ]}.

	
