
// Xenofarm Garbage Collect
// By Martin Nilsson
// $Id: gc.pike,v 1.3 2002/08/20 17:31:56 mani Exp $

string out_dir = "/home/nilsson/xenofarm/out/";
string result_dir = "/home/nilsson/html/xenofarm_results/";

int gc_poll = 60*60*2;
int dists_left = 1;
int results_left = 11;

void debug(string msg, mixed ... args) {
  write("[" + Calendar.ISO.now()->format_tod() + "] "+msg, @args);
}

void clean_out_dir(string dir, int save) {

  array files = get_dir(dir);
  array times = map(files,
		    lambda(string in) {
		      return file_stat( combine_path(dir,in) )->ctime;
		    } );
  sort(times, files);
  files = files[..sizeof(files)-save-1];

  foreach(files, string file)
    if(!rm(combine_path(dir,file)))
      debug("Could not delete %s.\n", combine_path(dir,file));
    else
      debug("Removed file %s\n", combine_path(dir,file));
}

void clean_res_dir(string dir, int save) {

  array files = get_dir(dir);
  multiset|array builds = map(files, lambda(string in) {
				       int b;
				       sscanf(in, "%d_", b);
				       return b;
				     });
  builds -= ({ 0 });
  builds = Array.uniq(sort(builds));
  builds = builds[..sizeof(builds)-1-save];
  builds = (multiset)builds;

  foreach(files, string file) {
    if(!has_value(file, "_")) continue;
    int b;
    sscanf(file, "%d_", b);
    if( builds[b] ) {
      if( !Stdio.recursive_rm(combine_path(dir,file)) )
	debug("Cuild not delete %s.\n", combine_path(dir,file));
      else
	debug("Removed directory %s\n", combine_path(dir,file));
    }
  }

}

int main(int n, array(string) args) {

  foreach(Getopt.find_all_options(args, ({
    ({ "out_dir",   Getopt.HAS_ARG, "--out-dir"        }),
    ({ "result_dir",Getopt.HAS_ARG, "--result-dir"     }),
    ({ "poll",      Getopt.HAS_ARG, "--poll"           }),
    ({ "dists",     Getopt.HAS_ARG, "--dists-left"     }),
    ({ "results",   Getopt.HAS_ARG, "--results-left"   }),
    ({ "help",      Getopt.NO_ARG,  "--help"           }),
  }) ),array opt)
    {
      switch(opt[0])
      {
      case "out_dir":
	out_dir = opt[1];
	break;

      case "result_dir":
	result_dir = opt[1];
	break;

      case "poll":
	gc_poll = (int)opt[1];
	break;

      case "dists":
	dists_left = (int)opt[1];
	break;

      case "results":
	results_left = (int)opt[1];
	break;

      case "help":
	write(prog_doc);
	return 0;
      }
    }

  while(1) {
    clean_out_dir(out_dir, dists_left);
    clean_res_dir(result_dir, results_left);
    debug("Waiting...\n");
    sleep(gc_poll);
  }

}

constant prog_doc = #"
--out-dir
--result-dir
--poll
--dists-left
--results-left
--help
";
