//
// Garbage collector for the Pike projects
// $Id: gc.pike,v 1.8 2004/04/26 01:33:42 mani Exp $
//

constant my_out_dir = "/pike/data/pikefarm/out/";
constant my_result_dir = "/pike/data/pikefarm/results/";
constant gc_poll = 60*60*2;

void debug(string msg, mixed ... args) {
  write("[" + Calendar.ISO.now()->format_tod() + "] "+msg, @args);
}

class PikeVersion {
  inherit "../../gc.pike";
  string version;

  void create(string v) {
    version = v;
    out_dir = my_out_dir + v + "/";
    result_dir = my_result_dir + v + "/";
  }

  void clean_out_dir() { ::clean_out_dir(out_dir, dists_left); }
  void clean_res_dir() { ::clean_res_dir(result_dir, results_left); }

  void info() {
    debug("Cleaning Pike %s.\n", version);
  }
}

void main() {

  array projects = ({ PikeVersion("7.4"),
		      PikeVersion("7.5"),
		      PikeVersion("7.6"),
		      PikeVersion("7.7") });

  while(1) {
    foreach(projects, object project) {
      project->clean_out_dir();
      project->clean_res_dir();
    }
    debug("Waiting...\n");
    sleep(gc_poll);
  }
}
