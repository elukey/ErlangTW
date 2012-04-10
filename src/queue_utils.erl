-module(queue_utils).

-export([dequeue_until/2, delete_element/2, dequeue_history_until/2]).

-include("user_include.hrl").
-include("common.hrl").
-include_lib("eunit/include/eunit.hrl").


dequeue_history_until(Queue, Message) ->
	Guard = queue:is_empty(Queue),
	if
		Guard == true -> Queue;
		Guard == false ->
			{_,_,Item} = queue:get_r(Queue),
			if
				Item == Message ->
					{{value,Tail}, NewQueue} = queue:out_r(Queue),
					{Tail, NewQueue};
				Item /= Message ->
					{_, NewQueue} = queue:out_r(Queue),
					dequeue_history_until(NewQueue, Message)
			end
	end.	

dequeue_history_until_test() ->
	Queue = queue:from_list([{not_imp, not_imp, #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}},
	 {not_imp, not_imp, #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2}},
	 {not_imp, not_imp, #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}}]),
	Message = #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2},
	Result = queue:from_list([{not_imp, not_imp, #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}},
	 {not_imp, not_imp, #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2}}]),
	Result = dequeue_history_until(Queue, Message).
	
dequeue_until(Queue, Timestamp) ->
	dequeue_until_aux(Queue, Timestamp, []).

dequeue_until_aux(Queue, Timestamp, Acc) ->	
	Guard = queue:is_empty(Queue),
	if
		Guard == true -> {Queue, Acc};
		Guard == false ->
			Item = queue:get_r(Queue),
			if
				Item#message.timestamp >= Timestamp -> 
					 {{value, ItemDequeued}, NewQueue} = queue:out_r(Queue),
					 dequeue_until_aux(NewQueue, Timestamp, [ItemDequeued] ++ Acc);
				Item#message.timestamp < Timestamp -> {Queue, Acc}
			end
	end.

dequeue_until_test() ->
	Queue = queue:from_list([#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}]),
	QueueResult = queue:from_list([#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}]),
	{QueueResult, [#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}]} = 
		dequeue_until(Queue, 1).

dequeue_until_2_test() ->
	Queue = queue:from_list([#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}]),
	QueueResult = queue:new(),
	{QueueResult, [#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}]} = dequeue_until(Queue, 1).

dequeue_until_3_test() ->
	Queue = queue:from_list([#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}]),
	{Queue, []} = dequeue_until(Queue, 4).



delete_element(Queue, Element) ->
	CheckPresence = queue:member(Element, Queue),
	if 
		CheckPresence == true ->
			queue:filter(fun(X) -> if X /= Element ->true; X == Element -> false end end, Queue);
		CheckPresence == false -> false
	end.

delete_elemet_test() ->
	Queue = queue:from_list([#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}]),
	QueueResult = queue:from_list([#message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2},
	 #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=3}]),
	QueueResult = delete_element(Queue, #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}).

delete_elemet_2_test() ->
	Queue = queue:new(),
	false = delete_element(Queue, #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}).




			