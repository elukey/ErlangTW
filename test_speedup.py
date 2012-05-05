import subprocess

def create_config_file(filepath, content):
	filefd = open(filepath, 'w')
	filefd.write(content)
	filefd.close()

def get_config_file_content(density, lps, max_ts, entities, seed):
	return "lps="+str(lps)+"\ndensity="+str(density)+"\nentities="+str(entities)+"\nmax_ts="+str(max_ts)+"\nseed="+str(seed) 

if __name__ == "__main__":
	print "\nTesting speed up\n"
	erlangtw_dir = "/home/luke/Desktop/ErlangTW"
	tests_dir = erlangtw_dir + "/tests"
	
	exp_runs = 100
	lps_list = [1,2,4,10]
	density = 0.5
	entities = 1000
	max_ts = 1000
	
	for lps in lps_list:
		for run in range(1, exp_runs):
			print "\nRun " + str(run) + " of " + str(exp_runs) + "\n"  
			config_file_content = get_config_file_content(density, lps, max_ts, entities, run)
			config_file_path = tests_dir + "/" + "config_speedup_lp"+str(lps)+"_run"+str(run)
			create_config_file(config_file_path, config_file_content)
			output_file_path = tests_dir + "/" + "output_speedup_lp"+str(lps)+"_run"+str(run)
			subprocess.call(["./starter",config_file_path, output_file_path])
	
	print "\nExperiment completed!\n"
