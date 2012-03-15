-module(lp).
-export([start/2, send_event/5]).

-include("user_include.hrl").
-include("common.hrl").
-include_lib("eunit/include/eunit.hrl").


start(MyLPNumber, InitModelState) ->
	Lp = #lp_status{
		my_id=MyLPNumber,
		init_model_state = InitModelState,
		model_state=InitModelState,
		received_messages=queue:new(),
		inbox_messages=gb_trees:empty(),			
		proc_messages=queue:new(),		
		sent_messages=queue:new(), 			
		to_ack_messages=[], 			
		anti_messages=queue:new(),				
		history=queue:new(),					
		gvt=0,
		rollbacks=0,
		timestamp=0,
		status=running,
		max_received_messages=100,
		samadi_find_mode=false,
		samadi_marked_messages_min=0,
		messageSeqNumber=0}, 
	io:format("\nI am LP ~w ~w", [Lp#lp_status.my_id, self()]),
	main_loop(init_state_vars(Lp)).


main_loop(Lp) ->
	if 
		Lp#lp_status.status == running ->
			receive
				Message ->
					NewLp = Lp#lp_status{received_messages=queue:in(Message, Lp#lp_status.received_messages)},
					main_loop(NewLp)
		
			after 0 -> 
				main_loop(process_top_message(process_received_messages(Lp, Lp#lp_status.max_received_messages)))
			end;

		Lp#lp_status.status == prepare_to_terminate -> 
			receive 
				{terminate, _} -> ok
			end
	end.
	


%
% Process the fist message in the inbox_messages priority queue
% It is responsible to call the user function
% @param Lp: the Lp status record
% @return the modified Lp status record
%
process_top_message(Lp) ->
	IsInboxEmpty = gb_trees:is_empty(Lp#lp_status.inbox_messages),
	if 
		(IsInboxEmpty == false) and (Lp#lp_status.status == running) -> 
			{InboxMinEvent, RestOfInbox} = tree_utils:retrieve_min(Lp#lp_status.inbox_messages),
			History = {Lp#lp_status.timestamp, Lp#lp_status.model_state, InboxMinEvent},
			file:write_file("/home/luke/Desktop/erllog", io_lib:fwrite("\n~w Processing event ~w", [self(), InboxMinEvent]), [append]),
			NewLp = user:entity_function(InboxMinEvent, Lp),
			NewLp#lp_status{inbox_messages=RestOfInbox, proc_messages=queue:in(InboxMinEvent, NewLp#lp_status.proc_messages),
							   history = queue:in(History, NewLp#lp_status.history), timestamp=InboxMinEvent#message.timestamp};
		
		(IsInboxEmpty == false) and (Lp#lp_status.status == prepare_to_terminate) -> Lp;
		
		(IsInboxEmpty == true) -> Lp
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
			%io:format("\n~w is processing the message ~w\nStatus: ~w", [self(), Message, Lp#lp_status.to_ack_messages]),
			case Message of
				
			    % ANTIMESSAGE
				Message when Message#message.type == antimessage ->
					SamadiFindMode = Lp#lp_status.samadi_find_mode,
					TestLocalEvent = (self() == Message#message.lpSender),
					if
						TestLocalEvent == false ->
							if
								SamadiFindMode == true ->
									LpAfterSend = send_marked_ack(Message, Lp#lp_status{received_messages=RemainingQueue}),
									io:format("\nSent marked ack for ~w", [Message]);
								SamadiFindMode == false ->
									LpAfterSend = send_ack(Message, Lp#lp_status{received_messages=RemainingQueue})
							end;
						TestLocalEvent == true -> LpAfterSend =  Lp#lp_status{received_messages=RemainingQueue}
					end,
					InboxResult = tree_utils:is_enqueued(Message#message{type=event},  LpAfterSend#lp_status.inbox_messages),
					if 
						InboxResult == false ->
							ProcResult = annihilate_antimsg(LpAfterSend#lp_status.proc_messages, Message),
							if 
								ProcResult /= false ->
									process_received_messages(rollback(Message#message.timestamp, 
																	   LpAfterSend#lp_status{proc_messages=ProcResult}), MaxMessageToProcess-1);
								ProcResult == false -> 
									process_received_messages(LpAfterSend#lp_status{anti_messages=queue:in(Message, LpAfterSend#lp_status.anti_messages)}, MaxMessageToProcess-1)
							end;
						InboxResult == true -> 
							process_received_messages(LpAfterSend#lp_status{inbox_messages=tree_utils:delete(Message#message{type=event}, LpAfterSend#lp_status.inbox_messages)}, MaxMessageToProcess-1)
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
				
		
				% STANDARD EVENT
				Message when (Message#message.type == event) ->
					Annihilation = find_antimessage(Lp#lp_status.anti_messages, Message),
					TestLocalEvent = (self() == Message#message.lpSender),
					if 
						(Annihilation == false) ->		
							Result = check_correct_timestamp(Lp#lp_status.timestamp, Message#message.timestamp),
							if 
								Result == true -> 
									InboxMessages = Lp#lp_status.inbox_messages,
									NewLp = Lp#lp_status{received_messages=RemainingQueue, inbox_messages=tree_utils:safe_insert(Message, InboxMessages)};
								Result == false -> 
									LpAfterRollback = rollback(Message#message.timestamp, Lp#lp_status{received_messages=RemainingQueue}),
									NewLp = LpAfterRollback#lp_status{inbox_messages=tree_utils:safe_insert(Message, Lp#lp_status.inbox_messages)}
							end,
							SamadiFindMode = NewLp#lp_status.samadi_find_mode,
							if
								TestLocalEvent == false ->
									if 
										SamadiFindMode == true ->
											process_received_messages(send_marked_ack(Message, NewLp), MaxMessageToProcess-1);
										SamadiFindMode == false ->
											process_received_messages(send_ack(Message,  NewLp), MaxMessageToProcess-1)
									end;
								TestLocalEvent == true -> process_received_messages(NewLp, MaxMessageToProcess-1)
							end;
		
						(Annihilation /= false) ->
							if
								TestLocalEvent == false ->
									process_received_messages(send_ack(Message, Lp#lp_status{anti_messages=Annihilation, received_messages=RemainingQueue}), MaxMessageToProcess-1);
								TestLocalEvent == true ->
									process_received_messages(Lp#lp_status{anti_messages=Annihilation, received_messages=RemainingQueue}, MaxMessageToProcess-1)
							end
					end;
		
				% COMPUTE LOCAL MINIMUM FOR GVT (SAMADI ALGORITHM)
				{compute_local_minimum, MasterPid} ->
					IsInboxEmpty = gb_trees:is_empty(Lp#lp_status.inbox_messages),
					if
						IsInboxEmpty == true -> InboxHeadEvent = [];
						IsInboxEmpty == false -> {_, [InboxHeadEvent|_]} = gb_trees:smallest(Lp#lp_status.inbox_messages)
					end,
					ToAckHeadEvent = list_utils:first_element(Lp#lp_status.to_ack_messages),
					MarkedMinTimestamp = Lp#lp_status.samadi_marked_messages_min,
					LocalMin = compute_local_minimum(InboxHeadEvent, ToAckHeadEvent, MarkedMinTimestamp, Lp),
					MasterPid ! {my_local_min, self(), LocalMin},
					io:format("\n~w with timestamp ~w LOCALMIN ~w local min values: ~w ~w ~w, total rollbacks ~w to_ack ~w inbox leng ~w to_ack leng ~w seqNumber ~w", 
							  [self(), Lp#lp_status.timestamp, LocalMin, InboxHeadEvent, ToAckHeadEvent, MarkedMinTimestamp, Lp#lp_status.rollbacks,Lp#lp_status.to_ack_messages, 
								length(gb_trees:keys(Lp#lp_status.inbox_messages)), length(Lp#lp_status.to_ack_messages),
								Lp#lp_status.messageSeqNumber]),
					process_received_messages(Lp#lp_status{samadi_find_mode=true, samadi_marked_messages_min=0, received_messages=RemainingQueue}, MaxMessageToProcess-1);
				
				% RECEIVED GLOBAL VIRTUAL TIME (SAMADI ALGORITHM)
				{gvt, GlobalMinTimestamp} ->
					if
						GlobalMinTimestamp < Lp#lp_status.gvt -> 
							exit("Incorrect GVT");
						GlobalMinTimestamp >= Lp#lp_status.gvt -> ok
					end,
					process_received_messages(Lp#lp_status{samadi_find_mode=false, samadi_marked_messages_min=0, gvt=GlobalMinTimestamp, received_messages=RemainingQueue}, MaxMessageToProcess-1);
			
				% SPECIAL MESSAGE: Start the simulation
				{start} ->
					io:format("\nStarting LP ~w with pid ~w",[Lp#lp_status.my_id, self()]),
					NewLp = user:start_function(Lp#lp_status{received_messages=RemainingQueue}),
					process_received_messages(NewLp, MaxMessageToProcess-1);
				
				{prepare_to_terminate, ControllerPid} ->
					io:format("\n~w has finished, timestamp ~w\n", [self(), Lp#lp_status.timestamp]),
					ControllerPid ! {ack},
					process_received_messages(Lp#lp_status{status=prepare_to_terminate, received_messages=queue:new()}, MaxMessageToProcess-1)

			end
	end.


compute_local_minimum([], [], 0, Lp) -> Lp#lp_status.timestamp;
compute_local_minimum([], [], MinMarkedTimestamp, _) when MinMarkedTimestamp > 0 -> MinMarkedTimestamp;
compute_local_minimum([], ToAckEvent, 0, _) when ToAckEvent /= []-> ToAckEvent#message.timestamp;
compute_local_minimum(InboxEvent, [], 0, _) when InboxEvent /= [] -> InboxEvent#message.timestamp;
compute_local_minimum(InboxEvent, ToAckEvent, 0, _) when (ToAckEvent /= []) and (InboxEvent /= []) -> 
	if
		InboxEvent#message.timestamp =< ToAckEvent#message.timestamp -> InboxEvent#message.timestamp;
		InboxEvent#message.timestamp > ToAckEvent#message.timestamp ->  ToAckEvent#message.timestamp
	end;
compute_local_minimum([], ToAckEvent, MinMarkedTimestamp, _) when (ToAckEvent /= []) and (MinMarkedTimestamp > 0) -> 
	if
		MinMarkedTimestamp =< ToAckEvent#message.timestamp -> MinMarkedTimestamp;
		MinMarkedTimestamp > ToAckEvent#message.timestamp ->  ToAckEvent#message.timestamp
	end;
compute_local_minimum(InboxEvent, [], MinMarkedTimestamp, _) when (InboxEvent /= []) and (MinMarkedTimestamp > 0) -> 
	if
		MinMarkedTimestamp =< InboxEvent#message.timestamp -> MinMarkedTimestamp;
		MinMarkedTimestamp > InboxEvent#message.timestamp ->  InboxEvent#message.timestamp
	end;
compute_local_minimum(InboxEvent, ToAckEvent, MinMarkedTimestamp, _) when (ToAckEvent /= []) and (InboxEvent /= []) and (MinMarkedTimestamp > 0) ->
	lists:min([ToAckEvent#message.timestamp, InboxEvent#message.timestamp, MinMarkedTimestamp]).


%
% Performs the rollback in case of a straggler message arrives 
% @param Lp: the Lp status record
% @param StragglerTimestamp: the timestamp to rollback to
% @return the modified Lp status record
%
rollback(StragglerTimestamp, Lp) ->
	%io:format("\n~w rollbacks to ~w, now it's ~w", [self(), StragglerTimestamp, Lp#lp_status.timestamp]),
	RollBacks = Lp#lp_status.rollbacks + 1,
	% bring the processed events back in the inbox queue
	{NewProcQueue, ToReProcessMsgs} = queue_utils:dequeue_until(Lp#lp_status.proc_messages, StragglerTimestamp),
	NewInboxQueue = tree_utils:multi_safe_insert(ToReProcessMsgs, Lp#lp_status.inbox_messages),
	% prepare the set of antimessages to send looking into the sent queue
	{NewQueueSentMessages, AntimessagesToSend} = queue_utils:dequeue_until(Lp#lp_status.sent_messages, StragglerTimestamp),


	if 
		ToReProcessMsgs == [] -> 
			NewLp = (init_state_vars(Lp))#lp_status{inbox_messages=NewInboxQueue, rollbacks=RollBacks, proc_messages=NewProcQueue, 
												  sent_messages=NewQueueSentMessages};
		ToReProcessMsgs /= [] -> 
			[Head|_] = ToReProcessMsgs, 
			NewLp = restore_history(Head, Lp#lp_status{inbox_messages=NewInboxQueue, rollbacks=RollBacks, proc_messages=NewProcQueue, 
											sent_messages=NewQueueSentMessages})
	end,
	
	% send the antimessages and restore the past state
	send_antimessages(AntimessagesToSend, NewLp).



%
% It searches into the queue in input the correspondent message to the antimessage 
% @param Queue: it could be a list or a queue
% @param Antimessage: a #message record 
% @returns in case Queue is a list, [] if it does not find the message, the list without that message otherwise;
%		   in case Queue is a queue, the output of the delete_element method
%
annihilate_antimsg(Queue, AntiMessage) ->
	MessageToFind = #message{type=event, seqNumber=AntiMessage#message.seqNumber,
					 lpSender=AntiMessage#message.lpSender, lpReceiver=AntiMessage#message.lpReceiver, payload=AntiMessage#message.payload, timestamp=AntiMessage#message.timestamp},
	IsQueue = queue:is_queue(Queue),
	if
		IsQueue == true ->
			queue_utils:delete_element(Queue, MessageToFind);
		IsQueue == false ->
			CheckInboxMessages = find_msg(Queue, MessageToFind),
			if
				CheckInboxMessages == [] -> [];
				CheckInboxMessages /= [] -> [Message || Message <- Queue, Message /= MessageToFind]
			end
	end.


%% unit testing
annihilate_antimsg_1_test() ->
	[] = annihilate_antimsg([], #message{type=antimessage, seqNumber=1,
		lpSender=1, lpReceiver=10, payload=1, timestamp=1}).
annihilate_antimsg_2_test() ->
		[#message{type=event, seqNumber=2, lpSender=1, lpReceiver=10, payload=10, timestamp=11}] = 
		annihilate_antimsg([#message{type=event, seqNumber=1, lpSender=1, lpReceiver=10, payload=1, timestamp=1},
	 						#message{type=event, seqNumber=2, lpSender=1, lpReceiver=10, payload=10, timestamp=11}], 
						    #message{type=antimessage, seqNumber=1, lpSender=1, lpReceiver=10, payload=1, timestamp=1}).


find_msg(MsgQueue, Message) ->
	[MessageFound || MessageFound <- MsgQueue, Message == MessageFound].

%% unit testing
find_msg_1_test() ->
		[] = find_msg([], #message{type=ack, seqNumber=1, lpSender=1, lpReceiver=10, payload=3, timestamp=20}).
find_msg_2_test() ->
		[#message{type=ack, seqNumber=1, lpSender=1, lpReceiver=10, payload=3, timestamp=20}] = 
			find_msg([#message{type=ack, seqNumber=1, lpSender=1, lpReceiver=10, payload=3, timestamp=20}, 
					#message{type=ack, seqNumber=11, lpSender=1, lpReceiver=11, payload=3, timestamp=10},
					#message{type=ack, seqNumber=12, lpSender=11, lpReceiver=13, payload=3, timestamp=30}],
					#message{type=ack, seqNumber=1, lpSender=1, lpReceiver=10, payload=3, timestamp=20}).


%
% It searches into the queue in input the correspondent message to the ack 
% @param MessageQueue: it could be a list or a queue
% @param Ack: a #message record 
% @param Type: the #message record type field of the message to ack
% @returns in case Queue is a list, [] if it does not find the message, the message otherwise;
%		   in case Queue is a queue, the output of the delete_element method
%
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

%% unit testing
find_message_to_ack_1_test() -> [] = find_message_to_ack([], 
										#message{type=ack, seqNumber=1, lpSender=11, lpReceiver=22, payload=3, timestamp=20}, 
										event).
find_message_to_ack_2_test() ->
	[#message{type=event, seqNumber=1, lpSender=11, lpReceiver=22, payload=3, timestamp=20}] = 
		find_message_to_ack([#message{type=event, seqNumber=1, lpSender=11, lpReceiver=22, payload=3, timestamp=20}, 
					#message{type=event, seqNumber=11, lpSender=1, lpReceiver=21, payload=3, timestamp=10},
					#message{type=event, seqNumber=12, lpSender=113, lpReceiver=22, payload=3, timestamp=30}], 
							#message{type=ack, seqNumber=1, lpSender=11, lpReceiver=22, payload=3, timestamp=20}, event).

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
%% @return: true if the entity's timestamp is lower, false otherwise
%%
check_correct_timestamp(LP_Timestamp, New_Timestamp) ->
	if 
		LP_Timestamp > New_Timestamp -> false;
		LP_Timestamp =< New_Timestamp -> true
	end. 


send_ack(Message, Lp) ->
	#message{type=_, seqNumber=SeqNumber, lpSender=LPSender, lpReceiver=LPReceiver, payload=Payload, timestamp=Timestamp} = Message,
	Ack = #message{type=ack, seqNumber=SeqNumber, lpSender=LPSender, lpReceiver=LPReceiver, payload=Payload, timestamp=Timestamp},
	send_message(Ack, Lp).


send_marked_ack(Message, Lp) ->
	#message{type=_, seqNumber=SeqNumber, lpSender=LPSender, lpReceiver=LPReceiver, payload=Payload, timestamp=Timestamp} = Message,
	Ack = #message{type=marked_ack, seqNumber=SeqNumber, lpSender=LPSender, lpReceiver=LPReceiver, payload=Payload, timestamp=Timestamp},
	send_message(Ack, Lp).

send_antimessage(Event, Lp) ->
	%SeqNumber = Lp#lp_status.messageSeqNumber + 1,
	#message{type=event, seqNumber=SeqNumber, lpSender=LPSender, lpReceiver=LPReceiver, payload=Payload, timestamp=Timestamp} = Event,
	Antimessage = #message{type=antimessage, seqNumber=SeqNumber, lpSender=LPSender, lpReceiver=LPReceiver, payload=Payload, timestamp=Timestamp},
	send_message(Antimessage, Lp).

%% 
%% Sends a list of antimessages
%% @param: a list of tuple like following one {Type, PidReceiver, Payload, Timestamp} 
%%
send_antimessages([], Lp) -> Lp;
send_antimessages([HeadEvent | Tail], Lp) -> 
	NewLp = send_antimessage(HeadEvent, Lp),
	send_antimessages(Tail, NewLp).

%% 
%% Sends a message to an entity
%% @param Type: a string correspondent to a message type (event, antimsg, ecc..)
%% @param PidReceiver: the receiver entity's pid
%% @param Payload: the content of the message
%% @param Timestamp: the executing timestamp of the message for the receiver's entity
%%
send_message(Message, LPStatus) ->
	MyLP = self(),
	if 
		(Message#message.type == ack) or (Message#message.type == marked_ack) ->
			LPDest = Message#message.lpSender;
		(Message#message.type == antimessage) or (Message#message.type == event) ->
			LPDest = Message#message.lpReceiver
	end,
	if
		LPDest /= MyLP ->
			LPDest ! Message,
			if 
				(Message#message.type == event) -> 
					LPStatus#lp_status{to_ack_messages=list_utils:insert_ordered(LPStatus#lp_status.to_ack_messages, Message), sent_messages=queue:in(Message, LPStatus#lp_status.sent_messages)};
				(Message#message.type == antimessage) -> 
					LPStatus#lp_status{to_ack_messages=list_utils:insert_ordered(LPStatus#lp_status.to_ack_messages, Message)};
				(Message#message.type == ack) or (Message#message.type == marked_ack) ->
					LPStatus
			end;
		LPDest == MyLP ->
			if 
				(Message#message.type == event) -> 
					LPStatus#lp_status{received_messages=queue:in(Message, LPStatus#lp_status.received_messages), sent_messages=queue:in(Message, LPStatus#lp_status.sent_messages)};
				(Message#message.type == antimessage) ->
					LPStatus#lp_status{received_messages=queue:in(Message, LPStatus#lp_status.received_messages)};
				(Message#message.type == ack) or (Message#message.type == marked_ack) ->
					LPStatus#lp_status{received_messages=queue:in(Message, LPStatus#lp_status.received_messages)}
			end
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
	HistoryToRestore = queue_utils:dequeue_history_until(Lp#lp_status.history, Event),
	IsHistoryToRestoreEmpty = queue:is_empty(HistoryToRestore),
	if
		IsHistoryToRestoreEmpty == true ->	
			init_state_vars(Lp);
		HistoryToRestore /= false ->
			restore_state_vars(queue:get_r(HistoryToRestore), Lp)
	end.
					
	
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



	
	
