
// Xenofarm Garbage Collect
// By Martin Nilsson
// $Id: gc.pike,v 1.1 2002/08/05 01:04:02 mani Exp $

string out_dir = "/home/nilsson/xenofarm/out/";
string result_dir = "/home/nilsson/html/xenofarm_results/";

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
      write("Could not delete %s.\n", combine_path(dir,file));
    else
      werror("Removed file %s\n", combine_path(dir,file));
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
	werror("Cuild not delete %s.\n", combine_path(dir,file));
      else
	werror("Removed directory %s\n", combine_path(dir,file));
    }
  }

}


int main() {

  while(1) {
    clean_out_dir(out_dir, 1);
    clean_res_dir(result_dir, 10);
    sleep(60*60*2);
  }

}
