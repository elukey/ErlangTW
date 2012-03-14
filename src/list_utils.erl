-module(list_utils).
-export([insert_ordered_sublist/2, insert_ordered/2, weak_match_pred/1, weak_not_match_pred/1, early_state_var/1, first_element/1, not_match_nothing/1]).

-include("user_include.hrl").
-include("common.hrl").
-include_lib("eunit/include/eunit.hrl").


%%
%% Inserts messages contained into a list in another (ordered one).
%%
insert_ordered_sublist(List, []) -> List;
insert_ordered_sublist(List, [Head|Tail]) -> 
	insert_ordered_sublist(insert_ordered(List, Head), Tail).

%% unit testing
insert_ordered_sublist_1_test() ->
	[#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}] = 
		list_utils:insert_ordered_sublist([], [#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}]).	
insert_ordered_sublist_2_test() -> 
	[#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}, 
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}] = 
		list_utils:insert_ordered_sublist([#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}], 
										  [#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}]).
insert_ordered_sublist_3_test() -> 
	[#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}] = 
		list_utils:insert_ordered_sublist([#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}], 
										  [#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}, 
										   #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2}]).

%%
%% Inserts a message in a list respecting the ordering accoring to its timestamp
%%
insert_ordered([], Message) -> 
	[Message];
insert_ordered([Head|Tail], Message) ->
	#message{type=_, seqNumber=_, lpSender=_, lpReceiver=_, payload=_, timestamp=Timestamp} = Message,
	#message{type=_, seqNumber=_, lpSender=_, lpReceiver=_, payload=_, timestamp=HeadTimestamp} = Head,
	if
		Timestamp =< HeadTimestamp -> [Message, Head] ++ Tail;
		Timestamp > HeadTimestamp -> [Head | insert_ordered(Tail, Message)]
	end.

%% unit testing
insert_ordered_1_test() -> 
	[#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}] = 
		list_utils:insert_ordered([], #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}).
insert_ordered_2_test() -> 
	[#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1},#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}] = 
		list_utils:insert_ordered([#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}], 
								  #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}).
insert_ordered_3_test() -> 
	[#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}] = 
		list_utils:insert_ordered([#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}, 
								   #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}], 
								   #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2}).



weak_match_pred(MessageToMatch) -> 
	#message{type=_, seqNumber=SeqToMatch, lpSender=lpSenderToMatch, lpReceiver=lpReceiverToMatch, 
			 payload=PayloadToMatch, timestamp=TimestampToMatch} = MessageToMatch,
	fun(Message) ->
		#message{type=_, seqNumber=SeqMessage, lpSender=lpSenderMessage, lpReceiver=lpReceiverMessage, 
			 payload=PayloadMessage, timestamp=TimestampMessage} = Message,		
		if
			{SeqToMatch, lpSenderToMatch, lpReceiverToMatch, PayloadToMatch, TimestampToMatch} == {SeqMessage, lpSenderMessage, lpReceiverMessage, 
			PayloadMessage, TimestampMessage} ->	true;
			{SeqToMatch, lpSenderToMatch, lpReceiverToMatch, PayloadToMatch, TimestampToMatch} /= {SeqMessage, lpSenderMessage, lpReceiverMessage, 
			PayloadMessage, TimestampMessage} ->	false
		end
	end.

%% unit testing
weak_match_pred_1_test() -> true = (list_utils:weak_match_pred(#message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=20}))
							  (#message{type=ack, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=20}).
weak_match_pred_2_test() -> false = (list_utils:weak_match_pred(
								 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=20}))
							  (#message{type=ack, seqNumber=12, lpSender=1, lpReceiver=2, payload=3, timestamp=20}). 


weak_not_match_pred(MessageToMatch) -> 
	#message{type=_, seqNumber=SeqToMatch, lpSender=lpSenderToMatch, lpReceiver=lpReceiverToMatch, 
			 payload=PayloadToMatch, timestamp=TimestampToMatch} = MessageToMatch,
	fun(Message) ->
		#message{type=_, seqNumber=SeqMessage, lpSender=lpSenderMessage, lpReceiver=lpReceiverMessage, 
			 payload=PayloadMessage, timestamp=TimestampMessage} = Message,		
		if
			{SeqToMatch, lpSenderToMatch, lpReceiverToMatch, PayloadToMatch, TimestampToMatch} == {SeqMessage, lpSenderMessage, lpReceiverMessage, 
			PayloadMessage, TimestampMessage} ->	false;
			{SeqToMatch, lpSenderToMatch, lpReceiverToMatch, PayloadToMatch, TimestampToMatch} /= {SeqMessage, lpSenderMessage, lpReceiverMessage, 
			PayloadMessage, TimestampMessage} ->	true
		end
	end.

%% unit testing
weak_not_match_pred_1_test() -> false = (list_utils:weak_not_match_pred(#message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=20}))
							  (#message{type=ack, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=20}).
weak_not_match_pred_2_test() -> true = (list_utils:weak_not_match_pred(#message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=20}))
							  (#message{type=ack, seqNumber=12, lpSender=1, lpReceiver=2, payload=3, timestamp=20}). 



not_match_nothing([]) -> [];
not_match_nothing([Head|Tail]) -> 
	if 
		Head == nothing -> not_match_nothing(Tail);
		Head /= nothing -> [Head | not_match_nothing(Tail)]
	end.

%% unit testing
not_match_nothing_1_test() -> [] = not_match_nothing([nothing, nothing, nothing]).
not_match_nothing_2_test() -> [{1,2,3}, {2,3,3}] = not_match_nothing([{1,2,3}, nothing, {2,3,3}]).


%% Get the first element of a list
%% @return: nothing if the list is empty, the Head of the list otherwise
first_element([]) -> [];
first_element([Head|_]) -> Head.

% unit testing 
first_element_1_test() -> [] = first_element([]).
first_element_2_test() -> 1 = first_element([1,2,3,4]).


%%
%% Predicate able to compare an entity's history state
%% @input TimestampPivot: the timestamp to compare
%% @return the predicate function
early_state_var(TimestampPivot) ->
	fun({Timestamp, _, _}) ->
		if
			Timestamp =< TimestampPivot -> true;
			Timestamp > TimestampPivot -> false
		end
	end.

%% unit testing
early_state_var_1_test() -> false = (early_state_var(10))({11, prova, prova}).
early_state_var_2_test() -> true = (early_state_var(10))({0, prova, prova}).


a_test() -> 
	A = #message{type=a, lpSender=b, lpReceiver=c, seqNumber=2, timestamp=11, payload=1},
	B = #message{type=a2, lpSender=b2, lpReceiver=c2, seqNumber=23, timestamp=112, payload=31},
	[A,A,A] = [X || X <- [A,B,A,B,A,B], X /= B].

