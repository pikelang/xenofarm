//
// Garbage collector for the Pike projects
// $Id: gc.pike,v 1.3 2002/11/30 03:36:57 mani Exp $
//

string my_out_dir = "/pike/data/pikefarm/out/";
string my_result_dir = "/pike/home/manual/web/pikefarm/";

class Pike7_3 {
  inherit "../../gc.pike";

  string out_dir = my_out_dir + "7.3/";
  string result_dir = my_result_dir + "7.3/";
}

void main() {

  array projects = ({ Pike7_3() });

  while(1) {
    foreach(projects, object project) {
      project->clean_out_dir(out_dir, dists_left);
      project->clean_res_dir(result_dir, results_left);
    }
    debug("Waiting...\n");
    sleep(gc_poll);
  }
}
