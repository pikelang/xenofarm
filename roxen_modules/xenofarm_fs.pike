// This is a Roxen WebServer module.
// Copyright 2002 Martin Nilsson

inherit "module";

constant cvs_version = "$Id: xenofarm_fs.pike,v 1.1 2002/05/03 15:46:57 mani Exp $";
constant thread_safe = 1;
constant module_type = MODULE_LOCATION;
constant module_name = "Xenofarm I/O module";
constant module_doc  = "...";
constant module_unique = 1;

void create() {
  defvar( "mountpoint", "/xenofarm/",
          "Mount point", TYPE_LOCATION|VAR_INITIAL,
          "Where the module will be mounted in the site's virtual file "
          "system." );

  defvar( "distpath", "NONE", "Dist search path",
	  TYPE_DIR|VAR_INITIAL,
	  "The directory that contains the export files.");

  defvar( "resultpath", "NONE", "Result search path",
	  TYPE_DIR|VAR_INITIAL,
	  "The directory where results will be stored." );
}

private string mountpoint;
private string distpath;
private string resultpath;
private int file_counter;

private string latest;
private int latest_timestamp;

void start() {
  mountpoint = query("mountpoint");
  distpath = query("distpath");
  resultpath = query("resultpath");
}

string query_location() {
  return mountpoint;
}

Stat stat_file(string f, RequestID id) {
  return file_stat( distpath + f );
}

string real_file(string f, RequestID id) {
  if(stat_file(f, id))
    return distpath+f;
  return 0;
}

array(string) find_dir(string path, RequestID id) {
  if(path=="")
    return get_dir(distpath) +
      ({ "latest", "latest-green", "result" });
  return 0;
}

mapping|Stdio.File find_file(string path, RequestID id) {

  if(path=="latest") {
    if(latest_timestamp+60*5 < time()) {
      array files = sort(get_dir(mountpoint));
      if(files) {
	latest = files[-1];
	latest_timestamp = time();
      }
      else
	return 404;

    return Roxen.http_redirect( mountpoint+latest, id );
  }

  if(path=="latest-green") {
    string latestg;
    return Roxen.http_redirect( mountpoint+latestg, id );
  }

  if(path=="result") {
    fn += (counter++);
    Stdio.write_file( fn, data );
    return ([]);
  }

  return Stdio.File( distpath+f );

}
