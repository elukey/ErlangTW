-module(runner).

-export([main/3]).
-include("user_include.hrl").
-include("common.hrl").

main(EntityNum, LPNum, MaxTimestamp) -> 
	InitModelState = #state{value=1, seed=1, density=0.5, entities=EntityNum, lps=LPNum},
	create_LPs(LPNum, InitModelState),
	io:format("~nThreads spawned~n"),
	start(LPNum),
	io:format("~nThreads started~n"),
	gvt:gvt_controller(LPNum, MaxTimestamp).


create_LPs(LPNum, _) when LPNum == 0 -> ok;
create_LPs(LPNum, InitModelState) ->
	Pid = spawn(lp,start,[LPNum,InitModelState]),
	global:register_name(list_to_atom(string:concat("lp_",integer_to_list(LPNum))),Pid),
	link(Pid),
	create_LPs(LPNum-1, InitModelState).

start(0) -> ok;
start(Remaining) when Remaining > 0 ->
	Pid = user:get_pid(Remaining),
	Pid ! {start},
	start(Remaining-1).
	
