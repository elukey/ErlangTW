-module(gvt).
-export([gvt_controller/2]).

gvt_controller(LPsnum, MaxTimestamp) ->
	timer:sleep(1000),
	broadcast_gvt_request(LPsnum),
	{_, _, EntityLocalMin} = calculate_local_min(receive_all(LPsnum)),
	%error_logger:info_msg("~nGlobal min is ~p~n", [EntityLocalMin]),
	if
		EntityLocalMin >= MaxTimestamp -> 
			error_logger:info_msg("~n~p (controller) has finished, GVT ~p, broadcasting terminate message.. ", [self(), EntityLocalMin]),
			broadcast_prepare_to_terminate(LPsnum),
			receive_all(LPsnum),
			broadcast_terminate(LPsnum);
		
		EntityLocalMin < MaxTimestamp ->
			broadcast_gvt_value(LPsnum, EntityLocalMin),
			gvt_controller(LPsnum, MaxTimestamp)
	end.

calculate_local_min(LocalMinList) ->
	list_utils:first_element(lists:keysort(3, LocalMinList)).


receive_all(Lpsnum) ->
	receive_all_aux(Lpsnum, []).

receive_all_aux(LPsnum, ReceivedList) when LPsnum == 0 -> ReceivedList;
receive_all_aux(LPsnum, ReceivedList) when LPsnum > 0  -> 
	receive 
		Message -> receive_all_aux(LPsnum -1, [Message | ReceivedList])
	end.
	

broadcast_gvt_value(LPs, GVTValue) -> 
	send_all(LPs, {gvt, GVTValue}).

broadcast_gvt_request(LPsnum) ->
	send_all(LPsnum, {compute_local_minimum, self()}).

broadcast_prepare_to_terminate(LPsnum) ->
	send_all(LPsnum, {prepare_to_terminate, self()}).

broadcast_terminate(LPsnum) -> 
	send_all(LPsnum, {terminate, self()}).

send_all(LPs, _) when LPs == 0 -> ok;
send_all(LPs, Message) when LPs > 0 -> 
	get_pid(LPs) ! Message,
	send_all(LPs -1, Message).

get_pid(LPnum) ->
	Pid = global:whereis_name(list_to_existing_atom(string:concat("lp_",integer_to_list(LPnum)))),
	if
		Pid == undefined -> error_logger:error_msg("The pid returned for the LP ~w is undefined, aborting..", [LPnum]);
		Pid /= undefined -> Pid
	end.
