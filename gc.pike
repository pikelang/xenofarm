
// Xenofarm Garbage Collect
// By Martin Nilsson
// $Id: gc.pike,v 1.8 2004/05/03 16:00:54 mani Exp $

string out_dir;
string result_dir;

int gc_poll = 60*60*2;
int dists_left = 1;
int results_left = 11;
int save_per_system = 0;

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

void rm_dir(string dir, string file) {
  if( !Stdio.recursive_rm(combine_path(dir,file)) )
    debug("Could not delete %s.\n", combine_path(dir,file));
  else
    debug("Removed directory %s\n", combine_path(dir,file));
}

void clean_res_dir(string dir, int save_builds, int save_systems) {

  array files = get_dir(dir);

  multiset|array builds = ({});
  mapping(int:multiset|array) systems = ([]);

  foreach(files, string fn) {
    int build, system;
    if( sscanf(fn, "%d_%d", build, system)!=2 ) continue;
    builds += ({ build });
    if(!systems[system])
      systems[system] = ({ build });
    else
      systems[system] += ({ build });
  }

  builds = Array.uniq(sort(builds));
  builds = builds[..sizeof(builds)-1-save_builds];
  builds = (multiset)builds;
  // These builds can be removed unless save_systems says otherwise.

  foreach(indices(systems), int system) {
    array b = systems[system];
    b = b[sizeof(b)-save_systems..];
    if(!sizeof(b))
      m_delete(systems, system);
    else
      systems[system] = (multiset)b;
  }
  // These results must not be removed to comply with save_systems.

  // Remove the results.
  foreach(files, string fn) {
    int build, system;
    if( sscanf(fn, "%d_%d", build, system)!=2 ) continue;
    if( !builds[build] ) continue;
    if( systems[system] && systems[system][build] ) continue;
    rm_dir(dir, fn);
  }

  // Save export information about non-removed results.
  foreach(values(systems), multiset b)
    builds -= b;

  // Remove export results.
  foreach(files, string fn) {
    if(has_value(fn, "_")) continue;
    if(fn == (string)(int)fn && builds[(int)fn])
      rm_dir(dir, fn);
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
    ({ "systems",   Getopt.HAS_ARG, "--save-per-system"}),
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

      case "systems":
	save_per_system = (int)opt[1];
	break;
      }
    }

  check_settings();

  while(1) {
    clean_out_dir(out_dir, dists_left);
    clean_res_dir(result_dir, results_left, save_per_system);
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
--save-per-system
";
