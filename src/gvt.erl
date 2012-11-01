%
% This file is part of ErlangTW.  ErlangTW is free software: you can
% redistribute it and/or modify it under the terms of the GNU General Public
% License as published by the Free Software Foundation, version 2.
%
% This program is distributed in the hope that it will be useful, but WITHOUT
% ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
% FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
% details.
%
% You should have received a copy of the GNU General Public License along with
% this program; if not, write to the Free Software Foundation, Inc., 51
% Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
%
% Copyright 2012, Luca Toscano, Gabriele D'Angelo, Moreno Marzolla
% Computer Science Department, University of Bologna, Italy

-module(gvt).
-export([gvt_controller/2]).
-include("common.hrl").

gvt_controller(LPsnum, MaxTimestamp) ->
	timer:sleep(1000),
	broadcast_gvt_request(LPsnum),
	{_, _, EntityLocalMin} = calculate_local_min(receive_all(LPsnum)),
	%error_logger:info_msg("~nGlobal min is ~p~n", [EntityLocalMin]),
	if
		EntityLocalMin >= MaxTimestamp -> 
			error_logger:info_msg("~n~p (controller) has finished, GVT ~p, broadcasting terminate message.. ", [self(), EntityLocalMin]),
			broadcast_prepare_to_terminate(LPsnum),
			receive_all(LPsnum);
			%broadcast_terminate(LPsnum);
		
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
	Message = #message{type=gvt, payload=GVTValue},
	send_all(LPs, Message).

broadcast_gvt_request(LPsnum) ->
	Message = #message{type=compute_local_minimum, payload=self()},
	send_all(LPsnum, Message).

broadcast_prepare_to_terminate(LPsnum) ->
	Message = #message{type=prepare_to_terminate, payload=self()},
	send_all(LPsnum, Message).

send_all(LPs, _) when LPs == 0 -> ok;
send_all(LPs, Message) when LPs > 0 -> 
	LPId = string:concat("lp_",integer_to_list(LPs)),
	gen_fsm:send_event({global, LPId}, Message),
	send_all(LPs -1, Message).
