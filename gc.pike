
// Xenofarm Garbage Collect
// By Martin Nilsson
// $Id: gc.pike,v 1.5 2002/08/30 01:36:43 mani Exp $

string out_dir;
string result_dir;

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

void check_settings() {

  if(!out_dir) {
    write("No out directory found.\n");
    exit(1);
  }
  if(!file_stat(out_dir) || !file_stat(out_dir)->isdir) {
    write("Out directory %s does not exist.\n", out_dir);
    exit(1);
  }

  if(!result_dir) {
    write("No result directory found.\n");
    exit(1);
  }
  if(!file_stat(result_dir) || !file_stat(result_dir)->isdir) {
    write("Result directory %s does not exist.\n", result_dir);
    exit(1);
  }

}

int main(int n, array(string) args) {

  foreach(Getopt.find_all_options(args, ({
    ({ "dists",     Getopt.HAS_ARG, "--dists-left"     }),
    ({ "help",      Getopt.NO_ARG,  "--help"           }),
    ({ "out_dir",   Getopt.HAS_ARG, "--out-dir"        }),
    ({ "poll",      Getopt.HAS_ARG, "--poll"           }),
    ({ "result_dir",Getopt.HAS_ARG, "--result-dir"     }),
    ({ "results",   Getopt.HAS_ARG, "--results-left"   }),
  }) ),array opt)
    {
      switch(opt[0])
      {
      case "dists":
	dists_left = (int)opt[1];
	break;

      case "help":
	write(prog_doc);
	return 0;

      case "out_dir":
	out_dir = opt[1];
	break;

      case "poll":
	gc_poll = (int)opt[1];
	break;

      case "result_dir":
	result_dir = opt[1];
	break;

      case "results":
	results_left = (int)opt[1];
	break;
      }
    }

  check_settings();

  while(1) {
    clean_out_dir(out_dir, dists_left);
    clean_res_dir(result_dir, results_left);
    debug("Waiting...\n");
    sleep(gc_poll);
  }

}

constant prog_doc = #"
--dists-left
--help
--out-dir
--poll
--result-dir
--results-left
";
