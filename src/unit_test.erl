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
