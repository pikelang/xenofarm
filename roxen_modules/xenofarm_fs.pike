// This is a Roxen WebServer module.
// Copyright 2002 Martin Nilsson

inherit "module";

constant cvs_version = "$Id: xenofarm_fs.pike,v 1.2 2002/05/03 22:37:31 mani Exp $";
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

static string mountpoint;
static string distpath;
static string resultpath;
static int file_counter;

static string latest;
static int latest_timestamp;

void start() {
  mountpoint = query("mountpoint");
  distpath = query("distpath");
  resultpath = query("resultpath");
}

string query_location() {
  return mountpoint;
}

// XXXXXXX/snapshot.tar.gz -> XXXXXXX.tar.gz
static string in_converter(string f) {
  array tmp = f/"/";
  if(tmp[-1]!="snapshot.tar.gz") return f;
  return tmp[..sizeof(tmp)-2]*"/" + ".tar.gz";
}

// XXXXXXX.tar.gz -> XXXXXXX/snapshot.tar.gz
static string out_converter(string f) {
  if(!sscanf(f, "%s.tar.gz", f)) return f;
  return f + "/snapshot.tar.gz";
}

Stat stat_file(string f, RequestID id) {
  return file_stat( distpath + f );
}

string real_file(string f, RequestID id) {
  f = in_convert(f);
  if(stat_file(f, id))
    return distpath+f;
  return 0;
}

array(string) find_dir(string path, RequestID id) {
  if(path=="")
    return get_dir(distpath) +
      ({ "latest", "latest-green", "result" });
  if( file_stat( (path/"/")[0] + ".tar.gz" ) )
    return "snapshot.tar.gz";
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
	return Roxen.http_low_answer(404, "File not found.");

    return Roxen.http_redirect( out_converter(mountpoint+latest), id );
  }

  if(path=="latest-green") {
    Roxen.http_low_nswer(404, "File not found.");
    string latestg;
    return Roxen.http_redirect( out_converter(mountpoint+latestg), id );
  }

  if(path=="result") {
    fn += (counter++);
    Stdio.write_file( fn, data );
    return ([]);
  }

  return Stdio.File( in_converter(distpath+f) );

}
