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
% Copyright Luca Toscano, PADS team members (Univ. of Bologna) 
% (http://pads.cs.unibo.it/dokuwiki/doku.php?id=pads:people

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
	NewQueue = queue:from_list([{not_imp, not_imp, #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=1}}]),
	ElementToRestore = {not_imp, not_imp, #message{type=event, seqNumber=1, lpSender=1, lpReceiver=1, payload=1, timestamp=2}},
	{ElementToRestore, NewQueue} = dequeue_history_until(Queue, Message).
	
dequeue_until(Message, Queue) ->
	if 
		Message#message.type == event ->
			dequeue_until_timestamp(Queue, Message#message.timestamp, []);
		Message#message.type == antimessage ->
			dequeue_until_event(Queue, Message#message{type=event}, [])
	end.

dequeue_until_event(Queue, EventToMatch, Acc) ->	
	Guard = queue:is_empty(Queue),
	if
		Guard == true -> {Queue, Acc};
		Guard == false ->
			{{value, ItemDequeued}, NewQueue} = queue:out_r(Queue),
			#sent_msgs{event=Event} = ItemDequeued,
			if
				Event /= EventToMatch -> 
					 dequeue_until_event(NewQueue, EventToMatch, [ItemDequeued | Acc]);
				Event == EventToMatch -> {Queue, Acc}
			end
	end.


dequeue_until_timestamp(Queue, Timestamp, Acc) ->
	Guard = queue:is_empty(Queue),
	if
		Guard == true -> {Queue, Acc};
		Guard == false ->
			#sent_msgs{event=Event} = queue:get_r(Queue),
			if
				Event#message.timestamp >= Timestamp -> 
					 {{value, ItemDequeued}, NewQueue} = queue:out_r(Queue),
					 dequeue_until_timestamp(NewQueue, Timestamp, [ItemDequeued | Acc]);
				Event#message.timestamp < Timestamp -> {Queue, Acc}
			end
	end.



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




			
