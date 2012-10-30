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

-module(lp).
-behaviour(gen_fsm).

% API
-export([send_event/5, compute_local_minimum/6]).

-export([start_link/2]).

-export([init/1, terminate/3]). % handle_event/3, handle_sync_event/4, handle_info/3, code_change/4]).

-export([simulate/2, prepare_to_terminate/2]).

-include("user_include.hrl").
-include("common.hrl").
-include_lib("eunit/include/eunit.hrl").


start_link(LPName, InitModelState) ->
	gen_fsm:start_link({global, LPName}, lp, [InitModelState,LPName], []).

init([InitModelState,LPName]) ->
	Lp = #lp_status{
		lp_id = LPName,
		init_model_state = InitModelState,
		model_state=InitModelState,
		received_messages=queue:new(),
		inbox_messages=gb_trees:empty(),			
		proc_messages=queue:new(),		
		sent_messages=queue:new(), 			
		to_ack_messages=[], 			
		anti_messages=queue:new(),				
		history=queue:new(),
		current_event=nil,					
		gvt=0,
		rollbacks=0,
		timestamp=0,
		status=running,
		max_received_messages=100,
		samadi_find_mode=false,
		samadi_marked_messages_min=0,
		messageSeqNumber=0}, 
	error_logger:info_msg("~nLp ~s init successful!~n", [LPName]),
	error_logger:info_msg("~nStarting Lp ~s with pid ~p",[LPName, self()]),
	NewLp = generate_starting_events(init_state_vars(Lp)),
	% next state of the fsm 
	{ok, simulate, NewLp}.

%
% Handles all the messages sent by other LPs. 
%
simulate(Message, Lp) ->
	%io:format("Received message ~p",[Message]),
	if 
		Message#message.type == event ->
			NewLp = Lp#lp_status{received_messages=queue:in(Message, Lp#lp_status.received_messages)},
			{next_state, simulate, 
			 	process_top_message(
			   		process_received_messages(NewLp, Lp#lp_status.max_received_messages))};
		Message#message.type == prepare_to_terminate ->
			ControllerPid = Message#message.payload,
			ControllerPid ! {ack},
			{next_state, prepare_to_terminate, 
			 	process_top_message(
			   		process_received_messages(Lp, Lp#lp_status.max_received_messages))};				
		(Message#message.type /= event) and  (Message#message.type /= prepare_to_terminate) ->
			NewLp = Lp#lp_status{received_messages=queue:in(Message, Lp#lp_status.received_messages)},
			{next_state, simulate, 
			   	process_received_messages(NewLp, Lp#lp_status.max_received_messages)}
		
	end.

	
prepare_to_terminate(Message, Lp) ->
	NewLP = process_received_messages(Lp#lp_status{received_messages=queue:in(Message, Lp#lp_status.received_messages)}, Lp#lp_status.max_received_messages),
	{next_state, prepare_to_terminate, NewLP}.




terminate(Reason, _, Lp) ->
	io:format("\nLP ~s terminated for reason: ~p ", [Lp#lp_status.lp_id, Reason]), ok.

%%
%% Process the fist message in the inbox_messages priority queue,
%% it is also responsible to call the user model's function
%%
process_top_message(Lp) ->
	IsInboxEmpty = gb_trees:is_empty(Lp#lp_status.inbox_messages),
	if 
		(IsInboxEmpty == false)  -> 
			{InboxMinEvent, RestOfInbox} = tree_utils:retrieve_min(Lp#lp_status.inbox_messages),
			History = {Lp#lp_status.timestamp, Lp#lp_status.model_state, InboxMinEvent},
			CurrentEventDep = #sent_msgs{event=InboxMinEvent, msgs_list=[]},
			user:lp_function(InboxMinEvent, Lp#lp_status{timestamp=InboxMinEvent#message.timestamp, inbox_messages=RestOfInbox,
											 current_event=InboxMinEvent, proc_messages=queue:in(CurrentEventDep, Lp#lp_status.proc_messages),
				 							 history = queue:in(History, Lp#lp_status.history)});

		(IsInboxEmpty == true) -> Lp
	end.



send_ack_to_received_message(Message, Lp) ->
	SamadiFindMode = Lp#lp_status.samadi_find_mode,
	if
		SamadiFindMode == true ->
			send_marked_ack(Message, Lp);
		SamadiFindMode == false ->
			send_ack(Message, Lp)
	end.

%
% Process the messages received and put them into the received_messages queue 
% @param Lp: the Lp status record
% @return the modified Lp status record
%
process_received_messages(Lp, MaxMessageToProcess) ->
	IsQueueEmpty = queue:is_empty(Lp#lp_status.received_messages),
	if 
		IsQueueEmpty == true -> Lp;
		(IsQueueEmpty == false) and (MaxMessageToProcess == 0) -> Lp;
		(IsQueueEmpty == false) and (MaxMessageToProcess > 0)-> 
			{{value, Message}, RemainingQueue} = queue:out(Lp#lp_status.received_messages),
			
			case Message of
														
				% STANDARD EVENT
				Message when (Message#message.type == event) ->
					LpAfterAck = send_ack_to_received_message(Message, Lp),
					Annihilation = find_antimessage(LpAfterAck#lp_status.anti_messages, Message),
					if 
						(Annihilation == false) ->		
							Result = check_correct_timestamp(LpAfterAck#lp_status.timestamp, Message#message.timestamp),
							if 
								Result == true -> 
									process_received_messages(LpAfterAck#lp_status{received_messages=RemainingQueue, 
																						inbox_messages=tree_utils:safe_insert(Message,  LpAfterAck#lp_status.inbox_messages)}, MaxMessageToProcess-1);
								Result == false -> 
									LpAfterRollback = rollback(Message, LpAfterAck#lp_status{received_messages=RemainingQueue}),
									process_received_messages(LpAfterRollback#lp_status{inbox_messages=tree_utils:safe_insert(Message, LpAfterRollback#lp_status.inbox_messages)}, MaxMessageToProcess-1)
							end;
		
						(Annihilation /= false) ->
									process_received_messages(LpAfterAck#lp_status{anti_messages=Annihilation, received_messages=RemainingQueue}, MaxMessageToProcess-1)
					end;
				
				
			    % ANTIMESSAGE
				Message when Message#message.type == antimessage ->
					LpAfterSend = send_ack_to_received_message(Message, Lp),
					InboxResult = tree_utils:is_enqueued(Message#message{type=event},  LpAfterSend#lp_status.inbox_messages),
					if 
						InboxResult == false ->
							ProcResult = queue:member(Message#message{type=event}, LpAfterSend#lp_status.proc_messages),
							if 
								ProcResult == true ->
									LpAfterRollback = rollback(Message, LpAfterSend),
									process_received_messages(
									  LpAfterRollback#lp_status{inbox_messages=tree_utils:delete(Message#message{type=event}, LpAfterRollback#lp_status.inbox_messages), 
																received_messages=RemainingQueue}, MaxMessageToProcess-1);
								ProcResult == false -> 
									process_received_messages(LpAfterSend#lp_status{anti_messages=queue:in(Message, LpAfterSend#lp_status.anti_messages), 
																					received_messages=RemainingQueue}, MaxMessageToProcess-1)
							end;
						InboxResult == true -> 
							process_received_messages(LpAfterSend#lp_status{inbox_messages=tree_utils:delete(Message#message{type=event}, LpAfterSend#lp_status.inbox_messages), 
																			received_messages=RemainingQueue}, MaxMessageToProcess-1)
					end;
					
			    % MESSAGE ACK
				Message when (Message#message.type == ack) or (Message#message.type == marked_ack) ->
					AcknowledgedEvent = find_event_to_ack(Lp#lp_status.to_ack_messages, Message),
					if 
						AcknowledgedEvent == [] ->
							AcknowledgedAntiMessage = find_antimessage_to_ack(Lp#lp_status.to_ack_messages, Message),
							if
								AcknowledgedAntiMessage == [] -> 
									 NewToAckMessagesQueue = Lp#lp_status.to_ack_messages,
									 erlang:error("No message to acknowledge!", [self(), Message]);
								AcknowledgedAntiMessage /= [] -> 
									[MessageToDelete] = AcknowledgedAntiMessage,
									NewToAckMessagesQueue = [MessageNotMatch || MessageNotMatch <-Lp#lp_status.to_ack_messages, MessageNotMatch /= MessageToDelete]
							end,
							NewLp = Lp#lp_status{to_ack_messages=NewToAckMessagesQueue};
						AcknowledgedEvent /= [] -> 
							[MessageToDelete] = AcknowledgedEvent,
							NewLp = Lp#lp_status{to_ack_messages=[MessageNotMatch || MessageNotMatch <-Lp#lp_status.to_ack_messages, MessageNotMatch /= MessageToDelete]}
																										   
					end,
					if
						(Message#message.type == marked_ack) ->
							MinMarkedTimestamp = NewLp#lp_status.samadi_marked_messages_min,
							if
								((MinMarkedTimestamp /= 0) and (MinMarkedTimestamp > Message#message.timestamp))
								  or (MinMarkedTimestamp == 0) ->
									process_received_messages(NewLp#lp_status{samadi_marked_messages_min=Message#message.timestamp, received_messages=RemainingQueue}, MaxMessageToProcess-1);
								true ->	process_received_messages(NewLp#lp_status{received_messages=RemainingQueue}, MaxMessageToProcess-1)
							end;
						(Message#message.type /= marked_ack) -> 
							process_received_messages(NewLp#lp_status{received_messages=RemainingQueue}, MaxMessageToProcess-1)
					end;
				
				% COMPUTE LOCAL MINIMUM FOR GVT (SAMADI ALGORITHM)
				Message when Message#message.type == compute_local_minimum ->
					MasterPid = Message#message.payload,
					IsInboxEmpty = gb_trees:is_empty(Lp#lp_status.inbox_messages),
					if
						IsInboxEmpty == true -> InboxHeadEventTimestamp = -1;
						IsInboxEmpty == false -> 
							{_, [InboxHeadEvent|_]} = gb_trees:smallest(Lp#lp_status.inbox_messages),
							InboxHeadEventTimestamp = InboxHeadEvent#message.timestamp
					end,
					ToAckHeadEvent = list_utils:first_element(Lp#lp_status.to_ack_messages),
					if
						ToAckHeadEvent == [] -> ToAckHeadEventTimestamp = -1;
						ToAckHeadEvent /= [] -> ToAckHeadEventTimestamp = ToAckHeadEvent#message.timestamp
					end,
					MarkedMinTimestamp = Lp#lp_status.samadi_marked_messages_min,
					spawn(lp, compute_local_minimum, [InboxHeadEventTimestamp, ToAckHeadEventTimestamp, MarkedMinTimestamp, Lp#lp_status.timestamp, MasterPid, self()]),
					process_received_messages(Lp#lp_status{samadi_find_mode=true, samadi_marked_messages_min=0, received_messages=RemainingQueue}, MaxMessageToProcess-1);
				
				% RECEIVED GLOBAL VIRTUAL TIME (SAMADI ALGORITHM)
				Message when Message#message.type == gvt ->
					GlobalMinTimestamp = Message#message.payload,
					io:format("\nGVT is ~w and timestamp is ~w from lp ~s", [GlobalMinTimestamp, Lp#lp_status.timestamp, Lp#lp_status.lp_id]),
					if
						GlobalMinTimestamp < Lp#lp_status.gvt -> 
							exit("Incorrect GVT");
						GlobalMinTimestamp >= Lp#lp_status.gvt -> ok
					end,
					NewLp = Lp#lp_status{samadi_find_mode=false, samadi_marked_messages_min=0, gvt=GlobalMinTimestamp, received_messages=RemainingQueue},
					io:format("\nI am ~s to ack ~w", [Lp#lp_status.lp_id, Lp#lp_status.to_ack_messages]),
					process_received_messages(gvt_cleaning(NewLp), MaxMessageToProcess-1)

			end
	end.


generate_starting_events(Lp) ->
		user:start_function(Lp).
		
		
gvt_cleaning(Lp) ->
	GVT = Lp#lp_status.gvt,
	Lp#lp_status{proc_messages=queue:filter(fun(X) -> if X#sent_msgs.event == nil -> false;
														 X#sent_msgs.event#message.timestamp >= GVT -> true; 
														 X#sent_msgs.event#message.timestamp < GVT -> false 
													  end end, Lp#lp_status.proc_messages),
				 history=queue:filter(fun(X) -> {Timestamp,_,_} = X, if Timestamp >= GVT -> true; Timestamp < GVT -> false end end, Lp#lp_status.history)}.

%%
%% Computes the local minimum and sends the result to the GVT controller process
%%
compute_local_minimum(InboxHeadEventTimestamp, ToAckHeadEventTimestamp, MarkedMinTimestamp, LpTimestamp, GVTControllerPid, LpPid) ->
	ComputedLocalMin = lists:foldl(fun(X,Acc) ->
						if
							(X > 0) and (Acc > 0) and (X < Acc) -> X;
							(X > 0) and (Acc > 0) and (X >= Acc) -> Acc;
							(X =< 0) and (Acc > 0) -> Acc;
							(X =< 0) and (Acc =< 0) -> Acc;
							(X > 0) and (Acc =< 0) -> X
						end end,
						-1, [InboxHeadEventTimestamp, ToAckHeadEventTimestamp, MarkedMinTimestamp]),
	if 
		ComputedLocalMin =< 0 ->  LocalMin = LpTimestamp;
		ComputedLocalMin > 0 ->   LocalMin = ComputedLocalMin
	end,
	io:format("\n~w Local min is ~w", [self(), LocalMin]),
	GVTControllerPid ! {my_local_min, LpPid, LocalMin}.


%%
%% Re-enqueues the events to reprocess and send their related antimessages 
%%
handle_processed_events([], Lp) -> Lp;
handle_processed_events([Head|Tail], Lp) ->
	#sent_msgs{event=Event, msgs_list=EventDependencies} = Head,
	NewInbox = tree_utils:safe_insert(Event, Lp#lp_status.inbox_messages),
	NewLp = send_antimessages(EventDependencies, Lp#lp_status{inbox_messages=NewInbox}),
	handle_processed_events(Tail, NewLp).

%%
%% Performs the rollback in case of a straggler message arrives 
%%
rollback(StragglerMessage, Lp) ->
	RollBacks = Lp#lp_status.rollbacks + 1,
	%io:format("\n~w rollbacks to ~w because ~w, now it's ~w", [self(), StragglerMessage#message.timestamp, StragglerMessage, Lp#lp_status.timestamp]),
	% bring the processed events back in the inbox queue
	{NewProcQueue, ToReProcessMsgs} = queue_utils:dequeue_until(StragglerMessage, Lp#lp_status.proc_messages),
	%io:format("\nRE-Processing ~w", [ToReProcessMsgs]),
	NewLp = handle_processed_events(ToReProcessMsgs, Lp#lp_status{proc_messages=NewProcQueue, rollbacks=RollBacks}),
	IsNewProcQueueEmpty = queue:is_empty(NewProcQueue),
	if 
		IsNewProcQueueEmpty == true -> 
			error_logger:info_msg("~n~p Processed Event queue empty! Straggler message ~p Lp timestamp ~p", [self(), StragglerMessage, NewLp#lp_status.timestamp]),
			(init_state_vars(NewLp));
		IsNewProcQueueEmpty == false ->
			if 
				ToReProcessMsgs /= [] ->
					[Head|_] = ToReProcessMsgs,
					restore_history(Head#sent_msgs.event, NewLp);
				ToReProcessMsgs == [] ->
					error_logger:error_msg("\nNO MESSAGE TO REPROCESS DURING ROLLBACK! ~p Straggler event ~p processed events \n~p", [self(),StragglerMessage, Lp#lp_status.proc_messages])
			end
	end.


find_msg(MsgQueue, Message) ->
	[MessageFound || MessageFound <- MsgQueue, Message == MessageFound].


%%
%% It searches into the queue in input the correspondent message to the ack 
%%
find_message_to_ack(MessageQueue, Ack, Type) ->
	#message{type=_, seqNumber=AckSeq, lpSender=LpSender, lpReceiver=LpReceiver, 
			 payload=AckPayload, timestamp=AckTimestamp} = Ack,
	Message = #message{type=Type, seqNumber=AckSeq, lpSender=LpSender, lpReceiver=LpReceiver, 
					   payload=AckPayload, timestamp=AckTimestamp},
	IsQueue = queue:is_queue(MessageQueue),
	if
		IsQueue == true ->
			queue_utils:delete_element(MessageQueue, Message);
		IsQueue == false ->
			find_msg(MessageQueue, Message)
	end.


%%
%% Finds the correspondent antimessage to the event in input
%%
find_antimessage(AntiMessageQueue, Event) ->
	#message{type=event, seqNumber=EventSeq, lpSender=LpSender, lpReceiver=LpReceiver, 
			 payload=EventPayload, timestamp=EventTimestamp} = Event,
	Antimessage = #message{type=antimessage, seqNumber=EventSeq, lpSender=LpSender, lpReceiver=LpReceiver, 
						   payload=EventPayload, timestamp=EventTimestamp},
	queue_utils:delete_element(AntiMessageQueue, Antimessage).
	

%%
%% Finds the correspondent event to the ack in input. 
%%
find_event_to_ack(MessageQueue, Ack) ->
	find_message_to_ack(MessageQueue, Ack, event).

%%
%% Finds the correspondent antimessage to the ack in input. 
%%
find_antimessage_to_ack(MessageQueue, Ack) ->
	find_message_to_ack(MessageQueue, Ack, antimessage).

%%
%% Checks if the current entity's timestamp is greater or lower
%% than the one in input.
%%
check_correct_timestamp(LP_Timestamp, New_Timestamp) ->
	if 
		LP_Timestamp > New_Timestamp -> false;
		LP_Timestamp =< New_Timestamp -> true
	end. 


send_ack(Message, Lp) ->
	Ack = Message#message{type=ack},
	send_message(Ack, Lp).

send_marked_ack(Message, Lp) ->
	Ack = Message#message{type=marked_ack},
	send_message(Ack, Lp).

send_antimessage(Event, Lp) ->
	Antimessage = Event#message{type=antimessage},
	send_message(Antimessage, Lp).

%% 
%% Sends a list of antimessages
%%
send_antimessages([], Lp) -> Lp;
send_antimessages([HeadEvent | Tail], Lp) -> 
	NewLp = send_antimessage(HeadEvent, Lp),
	send_antimessages(Tail, NewLp).

%% 
%% Sends a message to an entity
%%
send_message(Message, LPStatus) ->
	%io:format("\nSending ~w from Lp ~s", [Message, LPStatus#lp_status.lp_id]),
	if 
		(Message#message.type == ack) or (Message#message.type == marked_ack) ->
			LPDest = Message#message.lpSender;
		(Message#message.type == antimessage) or (Message#message.type == event) ->
			LPDest = Message#message.lpReceiver
	end,
	gen_fsm:send_event({global, LPDest}, Message),
	if 
		(Message#message.type == event) -> 
			LPUpdatedDept = insert_dependency(Message, LPStatus),
			LPUpdatedDept#lp_status{to_ack_messages=list_utils:insert_ordered(LPStatus#lp_status.to_ack_messages, Message)};
		(Message#message.type == antimessage) -> 
			LPStatus#lp_status{to_ack_messages=list_utils:insert_ordered(LPStatus#lp_status.to_ack_messages, Message)};
		(Message#message.type == ack) or (Message#message.type == marked_ack) ->
			LPStatus
	end.


insert_dependency(Message, Lp) ->
	EmptyQ = queue:is_empty(Lp#lp_status.proc_messages),
	if
		EmptyQ == true -> Lp;
		EmptyQ == false ->
				{{value, EventDependencies}, NewProcQueue} = queue:out_r(Lp#lp_status.proc_messages),
				NewDependencyList = [Message | EventDependencies#sent_msgs.msgs_list],
				Lp#lp_status{proc_messages=queue:in(EventDependencies#sent_msgs{msgs_list=NewDependencyList}, NewProcQueue)}
	end.

%% 
%% User function: send an event to another entity
%%
send_event(LPSender, LPReceiver, Payload, Timestamp, Lp) ->
	SeqNumber = Lp#lp_status.messageSeqNumber + 1,
	Message = #message{type=event, lpSender=LPSender, lpReceiver=LPReceiver, payload=Payload, timestamp=Timestamp, seqNumber=SeqNumber},
	send_message(Message, Lp#lp_status{messageSeqNumber=SeqNumber}).


%%
%% Restores the last known entity's state
%% related to a particular timestamp.
%%
restore_history(Event, Lp) ->
	{ElementToRestore, NewHistory} = queue_utils:dequeue_history_until(Lp#lp_status.history, Event),
	restore_state_vars(ElementToRestore, Lp#lp_status{history=NewHistory}).		
	
%%
%% Takes a past entity's state in input and
%% updates according to it the acutal state.
%%
restore_state_vars(ToRestore, Lp) ->
	{Timestamp, ModelState, _} = ToRestore,
	Lp#lp_status{timestamp=Timestamp, model_state=ModelState}.

%%
%% Takes the starting entity's state and
%% updates according to it the acutal state.
%%
init_state_vars(Lp) ->
	Lp#lp_status{timestamp=0, model_state=Lp#lp_status.init_model_state}.


print_lp_info(Lp) ->
	error_logger:info_msg("~n LP ~p rollbacks ~p timestamp ~p", [self(), Lp#lp_status.rollbacks, Lp#lp_status.timestamp]).
	
