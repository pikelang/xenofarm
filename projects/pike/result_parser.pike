
// Xenofarm Pike result parser
// By Martin Nilsson
// $Id: result_parser.pike,v 1.10 2002/08/14 18:47:52 mani Exp $

inherit "../../result_parser.pike";

constant db_def1 = "CREATE TABLE system (id INT UNSIGNED AUTO INCREMENT NOT NULL PRIMARY KEY, "
                   "name VARCHAR(255) NOT NULL, "
                   "platform VARCHAR(255) NOT NULL)";

constant db_def2 = "CREATE TABLE result (build INT UNSIGNED NOT NULL, " // FK build.id
                   "system INT UNSIGNED NOT NULL, " // FK system.id
                   "status ENUM('failed','built','verified','exported') NOT NULL, "
                   "warnings INT UNSIGNED NOT NULL, "
                   "time_spent INT UNSIGNED NOT NULL, "
                   "PRIMARY KEY (build, system) )";

Sql.Sql xfdb = Sql.Sql("mysql://localhost/xenofarm");
string result_dir = "/home/nilsson/xenofarm/in/";
string work_dir = "/tmp/xtmp/";
string web_dir = "/home/nilsson/html/xenofarm_results/";

string build_id_file = "exportstamp.txt";
string main_log_file = "xenofarmlog.txt";
string compilation_log_file = "makelog.txt";

multiset(string) ignored_warnings = (<
  "configure: warning: found bash as /*.",
  "configure: warning: defaulting to --with-poll since the os is *.",
  "checking for irritating if-if-else-else warnings... * (good)",
  "configure: warning: no login-related functions",
  "configure: warning: defaulting to unsigned int.",
  >);

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

  if( sscanf(file, "%*stime:%d", build_time)!=2 )
    return;

  array err = catch {
    res->build = (int)xfdb->query("SELECT id FROM build WHERE "
				  "project='pike7.3' AND time=%d",
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

  // We sometimes get empty _core-files.
  Stdio.Stat st = file_stat("_core.txt");
  if(st && !st->size)
    rm("_core.txt");

  // We don't consider verify passed if there was a leak.
  string log = Stdio.read_file("verifylog.txt");
  if(log && has_value(log, "=LEAK=")) {
    res->status="built";
    return;
  }

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
}
