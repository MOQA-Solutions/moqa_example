{application , 'molqa' ,

 	[

		{description , "simple client for moqa server"},

		{vsn , "0.1.0"},

		{modules , ['molqa_app' , 'molqa_sup' , 'molqa' , 'molqa_interface' , 'molqa_checker' ,

			    'molqa_worker' 

			   ] },

		{applications , [kernel , stdlib , moqalib]},

		{mod , {molqa_app , []}},

		{env , [ {port_number , 20} , {keep_alive , 600} ] }


       ]

}.
