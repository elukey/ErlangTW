-module(runner).

-export([main/2, distributed_main/2, create_LPs/3]).
-include("user_include.hrl").
-include("common.hrl").

main(LPNum, MaxTimestamp) -> 
	InitModelState = #state{value=1, seed=LPNum, density=0.5, lps=LPNum, starting_events=10},
	create_LPs(1, LPNum, InitModelState),
	io:format("~nThreads spawned~n"),
	start(LPNum),
	io:format("~nThreads started~n"),
	gvt:gvt_controller(LPNum, MaxTimestamp).


distributed_main(LPNum, MaxTimestamp) ->
	InitModelState = #state{value=1, seed=LPNum, density=0.5, lps=LPNum, starting_events=10},
	ConnectedErlangVM = net_adm:world(),
	LenConnectedErlangVM = length(ConnectedErlangVM),
	if 
		LenConnectedErlangVM >= 1 -> ok;
		LenConnectedErlangVM == 0 -> erlang:exit("Some problems during the connection with the other erlang vms, please check.")
	end,
	io:format("\nConnected with the following nodes: ~w\n", [ConnectedErlangVM]),
	call_vms(ConnectedErlangVM, LenConnectedErlangVM, LPNum, LenConnectedErlangVM, InitModelState),
	global:sync(),
	start(LPNum),
	gvt:gvt_controller(LPNum, MaxTimestamp).

call_vms([], 0, _, _, _) -> ok;
call_vms([Node| RestOfNodes], VMIndex,  LpNum, VMNum, InitModelState)->
	FirstLpIndex = get_first_lp_index(VMIndex, LpNum, VMNum),
	LastLpIndex = get_last_lp_index(VMIndex, LpNum, VMNum),
	io:format("\nDeploying Lps from ~w to ~w on node ~w", [FirstLpIndex, LastLpIndex, Node]),
	if 
		node() == Node -> 
			Result = create_LPs(FirstLpIndex, LastLpIndex, InitModelState);
		node() /= Node ->
			Result = rpc:call(Node, runner, create_LPs, [FirstLpIndex, LastLpIndex, InitModelState])
	end,
	case Result of 
		{badrpc, Error} -> erlang:error(Error);
		Result -> ok
	end,
	io:format("\n~w has ~w ~w", [Node, FirstLpIndex, LastLpIndex]),
	call_vms(RestOfNodes, VMIndex-1,  LpNum, VMNum, InitModelState).


create_LPs(LPNumMinIndex, LPNumMaxIndex,  _) when LPNumMaxIndex < LPNumMinIndex -> ok;
create_LPs(LPNumMinIndex, LPNumMaxIndex, InitModelState) ->
	Pid = spawn(lp,start,[LPNumMaxIndex,InitModelState#state{seed=LPNumMaxIndex}]),
	Result = global:register_name(list_to_atom(string:concat("lp_",integer_to_list(LPNumMaxIndex))),Pid),
	if 
		Result == yes -> ok;
		Result == no ->
			erlang:error("Global register name has failed!")
	end,
	link(Pid),
	create_LPs(LPNumMinIndex, LPNumMaxIndex-1, InitModelState).

start(0) -> ok;
start(Remaining) when Remaining > 0 ->
	Pid = user:get_pid(Remaining),
	Pid ! {start},
	start(Remaining-1).

get_first_lp_index(VMIndex, TotalLps, TotalVMs) ->
	trunc((VMIndex - 1)*(TotalLps / TotalVMs)+1).

get_last_lp_index(VMIndex, TotalLps, TotalVMs) ->
	get_first_lp_index(VMIndex, TotalLps, TotalVMs)  + trunc(TotalLps/TotalVMs) -1.
	
