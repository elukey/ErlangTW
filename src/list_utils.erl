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
% Copyright Luca Toscano, Gabriele D'Angelo, Moreno Marzolla
% Computer Science Department, University of Bologna, Italy

-module(list_utils).
-export([insert_ordered_sublist/2, insert_ordered/2, early_state_var/1, first_element/1, not_match_nothing/1]).

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

