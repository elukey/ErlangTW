#
# This file is part of ErlangTW.  ErlangTW is free software: you can
# redistribute it and/or modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation, version 2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 51
# Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# Copyright Luca Toscano, Gabriele D'Angelo, Moreno Marzolla
# Computer Science Department, University of Bologna, Italy

import subprocess
import random

def create_config_file(filepath, content):
	filefd = open(filepath, 'w')
	filefd.write(content)
	filefd.close()

def get_config_file_content(density, lps, max_ts, entities, seed, workload):
	return "lps="+str(lps)+"\ndensity="+str(density)+"\nentities="+str(entities)+"\nmax_ts="+str(max_ts)+"\nseed="+str(seed)+"\nworkload="+str(workload)

if __name__ == "__main__":
	print "\nTesting speed up\n"
	erlangtw_dir = "/home/luke/Desktop/ErlangTW"
	tests_dir = erlangtw_dir + "/tests"
	
	exp_runs = 10
	lps_list = [1,2]
	density = 0.5
	entities_list = [1000]
	max_ts = 1000
	workloads = [10000]
	
	for lps in lps_list:
		for entities in entities_list:
			for workload in workloads:
				for run in range(1, exp_runs+1):
					random.seed(lps+entities+workload)
					seed_run = random.randint(1,1147483647)
					if seed_run % 2 == 0:
						seed_run = seed_run + 1
					print "\nRun " + str(run) + " of " + str(exp_runs) + " with workload " + str(workload) + " and entities " + str(entities) + "\n"  
					config_file_content = get_config_file_content(density, lps, max_ts, entities, seed_run, workload)
					suffix = str(lps)+"_run"+str(run)+"_workload"+str(workload)+"_entities"+str(entities)
					config_file_path = tests_dir + "/" + "config_speedup_lp"+suffix
					create_config_file(config_file_path, config_file_content)
					output_file_path = tests_dir + "/" + "output_speedup_lp"+suffix
					subprocess.call(["./starter",config_file_path, output_file_path])
	
	print "\nExperiment completed!\n"
