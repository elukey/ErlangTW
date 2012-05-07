import subprocess
import os
import math

def add(x,y): 
	return x+y
		
if __name__ == "__main__":
	print "\nAnalysis speed up\n"
	erlangtw_dir = "/home/luke/Desktop/ErlangTW"
	tests_dir = erlangtw_dir + "/tests/speedup"
	
	exp_runs = 100
	lps_list = [1,2,4,10]
	density = 0.5
	entities = 1000
	max_ts = 1000
	
	filenames_list = os.listdir(tests_dir)
	for lps in lps_list:
		filenames_current_lps = [filename for filename in filenames_list if "lp"+str(lps) in filename]
		value_list = []
		for filename in filenames_current_lps:
			filename_fd = open(tests_dir + "/" + filename, 'r')
			for line in filename_fd.readlines():
				if "Time taken:" in line:
					time_taken = line.split(":")[1].strip()
					value_list.append(float(time_taken))
			filename_fd.close()
		
		if len(value_list) > 0:
			total_runs = len(value_list)
			mean = reduce(add, value_list, 0) / total_runs
			var_aux = 0
			for x in value_list:
				var_aux = ((x - mean)**2) + var_aux
			var = var_aux / (total_runs -1)
				
			confidence_inf_mean = mean - 1.96 * (math.sqrt(var)/math.sqrt(total_runs))
			confidence_sup_mean = mean + 1.96 * (math.sqrt(var)/math.sqrt(total_runs))
			
			print "\nLP " + str(lps) + " runs have mean " + str(mean) + " with confidence " + \
					str(confidence_inf_mean) + " " + str(confidence_sup_mean)
		else:
			print "\nNothing found for lps " + str(lps)
	
	print "\nAnalysis completed!\n"
