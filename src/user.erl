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

-module(user).
-export([lp_function/2, start_function/1, newton_radix/2, terminate_model/1, newton_radix_foldl/2]).

-include("user_include.hrl").
-include("common.hrl").



start_function(Lp) ->
	StartModel = get_modelstate(Lp),
	LpsNum = StartModel#state.lps,
	EntitiesNum = StartModel#state.entities,
	LpId = StartModel#state.lp_id,
	FirstEntity = get_first_entity_index(LpId, EntitiesNum, LpsNum),
	LastEntity = get_last_entity_index(LpId, EntitiesNum, LpsNum), 
	error_logger:info_msg("~nI am ~p and my first entity is ~p and last is ~p", [self(), FirstEntity, LastEntity]),
	GeneratedEvents = generate_start_events(StartModel),
	SeedProposal = StartModel#state.seed * LpId + EntitiesNum,
	if 
		SeedProposal rem 2 == 0 -> NewLpSeed = StartModel#state.seed + LpId + EntitiesNum + 1;
		SeedProposal rem 2 /= 0 -> NewLpSeed = StartModel#state.seed + LpId + EntitiesNum
	end,
	StartLp = Lp#lp_status{init_model_state=StartModel, model_state=StartModel#state{seed=NewLpSeed}},
	send_multiple_events(GeneratedEvents,  StartLp).


send_multiple_events([], Lp) -> Lp;
send_multiple_events([Event|Tail], Lp) ->
	LPSender = Event#message.lpSender,
	LPReceiver = Event#message.lpReceiver,
	Payload = Event#message.payload,
	Timestamp = Event#message.timestamp,
	send_multiple_events(Tail, lp:send_event(LPSender, LPReceiver, Payload, Timestamp, Lp)).

generate_start_events(Model) ->
	%NumberOfEvents = trunc(Model#state.density * Model#state.entities),
	NumberOfEvents =10,
	generate_start_events_aux(Model, NumberOfEvents, []).
	
	
generate_start_events_aux(_, Number, Acc) when Number == 0 -> Acc;
generate_start_events_aux(ModelState, Number, Acc) ->
	{EventTimestamp, NewSeed} =  lcg:get_exponential_random(ModelState#state.seed),
	{EntitySender, NewSeed1} = lcg:get_random(NewSeed, 1, ModelState#state.entities),
	{EntityReceiver, NewSeed2} = lcg:get_random(NewSeed1, 1, ModelState#state.entities),
	LpSender = which_lp_controls(EntitySender, ModelState#state.entities, ModelState#state.lps),
	LpReceiver = which_lp_controls(EntityReceiver, ModelState#state.entities, ModelState#state.lps),
	LPId = get_lpid_from_number(ModelState#state.lp_id),
	if
		LpSender == LPId -> 
			NewInitEvent = #message{type=event, lpSender=LpSender, lpReceiver=LpReceiver, 
									timestamp=EventTimestamp, seqNumber=0, 
									payload=#payload{entitySender=EntitySender, entityReceiver=EntityReceiver, value=0}},
			generate_start_events_aux(ModelState#state{seed=NewSeed2}, Number-1, [NewInitEvent|Acc]);
		LpSender /= LPId  -> 
			generate_start_events_aux(ModelState#state{seed=NewSeed2}, Number-1, Acc)
	end.
		

get_lpid_from_number(Number) ->
	string:concat("lp_",integer_to_list(Number)).

lp_function(Event, Lp) ->
	io:format("I am processing ~p with pid ~p\n", [Event, self()]),
	Workload = Lp#lp_status.model_state#state.workload,
	newton_radix(2, Workload),
	#payload{entityReceiver=EntityReceiver} = Event#message.payload,
	ModelState = get_modelstate(Lp),
	MaxTimestap = ModelState#state.max_timestamp,
	if
		Lp#lp_status.timestamp >= MaxTimestap -> Lp;
		Lp#lp_status.timestamp < MaxTimestap ->
			{NewEvent, NewModelState} = generate_event_from_sender(EntityReceiver, Event#message.timestamp, 1, ModelState),
			#message{lpSender=LPSender, lpReceiver=LPReceiver, payload=Payload, timestamp=Timestamp} = NewEvent, 
			lp:send_event(LPSender, LPReceiver, Payload, Timestamp, Lp#lp_status{model_state=NewModelState})
	end.

terminate_model(_) -> 
	error_logger:info_msg("~n~p has finished~n",[self()]).

generate_event_from_sender(EntitySender, Timestamp, PayloadValue, ModelState) ->
	{ExpDeltaTime, NewSeed} =  lcg:get_exponential_random(ModelState#state.seed),
	NewTimestamp = Timestamp + ExpDeltaTime,
	{EntityReceiver, NewSeed2} = lcg:get_random(NewSeed, 1, ModelState#state.entities),
	LpReceiver = which_lp_controls(EntityReceiver, ModelState#state.entities, ModelState#state.lps),
	Payload = #payload{entitySender=EntitySender, entityReceiver=EntityReceiver, value=PayloadValue},
	LPSender = get_lpid_from_number(ModelState#state.lp_id),
	Event = #message{type=event, lpSender=LPSender, lpReceiver=LpReceiver, payload=Payload, seqNumber=0, timestamp=NewTimestamp},
	NewModelState = ModelState#state{seed=NewSeed2},
	{Event, NewModelState}.

%% 
%% Newton's radix function implemented using the foldl bif
%% Note: worst performances respect the newton_radix method 
%%
newton_radix_foldl(Number, FPOp) ->
	TotalIterations = trunc(FPOp/5),
	Result = lists:foldl(fun(_, Acc) -> 0.5 * Acc * (3 - (Number * Acc * Acc)) end , 0.5, lists:seq(1, TotalIterations)),
	1/Result.


%%
%% Newton's radix function implementation
%%
newton_radix(Number, FPOp) ->
	newton_radix_aux(Number, trunc(FPOp/5), 1, 0.5).

newton_radix_aux(_, TotalIteration, CurrentIterationNum, Acc) when CurrentIterationNum == TotalIteration -> 1/Acc;
newton_radix_aux(Number, TotalIteration, CurrentIterationNum, Acc) ->
	NewAcc = 0.5 * Acc * (3 - (Number * Acc * Acc)),
	newton_radix_aux(Number, TotalIteration, CurrentIterationNum + 1, NewAcc).

get_modelstate(Lp) ->
	Lp#lp_status.model_state.


%get_pid(LP) ->
%	LPString = "lp_" ++ integer_to_list(LP),
%	Pid = global:whereis_name(list_to_atom(LPString)),
%	if
%		Pid == undefined -> erlang:error("The pid returned for the LP is undefined!\n", [LP,global:registered_names()]);
%		Pid /= undefined -> Pid
%	end.

get_first_entity_index(LpId, EntitiesNum, LpsNum) ->
       trunc((LpId - 1)*(EntitiesNum/LpsNum)+1).

get_last_entity_index(LpId, EntitiesNum, LpsNum) ->
       get_first_entity_index(LpId, EntitiesNum, LpsNum) + trunc(EntitiesNum/LpsNum) -1.

which_lp_controls(Entity, EntitiesNum, LpsNum) ->
       EntitiesEachLP = trunc(EntitiesNum / LpsNum),
       if
               (Entity rem EntitiesEachLP == 0) and (Entity /= 0) -> 
                       LPid = trunc(Entity / EntitiesEachLP);
               (Entity rem EntitiesEachLP == 0) and (Entity == 0) -> 
                       LPid = 1;
               Entity rem EntitiesEachLP /= 0 -> 
                       LPid = trunc(Entity / EntitiesEachLP) + 1
       end,
	   "lp_" ++ integer_to_list(LPid).
       %get_pid(LPid).




