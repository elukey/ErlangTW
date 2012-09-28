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
% Copyright 2012, Luca Toscano, Gabriele D'Angelo, Moreno Marzolla
% Computer Science Department, University of Bologna, Italy

-module(runner).

-export([main/2, create_LPs/3, stop_vms/1]).
-include("user_include.hrl").
-include("common.hrl").



get_model_config_scanner() ->
	fun(ParsedLine, Acc) ->
			TokenList = string:tokens(ParsedLine, "="),
			LenTokenList = length(TokenList),
			if
				 LenTokenList == 2 ->
					case string:strip(lists:nth(1, TokenList)) of
						"density" -> [{"density", list_to_float(string:strip(string:strip(lists:nth(2, TokenList)), right, $\n))}|Acc];
						"lps" -> [{"lps", list_to_integer(string:strip(string:strip(lists:nth(2, TokenList)), right, $\n))}|Acc];
						"entities" -> [{"entities", list_to_integer(string:strip(string:strip(lists:nth(2, TokenList)), right, $\n))}|Acc];
						"seed" -> [{"seed", list_to_integer(string:strip(string:strip(lists:nth(2, TokenList)), right, $\n))}|Acc];
						"max_ts" -> [{"max_ts", list_to_integer(string:strip(string:strip(lists:nth(2, TokenList)), right, $\n))}|Acc];
						"workload" -> [{"workload", list_to_integer(string:strip(string:strip(lists:nth(2, TokenList)), right, $\n))}|Acc];
						_ -> io:format("\nError during reading the config file, option not recognized: ~w", [lists:nth(1, TokenList)]),
						erlang:exit(-1)
					end;
				LenTokenList /= 2 -> Acc
		  end
	end.

read_model_configuration(FileName) ->
    {ok, Device} = file:open(FileName, [read]),
    ParametersList = for_each_line(Device, get_model_config_scanner(), []),
	dict:from_list(ParametersList).

for_each_line(Device, Proc, Acc) ->
    case file:read_line(Device) of
		{error, Reason} -> io:format("\nError during reading ~w", [Reason]), Acc;
        eof  -> file:close(Device), Acc;
        {ok, Line} -> NewAccum = Proc(Line, Acc),
                    for_each_line(Device, Proc, NewAccum)
    end.

main(ConfigFilePath, Topology) ->
	StartTimestamp = erlang:now(),
	
	ParametersDict = read_model_configuration(ConfigFilePath),
	Density = dict:fetch("density", ParametersDict),
	LPNum = dict:fetch("lps", ParametersDict),
	EntitiesNum = dict:fetch("entities", ParametersDict), 
	MaxTimestamp = dict:fetch("max_ts", ParametersDict),
	Seed = dict:fetch("seed", ParametersDict),
	Workload = dict:fetch("workload", ParametersDict),
	
	InitModelState = #state{value=1, seed=Seed, density=Density, lps=LPNum,  
							entities=EntitiesNum, entities_state=none,
							max_timestamp=MaxTimestamp, workload=Workload},
	if
		Topology == parallel ->
			create_LPs(1, LPNum, InitModelState);
		Topology == distributed ->
			ConnectedErlangVM = net_adm:world(),
			LenConnectedErlangVM = length(ConnectedErlangVM),
			if 
				LenConnectedErlangVM >= 1 -> ok;
				LenConnectedErlangVM == 0 -> erlang:exit("Some problems during the connection with the other erlang vms, please check.")
			end,
			error_logger:info_msg("~nConnected with the following nodes: ~p~n", [ConnectedErlangVM]),
			call_vms(ConnectedErlangVM, LenConnectedErlangVM, LPNum, LenConnectedErlangVM, InitModelState),
			global:sync()
	end,
	start(LPNum),
	gvt:gvt_controller(LPNum, MaxTimestamp),
	EndTimestamp = erlang:now(),
	error_logger:info_msg("~nTime taken: ~p~n", [timer:now_diff(EndTimestamp, StartTimestamp)/1000000]).


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
	%Pid = spawn(lp,start,[LPNumMaxIndex,InitModelState]),
	%Result = global:register_name(list_to_atom(string:concat("lp_",integer_to_list(LPNumMaxIndex))),Pid),
	{Result,_} = lp:start_link(string:concat("lp_",integer_to_list(LPNumMaxIndex)), InitModelState#state{lp_id=LPNumMaxIndex}),
	if 
		Result == ok -> ok;
		Result == error ->
			%erlang:error("Global register name has failed!")
			erlang:error("Lp start link has failed!")
	end,
	%link(Pid),
	create_LPs(LPNumMinIndex, LPNumMaxIndex-1, InitModelState).

start(0) -> ok;
start(Remaining) when Remaining > 0 ->
	LPId = string:concat("lp_",integer_to_list(Remaining)),
	lp:start_simulating(LPId),
	start(Remaining-1).

get_first_lp_index(VMIndex, TotalLps, TotalVMs) ->
	trunc((VMIndex - 1)*(TotalLps / TotalVMs)+1).

get_last_lp_index(VMIndex, TotalLps, TotalVMs) ->
	get_first_lp_index(VMIndex, TotalLps, TotalVMs)  + trunc(TotalLps/TotalVMs) -1.
	
