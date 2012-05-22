import subprocess
import os
import math
import re

def add(x,y): 
	return x+y
		
if __name__ == "__main__":
	print "\nAnalysis speed up\n"
	erlangtw_dir = "/home/luke/Desktop/ErlangTW"
	tests_dir = erlangtw_dir + "/tests"
	
	exp_runs = 10
	lps_list = [1,2]
	entities_list = [1000]
	workloads = [1000,10000]
	
	filenames_list = os.listdir(tests_dir)
	
	
	for entities in entities_list:
		for workload in workloads:
			for lps in lps_list:
				print "\nResults for lp " + str(lps) + " workload " + str(workload) + " entities " + str(entities)
				regexp = "output_\w*lp"+str(lps)+"_\w*workload"+str(workload)+"_\w*entities"+str(entities)+"$"
				filenames = [filename for filename in filenames_list if re.search(regexp, filename) != None]
				print "\nFiles found: " + str(len(filenames))
				time_list = []
				rollbacks = []
				for filename in filenames:
					filename_fd = open(tests_dir + "/" + filename, 'r')
					total_rollbacks_lps = 0
					for line in filename_fd.readlines():
						if "Time taken:" in line:
							time_taken = line.split(":")[1].strip()
							time_list.append(float(time_taken))
						if "rollbacks" in line:
							rollback_n = line.split(" ")[4].strip()
							total_rollbacks_lps = total_rollbacks_lps + int(rollback_n)
					filename_fd.close()
					rollbacks.append(total_rollbacks_lps)
			
				if len(rollbacks) > 0:
					total_runs = len(filenames)
					mean = reduce(add, rollbacks, 0) / total_runs
					var_aux = 0
					for x in time_list:
						var_aux = ((x - mean)**2) + var_aux
					var = var_aux / (total_runs -1)
				
					confidence = 1.96 * (math.sqrt(var)/math.sqrt(total_runs))
			
					print "\nLP " + str(lps) + " rollbacks have mean " + str(mean) + " with confidence " + str(confidence)
			
		
				else:
					print "\nNo rollbacks data for lps " + str(lps)
			
		
				if len(time_list) > 0:
					total_runs = len(time_list)
					mean = reduce(add, time_list, 0) / total_runs
					var_aux = 0
					for x in time_list:
						var_aux = ((x - mean)**2) + var_aux
					var = var_aux / (total_runs -1)
				
					confidence = 1.96 * (math.sqrt(var)/math.sqrt(total_runs))
			
					print "\nLP " + str(lps) + " WCT have mean " + str(mean) + " with confidence " + str(confidence)
				else:
					print "\nNo time taken data for lps " + str(lps)
	
	print "\nAnalysis completed!\n"
