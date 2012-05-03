-module(runner).

-export([main/4, create_LPs/3, stop_vms/1]).
-include("user_include.hrl").
-include("common.hrl").

main(LPNum, EntitiesNum, MaxTimestamp, Topology) ->
	StartTimestamp = erlang:now(),
	Density = 0.5, 
	InitModelState = #state{value=1, seed=303123, density=Density, lps=LPNum,  
							entities=EntitiesNum, entities_state=dict:new(),
							max_timestamp=MaxTimestamp},
	if
		Topology == sequential ->
			create_LPs(1, LPNum, InitModelState);
		Topology == distributed ->
			ConnectedErlangVM = net_adm:world(),
			LenConnectedErlangVM = length(ConnectedErlangVM),
			if 
				LenConnectedErlangVM >= 1 -> ok;
				LenConnectedErlangVM == 0 -> erlang:exit("Some problems during the connection with the other erlang vms, please check.")
			end,
			io:format("\nConnected with the following nodes: ~w\n", [ConnectedErlangVM]),
			call_vms(ConnectedErlangVM, LenConnectedErlangVM, LPNum, LenConnectedErlangVM, InitModelState),
			global:sync()
	end,
	start(LPNum),
	gvt:gvt_controller(LPNum, MaxTimestamp),
	EndTimestamp = erlang:now(),
	io:format("\nTime taken: ~w", [timer:now_diff(EndTimestamp, StartTimestamp)/1000000]).


stop_vms([]) -> ok;
stop_vms([Node| RestOfNodes]) ->
	if 
		node() == Node -> 
			ok;
		node() /= Node ->
			rpc:call(Node, init, stop, [])
	end, 
	stop_vms(RestOfNodes).

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
	Pid = spawn(lp,start,[LPNumMaxIndex,InitModelState]),
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
	
