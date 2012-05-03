-module(lcg).
-export([get_random_01/1, get_random/3, get_exponential_random/1, get_init_seed/2, get_random_01_combined/1]).

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


% Combined linear congruential generators

get_random_01_combined(Seed) ->
   {S10, S11, S12, S20, S21, S22} = Seed,
   Norm =  2.328306549295728e-10,
   M1 = 4294967087.0,
   M2 = 4294944443.0,
   A12 = 1403580.0,
   A13n = 810728.0,
   A21 = 527612.0,
   A23n = 1370589.0,
   P1 = A12 * S11 - A13n * S10,
   K = P1 / M1,
   if 
	  (P1 - K * M1) < 0.0 -> P1n = (P1 - K * M1) + M1;
	  (P1 - K * M1) >= 0.0 -> P1n = (P1 - K * M1)
   end,
   P2 = A21 * S22 - A23n * S20,
   K2 = P2 / M2,
   if 
	  (P2 - K2 * M2) < 0.0 -> P2n = P2 - K2 * M2 + M2;
      (P2 - K2 * M2) >= 0.0 -> P2n = P2 - K2 * M2
   end,
   NewSeed = {S11, S12, P1n, S21, S22, P2n},
   if 
	   P1n =< P2n -> {(P1n - P2n + M1) * Norm, NewSeed};
   	   P1n > P2n -> {(P1n - P2n) * Norm, NewSeed}
   end.



