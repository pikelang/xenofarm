
// Xenofarm lyskom server result parser
// By Martin Nilsson
// $Id: result_parser.pike,v 1.1 2002/08/14 09:13:22 mani Exp $

inherit "../../result_parser.pike";

// Sql.Sql xfdb = Sql.Sql("mysql://localhost/xenofarm");
// string result_dir = "/home/nilsson/xenofarm/in/";
// string work_dir = "/tmp/xtmp/";
// string web_dir = "/home/nilsson/html/xenofarm_results/";

string build_id_file = "exportstamp.txt";
string main_log_file = "xenofarmlog.txt";
string compilation_log_file = "makelog.txt";

void parse_build_id(string fn, mapping res) {
  string file = Stdio.read_file(fn);
  if(!file) {
    file = Stdio.read_file("export.stamp");
    res->status = "failed";
  }
  if(!file || !sizeof(file)) {
    debug("No %s nor export.stamp in result pkg.\n", fn);
    return;
  }

  int build_time;

  if( sscanf(file, "buildtime: %d", build_time)!=1 )
    return;

  res->build = build_time;
  return;

  // Look up build id
  array err = catch {
    res->build = (int)xfdb->query("SELECT id FROM build WHERE "
				  "project='lyskom-server' AND time=%d",
				  build_time)[0]->id;
  };

  if(err) {
    debug("Build %d not found.\n", build_time);
    if(verbose)
      write(describe_backtrace(err));
    else
      werror(describe_backtrace(err));
  }
}

void parse_log(string fn, mapping res) {
  ::parse_log(fn, res);

  /*
  Stdio.Stat st = file_stat("_core.txt");
  if(st && !st->size)
    rm("_core.txt");

  if(res->status=="built") {
    res->status="exported";
    return;
  }

  if(res->time_export) {
    res->status = "verified";
    return;
  }

  if(res->time_verify)
    res->status = "built";
  */
}
