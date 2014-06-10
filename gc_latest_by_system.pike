// Xenofarm Garbage Collect variant to clean results dir by keeping
// the latest results for each system.
// By Quest

inherit "gc.pike";

void clean_res_dir(string dir, int save) {

  array files = get_dir(dir);
  multiset|array systems = map(files, lambda(string in) {
				       int b;
                       int dummy;
				       sscanf(in, "%d_%d", dummy, b);
				       return b;
				     });
  systems -= ({ 0 });
  systems = Array.uniq(systems);

  foreach(systems, string system) {
    // Get list of builds from this system
    multiset|array system_builds = filter(files, lambda(string in) {
                                          if(has_value(in, "_" + system))
                                            return 1;
                                         });
    system_builds -= ({ 0 });
    system_builds = sort((array(int))system_builds);
    if (sizeof(system_builds) > save) {
      system_builds = system_builds[..sizeof(system_builds) - 1 - save];

      foreach(system_builds, string file) {
        if( !Stdio.recursive_rm(combine_path(dir,file)) )
          debug("Cuild not delete %s.\n", combine_path(dir,file));
        else
          debug("Removed directory %s\n", combine_path(dir,file));
      }
    }
  }
}
