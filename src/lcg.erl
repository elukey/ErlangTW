-module(lcg).
-export([get_random_01/1, get_random/3, get_exponential_random/1, get_init_seed/2]).

-include("user_include.hrl").
-include("common.hrl").
-include_lib("eunit/include/eunit.hrl").


get_random_01(Seed) ->
	A = 16807,
	M = 2147483647,
	NewSeed = (A  *  Seed) rem  M,
	{NewSeed  / M, NewSeed}.

get_random(Seed, Min, Max) ->
	if 
		Max < Min -> 0;
		Max >= Min -> 
			{Rand, NewSeed} = get_random_01(Seed),
			{trunc(Rand*(Max-Min+1))+Min, NewSeed}
	end.

get_exponential_random(Seed) ->
  {RandomNumber, NewSeed} = get_random_01(Seed),
  {round(-5.0 * math:log(RandomNumber) + 1), NewSeed}.



lcg_test(Times, Seed) when Times == 10000 -> Seed;
lcg_test(Times, Seed) ->
	{_, NewSeed} = get_random_01(Seed),
	lcg_test(Times + 1, NewSeed).


get_random_01_test() ->
	FinalSeed = lcg_test(0, 1),
	FinalSeed = 1043618065.

get_init_seed(LpNumber, Lps) ->
	trunc((LpNumber * 2147483646) / Lps).