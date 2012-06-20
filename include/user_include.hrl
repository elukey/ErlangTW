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

-record(state, {value, seed, density, lps, entities, entities_state, max_timestamp, workload}).
-record(payload, {entitySender, entityReceiver, value}).
-record(entity_state, {seed, timestamp}).
