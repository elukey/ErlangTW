-module(unit_test).

-include("user_include.hrl").
-include("common.hrl").
-include_lib("eunit/include/eunit.hrl").

all_test() ->
	lcg:test(),
	lp:test(),
	list_utils:test(),
	tree_utils:test(),
	queue_utils:test().
