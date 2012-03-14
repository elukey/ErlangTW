-module(user).
-export([entity_function/2, start_function/1, newton_radix/2, get_pid/1]).

-include("user_include.hrl").
-include("common.hrl").

start_function(Lp) ->
	StartModel = Lp#lp_status.init_model_state,
	StartingEntitiesNumber = round(get_total_entities(Lp) * StartModel#state.density),
	io:format("\n~w created ~w init events..", [self(), StartingEntitiesNumber]),
	generate_events(StartingEntitiesNumber, Lp).

generate_events(Number, Lp) when Number == 0 -> Lp;
generate_events(Number, Lp) ->
	generate_events(Number-1, generate_event(0, Lp)).
	
generate_event(BaseTimestamp, Lp) ->
	ModelState = get_modelstate(Lp),
	{RandomEntitySender, NewSeedAfterSender} = lcg:get_random(ModelState#state.seed, 1, get_total_entities(Lp)),
	{RandomEntityReceiver, NewSeedAfterReceiver} = lcg:get_random(NewSeedAfterSender, 1, get_total_entities(Lp)),
	{ExpRand, NewSeedRand}  = lcg:get_exponential_random(NewSeedAfterReceiver),
	NewTimestamp = BaseTimestamp + ExpRand,
	NewLp = set_modelstate(Lp, ModelState#state{seed=NewSeedRand}),
	LpEntityReceiver = which_lp_controls(RandomEntityReceiver, Lp),
	LpEntitySender = which_lp_controls(RandomEntitySender, Lp),
	Payload = #payload{entitySender=RandomEntitySender, entityReceiver=RandomEntityReceiver},
	EventGenerated = #message{type=event, lpSender=LpEntitySender, lpReceiver=LpEntityReceiver, timestamp=NewTimestamp, seqNumber=0, payload=Payload},
	if
		LpEntityReceiver == self() ->
				NewLp#lp_status{inbox_messages=tree_utils:safe_insert(EventGenerated, NewLp#lp_status.inbox_messages)};
		LpEntityReceiver /= self() ->
				NewLp
	end.

entity_function(Event, Lp) ->
	newton_radix(2, 10000),
	ModelState = get_modelstate(Lp),
	{RandomEntity, NewSeed} = lcg:get_random(ModelState#state.seed, 1, get_total_entities(Lp)),
	{ExpRand, NewSeedRand}  = lcg:get_exponential_random(NewSeed),
	NewTimestamp = Event#message.timestamp + ExpRand,
	NewLp = set_modelstate(Lp, ModelState#state{seed=NewSeedRand}),
	LpEntityReceiver = which_lp_controls(RandomEntity, Lp),
	EntitySender = (Event#message.payload)#payload.entityReceiver,
	Payload = #payload{entitySender=EntitySender, entityReceiver=RandomEntity},
	lp:send_event(self(), LpEntityReceiver, Payload, NewTimestamp, NewLp).


newton_radix(Number, FPOp) ->
	newton_radix_aux(Number, trunc(FPOp/5), 1, 0.5).

newton_radix_aux(_, TotalIteration, CurrentIterationNum, Acc) when CurrentIterationNum == TotalIteration -> 1/Acc;
newton_radix_aux(Number, TotalIteration, CurrentIterationNum, Acc) ->
	NewAcc = 0.5 * Acc * (3 - (Number * Acc * Acc)),
	newton_radix_aux(Number, TotalIteration, CurrentIterationNum + 1, NewAcc).

get_modelstate(Lp) ->
	Lp#lp_status.model_state.

get_total_entities(Lp) ->
	InitModelState = Lp#lp_status.init_model_state,
	InitModelState#state.entities.

get_lps_number(Lp) ->
	InitModelState = Lp#lp_status.init_model_state,
	InitModelState#state.lps.

set_modelstate(Lp, ModelState) ->
	Lp#lp_status{model_state=ModelState}.

get_first_entity_index(Lp) ->
	trunc((Lp#lp_status.my_id - 1)*((get_total_entities(Lp)/get_lps_number(Lp)))+1).

get_last_entity_index(Lp) ->
	get_first_entity_index(Lp) + trunc(get_total_entities(Lp)/get_lps_number(Lp)) -1.

which_lp_controls(Entity, Lp) ->
	EntitiesEachLP = trunc(get_total_entities(Lp) / get_lps_number(Lp)),
	if
		(Entity rem EntitiesEachLP == 0) and (Entity /= 0) -> 
			LPid = trunc(Entity / EntitiesEachLP);
		(Entity rem EntitiesEachLP == 0) and (Entity == 0) -> 
			LPid = 1;
		Entity rem EntitiesEachLP /= 0 -> 
			LPid = trunc(Entity / EntitiesEachLP) + 1
	end,
	get_pid(LPid).


get_pid(LP) ->
	Pid = global:whereis_name(list_to_existing_atom(string:concat("lp_",integer_to_list(LP)))),
	if
		Pid == undefined -> erlang:error("The pid returned for the LP is undefined!\n", [LP,global:registered_names()]);
		Pid /= undefined -> Pid
	end.
