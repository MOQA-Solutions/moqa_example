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


-record(state , {

	}).



-record(roster , {

	updates :: map()

	}).



-record(subscriptions , {

	updates :: map()

	}).



-record(signup , {

	packet_identifier :: pos_integer(),

	keep_alive :: pos_integer(),

	username :: nonempty_binary(),

	password :: nonempty_binary()

	}).



-record(signack , {

	packet_identifier :: pos_integer(),

	response :: 0 | 1

	}).

	

-record(deactivate , {

	packet_identifier :: pos_integer()

	}).



-record(deactivack , {

	packet_identifier :: pos_integer()

	}).



-record(connect , {

	packet_identifier :: pos_integer(),

	keep_alive :: pos_integer(),

	username :: nonempty_binary(),

	password :: nonempty_binary()

	}).



-record(connack , {

	packet_identifier :: pos_integer(),

	response :: 0 | 1

	}).



-record(disconnect , {

	packet_identifier :: pos_integer()

	}).



-record(disconnack , {

	packet_identifier :: pos_integer()

	}).



-record(publish , {

	packet_identifier :: pos_integer(),

	source :: nonempty_binary(),

	destination :: nonempty_binary(),

	message ::nonempty_binary()

	}).



-record(puback , {

	packet_identifier :: pos_integer(),

	destination :: nonempty_binary()

	}).



-record(pubcomp , {

	packet_identifier :: pos_integer(),

	source :: nonempty_binary(),

	destination :: nonempty_binary()

	}).



-record(pubcompack , {

	packet_identifier :: pos_integer(),

	destination :: nonempty_binary()

	}).



-record(subscribe , {

	packet_identifier :: pos_integer(),

	source :: nonempty_binary(),

	destination :: nonempty_binary()

	}).



-record(suback , {

	packet_identifier :: pos_integer(),

	destination :: nonempty_binary()

	}).



-record(subcnl , {

	packet_identifier :: pos_integer(),

	destination :: nonempty_binary()

	}).



-record(subcnlack , {

	packet_identifier :: pos_integer()

	}).



-record(subresp , {

	packet_identifier :: pos_integer(),

	source :: nonempty_binary(),

	destination :: nonempty_binary(),

	response :: 0 | 1

	}).



-record(subrespack , {

	packet_identifier :: pos_integer(),

	destination :: nonempty_binary()

	}).



-record(unsubscribe  , {

	packet_identifier :: nonempty_binary(),

	destination :: nonempty_binary()

	}).



-record(unsuback , {

	packet_identifier :: pos_integer()

	}).



-record(block , {

	packet_identifier :: pos_integer(),

	destination :: nonempty_binary()

	}).



-record(blockack , {

	packet_identifier :: pos_integer()

	}).



-record(unblock , {

	packet_identifier :: pos_integer(),

	destination :: nonempty_binary()

	}).



-record(unblockack , {

	packet_identifier :: pos_integer()

	}).



-record(ping , {

	packet_identifier :: pos_integer()

	}).



-record(pingack , {

	packet_identifier :: pos_integer()

	}).



	
