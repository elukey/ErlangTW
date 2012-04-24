-module(tree_utils).

-export([safe_insert/2, retrieve_min/1, is_enqueued/2, delete/2, multi_safe_insert/2]).

-include("user_include.hrl").
-include("common.hrl").
-include_lib("eunit/include/eunit.hrl").


multi_safe_insert([], Tree) -> Tree;
multi_safe_insert([Element|Tail], Tree) ->
	multi_safe_insert(Tail, safe_insert(Element,Tree)).


multi_safe_insert_test() ->
	Event1 = #message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=100},
	Event2 = #message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=20},
	Event3 = #message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=330},
	Tree1 = safe_insert(Event1, safe_insert(Event2, safe_insert(Event3, gb_trees:empty()))),
	Tree2 = multi_safe_insert([Event1, Event2, Event3], gb_trees:empty()),
	{Key, FirstTree1} = gb_trees:smallest(Tree1),
	{Key, FirstTree2} = gb_trees:smallest(Tree2),
	SizeTree1 = gb_trees:size(Tree1),
	SizeTree2 = gb_trees:size(Tree2),
	SizeTree1 = SizeTree2,
	FirstTree1 = FirstTree2.

safe_insert(Element, Tree) ->
	%Result = gb_trees:is_defined(Element#message.timestamp, Tree),
	Key = Element#message.timestamp,
	Result = gb_trees:lookup(Key, Tree),
	if
		Result == none -> gb_trees:insert(Key, [Element], Tree);
		Result /= none -> 
			{value, Val} = Result,
			gb_trees:update(Key, sort_events([Element| Val]), Tree)
	end.
		

sort_events(ListUnsorted) ->
	lists:sort(fun(Event1, Event2) -> 
					   if Event1#message.seqNumber =< Event2#message.seqNumber -> true;
						  Event1#message.seqNumber > Event2#message.seqNumber -> false
						end
			   end, ListUnsorted).

retrieve_min(Tree) ->
	IsTreeEmpty = gb_trees:is_empty(Tree),
	if 
		IsTreeEmpty == true -> nothing;
		IsTreeEmpty == false ->
			{Timestamp, Val, NewTree} = gb_trees:take_smallest(Tree),
			ValLength = length(Val),
			if 
				ValLength == 1 ->
					[Element] = Val, 
					{Element, NewTree};
				ValLength > 1 ->
					[Element | TailElements] = Val,
					LastTree = gb_trees:insert(Timestamp, TailElements, NewTree),
					{Element, LastTree}
			end
	end.

is_enqueued(Element, Tree) ->
	KeySearchResult = gb_trees:lookup(Element#message.timestamp, Tree),
	if 
		KeySearchResult == none -> false;
		KeySearchResult /= none ->
			{value, ListOfEvents} = KeySearchResult,
			ElementSearchResult = [Event || Event <- ListOfEvents, Element == Event],
			if 
				ElementSearchResult == [] -> false;
				ElementSearchResult /= [] -> true
			end
	end.

delete(Element, Tree) ->
	Result = gb_trees:lookup(Element#message.timestamp, Tree),
	if 
		Result == none -> io:format("\nElement to delete not found\n"), Tree;
		Result /= none ->
			{value, ListOfEvents} = Result,
			NewListOfEvents = [Event || Event <- ListOfEvents, Event /= Element],
			if 
				length(NewListOfEvents) == length(ListOfEvents) -> io:format("\nElement to delete not found\n"), Tree;
				length(NewListOfEvents) == 0 -> gb_trees:delete(Element#message.timestamp, Tree);
				length(NewListOfEvents) /= length(ListOfEvents) -> gb_trees:update(Element#message.timestamp, NewListOfEvents, Tree)
			end
	end.		
					
%% integration testing 

integration_test() ->
	Event1 = #message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=100},
	Event2 = #message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=20},
	Event3 = #message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=330},
	Event4 = #message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=2},
	Event5 = #message{type=event, seqNumber=1, lpSender=1, lpReceiver=2, payload=3, timestamp=44},
	
	Tree = safe_insert(Event3, safe_insert(Event2, safe_insert(Event1, gb_trees:empty()))),
	true = is_enqueued(Event3, Tree),
	true = is_enqueued(Event1, Tree),
	true = is_enqueued(Event2, Tree),
	false = is_enqueued(Event4, Tree),
	{Event2, _} = retrieve_min(Tree), 
	Tree2 = safe_insert(Event5, safe_insert(Event4, Tree)),
	{Event4, Tree3} = retrieve_min(Tree2),
	{Event2, Tree4} = retrieve_min(Tree3),
	{Event5, Tree5} = retrieve_min(Tree4),
  	{Event1, Tree6} = retrieve_min(Tree5),
	{Event3, Tree7} = retrieve_min(Tree6),
	true = gb_trees:is_empty(Tree7),
	Tree8 = safe_insert(Event5, safe_insert(Event4, Tree7)),
	{Event4, _} = retrieve_min(Tree8),
	
	TreeDelete = safe_insert(Event3, safe_insert(Event2, safe_insert(Event1, gb_trees:empty()))),
	TreeDeleteEvent3 = delete(Event3, TreeDelete),
	TreeDeleteEvent2 = delete(Event2, TreeDelete),
	TreeDeleteEvent1 = delete(Event1, TreeDelete),
	false = is_enqueued(Event3, TreeDeleteEvent3),
	false = is_enqueued(Event2, TreeDeleteEvent2),
	false = is_enqueued(Event1, TreeDeleteEvent1),
	TreeDelete = delete(Event4, TreeDelete),
	
	Event1b = #message{type=event, seqNumber=1, lpSender=12, lpReceiver=23, payload=3, timestamp=100},
	Event2b = #message{type=event, seqNumber=12, lpSender=13, lpReceiver=211, payload=3, timestamp=20},
	Event3b = #message{type=event, seqNumber=55, lpSender=41, lpReceiver=2, payload=3, timestamp=330},
	
	TreeDeleteWithDuplicates = safe_insert(Event3b, safe_insert(Event2b, safe_insert(Event1b, TreeDelete))),
	TreeDeleteWithDuplicatesWithMultiSafeInsert = multi_safe_insert([Event1b, Event2b, Event3b], TreeDelete),
	TreeDeleteEvent3D = delete(Event3, TreeDeleteWithDuplicates),
	TreeDeleteEvent2D = delete(Event2, TreeDeleteWithDuplicates),
	TreeDeleteEvent1D = delete(Event1, TreeDeleteWithDuplicates),
	true = is_enqueued(Event3b, TreeDeleteEvent3D),
	true = is_enqueued(Event2b, TreeDeleteEvent2D),
	true = is_enqueued(Event1b, TreeDeleteEvent1D),
	true = is_enqueued(Event3b, TreeDeleteWithDuplicatesWithMultiSafeInsert),
	true = is_enqueued(Event2b, TreeDeleteWithDuplicatesWithMultiSafeInsert),
	true = is_enqueued(Event1b, TreeDeleteWithDuplicatesWithMultiSafeInsert).
	
	


