// This is a Roxen WebServer module.
// Copyright 2002 Martin Nilsson

inherit "module";
inherit "roxenlib";
#include <module.h>

constant thread_safe = 1;
constant module_type = MODULE_LOCATION;
constant module_name = "Xenofarm: I/O module";
constant module_doc  = #"This module provides a mount point from which build
packages can be fetched by the clients. It also provides a redirect from
<tt><i>mountpoint</i>/latest</tt> to the most recent build. The time stamps are
parsed from the file names (project-YYYYMMDD-hhmmss.tar.gz) and not from file
stats. At <tt><i>mountpoint</i>/result</tt> this module also accepts HTTP PUTs
of finished results. These will be named as
res<i>&lt;timestamp&gt;</i>-<i>&lt;counter&gt;</i>.tar.gz, e g
res1028172584_4.tar.gz. The counter wraps at 10.";
constant module_unique = 0;

void create() {
  defvar( "mountpoint", "/xenofarm/",
          "Mount point", TYPE_LOCATION|VAR_INITIAL,
          "Where the module will be mounted in the site's virtual file "
          "system." );

  defvar( "distpath", "NONE", "Dist search path",
	  TYPE_DIR|VAR_INITIAL|VAR_NO_DEFAULT,
	  "The directory that contains the files to supply to the clients.");

  defvar( "resultpath", "NONE", "Result search path",
	  TYPE_DIR|VAR_INITIAL|VAR_NO_DEFAULT,
	  "The directory where uploaded results will be stored." );
}

protected string truncate(string path, int max_len)
{
  if (sizeof(path) <= max_len) return path;
  array(string) segments = path/"/";
  int res_len = sizeof(path);
  for (int i = 2; (res_len > max_len) && i < (sizeof(segments)-2); i++) {
    res_len -= sizeof(segments[i]) + 1;
    if (i == 2) {
      segments[i] = "...";
    } else {
      segments[i] = 0;
    }
  }
  return (segments - ({ 0 })) * "/";
}

string query_name()
{
  return sprintf("%s from %s",
		 truncate(query("mountpoint"), 20),
		 truncate(query("distpath"), 20));
}

string info()
{
  string descr = sprintf("<p><tt>%s</tt> mounted from <tt>%s</tt>.</p>\n",
			 Roxen.html_encode_string(query("mountpoint")),
			 Roxen.html_encode_string(query("distpath")));
  if(!sizeof(downloaded) && !sizeof(uploaded))
    return descr + "<p>No downloads or uploads so far.</p>\n";
  string table = "<table border='1' cellspacing='0' cellpadding='2'>\n"
    "<tr><th>Remote address</th><th>Downloads</th><th>Uploads</th></tr>\n";
  foreach(sort(indices(downloaded + uploaded)), string ip)
    table += sprintf("<tr><td>%s</td><td>%d</td><td>%d</td></tr>\n",
		     ip, downloaded[ip], uploaded[ip]);
  return descr + table + "</table>\n";
}

// User variables
static string mountpoint;
static string distpath;
static string resultpath;

// Counter to prevent upload name clashes
static int file_counter;

// Info about the latest source distribution
static string latest;
static int latest_timestamp;

// Statistics
static mapping(string:int) downloaded = ([]);
static mapping(string:int) uploaded = ([]);

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

// XXXX-YYYYMMDD-hhmmss.suffix -> posix time
static int dist_mtime(string f) {
#if constant(Calendar_I)
  string ymd, hms;
  catch {
    if( sscanf( reverse(f), "%*s.%s-%s-", hms, ymd)!=3 ) return 0;
    f = reverse(ymd)+"-"+reverse(hms);
    return Calendar.set_timezone("UTC")->parse("%d-%t", f)->unix_time();
  };
  return 0;
#else
  int Y,M,D,h,m,s;
  if( sscanf(f, "%*s-%4d%2d%2d-%2d%2d%2d", Y,M,D,h,m,s)!=7 )
    return 0;
  return mktime(s, m, h, D, M-1, Y-1900, 0, 0);
#endif
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

  if(putting[from] <= 0) {
    putting[from] = 0;
    done_with_put( id_arr );
  }
}

static void done_with_put( array(object) id_arr ) {
  object to;
  object from;
  object id;

  [to, from ,id] = id_arr;
  string fn = to->query_id();

  to->close();
  from->set_blocking();
  m_delete(putting, from);

  if (putting[from] && (putting[from] != 0x7fffffff)) {
    // Truncated!
    id->send_result(http_low_answer(400,
                                    "Bad Request - "
                                    "Expected more data."));
    rm(fn);
  }
  else {
    id->send_result(http_low_answer(200, "Transfer Complete."));
    mv(fn, replace(fn, "tmp", "res"));
  }
}


// API methods

Stat stat_file(string f, RequestID id) {
  if(f=="latest" || f=="result") {
    mapping|Stdio.File res = find_file(f,id);
    if(!res) return 0;
    if(objectp(res)) return res->stat();
    return res->stat;
  }

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
      ({ "latest",
	 //	 "latest-green",
	 //	 "most-successful",
	 "result" });
  if( file_stat( (path/"/")[0] + ".tar.gz" ) )
    return ({ "snapshot.tar.gz" });
  return 0;
}

mapping|Stdio.File find_file(string path, RequestID id) {

  CACHE(5);

  if(path=="latest") {
    if(latest_timestamp+5 < time()) {
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

  // FIXME
  if(path=="latest-green") {
    Roxen.http_low_answer(404, "File not found.");
    string latestg;
    return http_redirect( out_converter(mountpoint+latestg), id );
  }

  // FIXME
  if(path=="most-successful") {
    Roxen.http_low_answer(404, "File not found.");
    string msuccess;
    return http_redirect( out_converter(mountpoint+msuccess), id );
  }

  if(path=="result") {
    file_counter = (file_counter+1)%10; // No more than 10 results at the same second...
    string fn = resultpath + "/tmp" + time() + "_" + file_counter + ".tar.gz";
    Stdio.File to = Stdio.File( fn, "wct", 0775 );

    if(!to)
      return http_low_answer(403, "Open new file failed.");
    to->set_id(fn);

    chmod(fn, 0666);

    putting[id->my_fd] = id->misc->len;
    uploaded[id->remoteaddr]++;

    if(id->data && sizeof(id->data))
      got_put_data( ({ to, id->my_fd, id }), id->data );

    if(!id) return 0;
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
  downloaded[id->remoteaddr]++;

  return ([
    "file" : f,
    "type" : "application/octet-stream",
    "stat" : s,
    // Some versions of WebServer doesn't add Last-Modified on HEAD requests.
    "extra_heads" : ([ "Last-Modified" : http_date( s[3] ) ]),
  ]);

}
