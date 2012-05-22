import subprocess
import os
import math

def add(x,y): 
	return x+y
		
if __name__ == "__main__":
	print "\nAnalysis speed up\n"
	erlangtw_dir = "/home/toscano/ErlangTW"
	tests_dir = erlangtw_dir + "/tests/speedup_fp10000_1000e"
	
	exp_runs = 100
	lps_list = [1,2,4,10]
	
	filenames_list = os.listdir(tests_dir)
	for lps in lps_list:
		filenames_current_lps = [filename for filename in filenames_list if "lp"+str(lps)+"_" in filename]
		time_list = []
		rollbacks = []
		for filename in filenames_current_lps:
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
			total_runs = exp_runs
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
