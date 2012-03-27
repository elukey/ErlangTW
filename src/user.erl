-module(user).
-export([lp_function/2, start_function/1, newton_radix/2, get_pid/1]).

-include("user_include.hrl").
-include("common.hrl").

start_function(Lp) ->
	StartModel = Lp#lp_status.init_model_state,
	generate_events(StartModel#state.starting_events, Lp).

generate_events(Number, Lp) when Number == 0 -> Lp;
generate_events(Number, Lp) ->
	generate_events(Number-1, generate_starting_event(Lp)).
	
generate_starting_event(Lp) ->
	ModelState = get_modelstate(Lp),
	LpsNumber = ModelState#state.lps,
	LpReceiverPid = self(),
	{LpSenderId, NewSeed} = lcg:get_random(ModelState#state.seed, 1, LpsNumber),
	LpSenderPid = get_pid(LpSenderId),
	Payload = #payload{value=0},
	{Timestamp, NewSeed2} = lcg:get_exponential_random(NewSeed),
	Event = #message{lpSender=LpSenderPid, lpReceiver=LpReceiverPid, payload=Payload, type=event, seqNumber=0, timestamp=Timestamp},
	%io:format("\n~wEvent Generated: ~w", [self(), Event]),
	Lp#lp_status{inbox_messages=tree_utils:safe_insert(Event, Lp#lp_status.inbox_messages), model_state=ModelState#state{seed=NewSeed2}}.
		

lp_function(Event, Lp) ->
	Payload=newton_radix(2, 10000),
	ModelState = get_modelstate(Lp),
	LpsNumber = ModelState#state.lps,
	{LpReceiver, NewSeed} = lcg:get_random(ModelState#state.seed, 1, LpsNumber),
	LpSender = self(),
	{ExpDeltaTime, NewSeed2} =  lcg:get_exponential_random(NewSeed),
	NewTimestamp = Event#message.timestamp + ExpDeltaTime,
	NewLp = set_modelstate(Lp, ModelState#state{seed=NewSeed2}),
	lp:send_event(LpSender, get_pid(LpReceiver), Payload, NewTimestamp, NewLp).


newton_radix(Number, FPOp) ->
	newton_radix_aux(Number, trunc(FPOp/5), 1, 0.5).

newton_radix_aux(_, TotalIteration, CurrentIterationNum, Acc) when CurrentIterationNum == TotalIteration -> 1/Acc;
newton_radix_aux(Number, TotalIteration, CurrentIterationNum, Acc) ->
	NewAcc = 0.5 * Acc * (3 - (Number * Acc * Acc)),
	newton_radix_aux(Number, TotalIteration, CurrentIterationNum + 1, NewAcc).

get_modelstate(Lp) ->
	Lp#lp_status.model_state.

set_modelstate(Lp, ModelState) ->
	Lp#lp_status{model_state=ModelState}.


get_pid(LP) ->
	Pid = global:whereis_name(list_to_existing_atom(string:concat("lp_",integer_to_list(LP)))),
	if
		Pid == undefined -> erlang:error("The pid returned for the LP is undefined!\n", [LP,global:registered_names()]);
		Pid /= undefined -> Pid
	end.
