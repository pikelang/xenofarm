// This is a Roxen WebServer module.
// Copyright 2002 Martin Nilsson

inherit "module";
inherit "roxenlib";
#include <module.h>

constant cvs_version = "$Id: xenofarm_fs.pike,v 1.7 2002/05/15 17:27:18 mani Exp $";
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

// XXXX-YYYYMMDD-hhmmss -> posix time
static int dist_mtime(string f) {
  int Y,M,D,h,m,s;
  if( sscanf(f, "%*s-%4d%2d%2d-%2d%2d%2d", Y,M,D,h,m,s)!=7 )
    return 0;
  return mktime(s, m, h, D, M-1, Y-1900, 0, 0);
}


// PUT stuff

static mapping(object:int) putting = ([]);

static void got_put_data( array(object) id_arr, string data ) {
  object to;
  object from;
  object id;

  [to, from ,id] = id_arr;

  // Truncate last block
  data = data[..putting[from]];

  int bytes = to->write(data);

  if(bytes < sizeof(data)) {
    // Out of disk.
    to->close();
    from->set_blocking();
    m_delete(putting, from);
    id->send_result(http_low_answer(413, "Disk is full."));
    return;
  }

  if(putting[from] != 0x7fffffff)
    putting[from] -= bytes;

  if(putting[from] < 0) {
    putting[from] = 0;
    done_with_put( id_arr );
  }
}

static void done_with_put( array(object) id_arr ) {
  object to;
  object from;
  object id;

  [to, from ,id] = id_arr;

  to->close();
  from->set_blocking();
  m_delete(putting, from);

  if (putting[from] && (putting[from] != 0x7fffffff)) {
    // Truncated!
    id->send_result(http_low_answer(400,
                                    "Bad Request - "
                                    "Expected more data."));
  }
  else
    id->send_result(http_low_answer(200, "Transfer Complete."));
}


// API methods

Stat stat_file(string f, RequestID id) {
  Stat s = file_stat( distpath + f );
  if(!s) return 0;
  int mtime = dist_mtime(f);
  if(mtime)
    s[3] = mtime;
  return s;
}

string real_file(string f, RequestID id) {
  f = in_converter(f);
  if(stat_file(f, id))
    return distpath+f;
  return 0;
}

array(string) find_dir(string path, RequestID id) {
  if(path=="")
    return get_dir(distpath) +
      ({ "latest", "latest-green", "result" });
  if( file_stat( (path/"/")[0] + ".tar.gz" ) )
    return ({ "snapshot.tar.gz" });
  return 0;
}

mapping|Stdio.File find_file(string path, RequestID id) {

  if(path=="latest") {
    if(latest_timestamp+60*5 < time()) {
      array files = sort(get_dir(distpath));
      if(sizeof(files)) {
	latest = files[-1];
	latest_timestamp = time();
      }
      else
	return http_low_answer(404, "File not found.");
    }

    return http_redirect( out_converter(mountpoint+latest), id );
  }

  if(path=="latest-green") {
    Roxen.http_low_answer(404, "File not found.");
    string latestg;
    return http_redirect( out_converter(mountpoint+latestg), id );
  }

  if(path=="result") {
    string fn = resultpath + "/res" + time() + "_" + (file_counter++) + ".tar.gz";
    Stdio.File to = Stdio.File( fn, "wct" );

    if(!to)
      return http_low_answer(403, "Open new file failed.");

    chmod(fn, 0666);

    if(id->data && sizeof(id->data)) {
      to->write(id->data);
      to->close();
      return http_string_answer("Thanks!");
    }

    putting[id->fd] = id->misc->len;
    if(id->clientprot == "HTTP/1.1")
      id->my_fd->write("HTTP/1.1 100 Continue\r\n");

    id->my_fd->set_id( ({ to, id->my_fd, id }) );
    id->my_fd->set_nonblocking(got_put_data, 0, done_with_put);
    return http_pipe_in_progress();
  }

  Stdio.File f = Stdio.File( distpath+in_converter(path) );

  if(!f) return Stdio.File( distpath+path );

  Stat s = f->stat();
  s[3] = dist_mtime(path);

  return ([
    "file" : f,
    "type" : "application/octet-stream",
    "stat" : s,
  ]);

}
