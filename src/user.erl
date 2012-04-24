-module(user).
-export([lp_function/2, start_function/1, newton_radix/2, get_pid/1, terminate_model/1, newton_radix_foldl/2]).

-include("user_include.hrl").
-include("common.hrl").

start_function(Lp) ->
	StartModel = get_modelstate(Lp),
	LpsNum = StartModel#state.lps,
	EntitiesNum = StartModel#state.entities,
	LpId = Lp#lp_status.my_id,
	FirstEntity = get_first_entity_index(LpId, EntitiesNum, LpsNum),
	LastEntity = get_last_entity_index(LpId, EntitiesNum, LpsNum), 
	io:format("\nI am ~w and my first entity is ~w and last is ~w", [self(), FirstEntity, LastEntity]),
	ModelWithEntitiesStates = StartModel#state{entities_state=generate_init_entities_states(FirstEntity, LastEntity)},
	NewLp = generate_events(StartModel#state.starting_events, 
							Lp#lp_status{model_state=ModelWithEntitiesStates}, FirstEntity, LastEntity),
	NewLp#lp_status{init_model_state=ModelWithEntitiesStates}.

generate_init_entities_states(FirstEntity, LastEntity) ->
	InitEntitiesStates = [{Entity, #entity_state{seed=Entity, timestamp=0}} || Entity <- lists:seq(FirstEntity, LastEntity)],
	dict:from_list(InitEntitiesStates).

generate_events(_, Lp, FirstEntity, LastEntity) when FirstEntity -1 == LastEntity -> Lp;
generate_events(Number, Lp, FirstEntity, LastEntity) ->
	generate_events(Number, generate_starting_events(Lp, LastEntity, Number), FirstEntity, LastEntity-1).
	
generate_starting_events(Lp, _, Number) when Number == 0 -> Lp;
generate_starting_events(Lp, Entity, Number) ->
	ModelState = get_modelstate(Lp),
	{Event, NewModelState} = generate_event_from_sender(Entity, 0, 0, ModelState),
	%io:format("\nEvent generated for entity ~w is ~w", [Entity, Event]),
	NewLp = lp:send_event(Event#message.lpSender, Event#message.lpReceiver, Event#message.payload, Event#message.timestamp, Lp),
	generate_starting_events(NewLp#lp_status{model_state=NewModelState}, Entity, Number-1).

lp_function(Event, Lp) ->
	newton_radix(2, 10000),
	#payload{entityReceiver=EntityReceiver} = Event#message.payload,
	ModelState = get_modelstate(Lp),
	MaxTimestap = ModelState#state.max_timestamp,
	EntityState = get_entity_state(EntityReceiver, ModelState),
	% coherence check, testing code
	if
		EntityReceiver == 5 ->
			{ok, WriteDescr} = file:open("/home/luke/Desktop/trace5.txt", [append]), 
			io:format(WriteDescr,"\nEntity ~w with timestamp ~w received payload ~w", [EntityReceiver, EntityState#entity_state.timestamp, Event#message.payload]), 
			file:close(WriteDescr);
		EntityReceiver /= 5 ->
			ok
	end,
	if
		Event#message.timestamp < EntityState#entity_state.timestamp ->
			io:format("\n\n~w Entity timestamp ~w message timestamp ~w LP timestamp ~w\n", [self(), EntityState#entity_state.timestamp, Event#message.timestamp, Lp#lp_status.timestamp]),
			erlang:error("Timestamp less than expected!");
		Event#message.timestamp >= EntityState#entity_state.timestamp -> 
			if
				EntityState#entity_state.timestamp >= MaxTimestap -> Lp;
				EntityState#entity_state.timestamp < MaxTimestap ->
					NewEntityState = EntityState#entity_state{timestamp=Event#message.timestamp},
					NewModelState = ModelState#state{entities_state=set_entity_state(EntityReceiver, NewEntityState, ModelState)},
					{NewEvent, NewModelState2} = generate_event_from_sender(EntityReceiver, Event#message.timestamp, 1, NewModelState),
					#message{lpSender=LPSender, lpReceiver=LPReceiver, payload=Payload, timestamp=Timestamp} = NewEvent, 
					lp:send_event(LPSender, LPReceiver, Payload, Timestamp, Lp#lp_status{model_state=NewModelState2})
			end
	end.

terminate_model(Lp) ->
	ModelState = get_modelstate(Lp),
	pretty_print_model_entities(ModelState).

pretty_print_model_entities(ModelState) ->
	lists:foreach(fun(X) -> {Entity, EntityState} = X, io:format("\nEntity ~w with timestamp ~w\n", [Entity, EntityState#entity_state.timestamp]) end, dict:to_list(ModelState#state.entities_state)).


get_entity_state(Entity, ModelState) ->
	dict:fetch(Entity, ModelState#state.entities_state).

set_entity_state(Entity,State,ModelState) ->
	dict:store(Entity, State, ModelState#state.entities_state).

generate_event_from_sender(EntitySender, Timestamp, PayloadValue, ModelState) ->
	EntityState = get_entity_state(EntitySender, ModelState),
	{ExpDeltaTime, NewSeed} =  lcg:get_exponential_random(EntityState#entity_state.seed),
	NewTimestamp = Timestamp + ExpDeltaTime,
	{EntityReceiver, NewSeed2} = lcg:get_random(NewSeed, 1, ModelState#state.entities),
	LpReceiver = which_lp_controls(EntityReceiver, ModelState#state.entities, ModelState#state.lps),
	Payload = #payload{entitySender=EntitySender, entityReceiver=EntityReceiver, value=PayloadValue},
	Event = #message{type=event, lpSender=self(), lpReceiver=LpReceiver, payload=Payload, seqNumber=0, timestamp=NewTimestamp},
	NewEntityState = EntityState#entity_state{seed=NewSeed2},
	NewModelState = ModelState#state{entities_state=set_entity_state(EntitySender, NewEntityState, ModelState)},
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


get_pid(LP) ->
	LPString = "lp_" ++ integer_to_list(LP),
	Pid = global:whereis_name(list_to_existing_atom(LPString)),
	if
		Pid == undefined -> erlang:error("The pid returned for the LP is undefined!\n", [LP,global:registered_names()]);
		Pid /= undefined -> Pid
	end.

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
       get_pid(LPid).




