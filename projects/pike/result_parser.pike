
// Xenofarm Pike result parser
// By Martin Nilsson
// $Id: result_parser.pike,v 1.15 2002/10/21 23:17:02 mani Exp $

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

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/xenofarm");
string result_dir = "/pike/home/manual/pikefarm/in/";
string work_dir = "/pike/home/manual/pikefarm/in_work/";
string web_dir = "/pike/home/manual/web/pikefarm/";

string main_log_file = "xenofarmlog.txt";
string compilation_log_file = "makelog.txt";

// These warnings will not be counted as real warnings.
multiset(string) ignored_warnings = (<
  "configure: warning: found bash as /*.",
  "configure: warning: defaulting to --with-poll since the os is *.",
  "checking for irritating if-if-else-else warnings... *",
  "configure: warning: no login-related functions",
  "configure: warning: defaulting to unsigned int.",
  "configure: warning: configure script has been "
    "generated with autoconf 2.50 or later.",
  "configure: warning: cleaning the environment from autoconf 2.5x pollution",
  "configure: warning: found bash as /bin/bash.",
  " warning: failed to find the gtk gl widget.  ",
  "configure: warning: rntcc/rntcl/rnticl/rntecl detected.",
  "configure: warning: enabling dynamic modules for win32",
  "configure: warning: no gl or mesagl libraries, disabling gl support.",
  "cc: 1501-245 warning: hard ulimit has been reduced to less than "
    "rlim_infinity.  there may not be enough space to complete the "
    "compilation.",
  "configure: warning: debug malloc requires rtldebug. enabling rtldebug.",
  >);

constant removed_warnings = ({
  "configure: warning: cleaning the environment from autoconf 2.5x pollution",
  "cc: 1501-245 warning: hard ulimit has been reduced to less than "
    "rlim_infinity.  there may not be enough space to complete the "
    "compilation.",
});

void parse_build_id(string fn, mapping res) {
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) {
    debug("No %s in result package.\n", fn);
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
  else
    mv("_core.txt", "core.txt");

  // We don't consider verify passed if there was a leak.
  string log = Stdio.read_file("verifylog.txt");
  if(log && has_value(log, "==LEAK==")) {
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

void count_warnings(string fn, mapping res) {
  ::count_warnings(fn, res);

  // Highlight warnings.
  if(file_stat("makelog.txt")) {
    array lines = Stdio.read_file("makelog.txt")/"\n";
  newline:
    foreach(lines; int n; string line) {
      string lc_line=lower_case(line);
      if(!(has_value(lc_line, "warning") ||
	   has_value(lc_line, "(W)"))) {
	lines[n]=_Roxen.html_encode_string(line);
	continue;
      }
      foreach(removed_warnings, string remove)
	if(glob(remove,lc_line)) {
	  lines[n]=0;
	  continue newline;
	}
      foreach(indices(ignored_warnings), string ignore)
	if(glob(ignore,lc_line)) continue newline;
      lines[n]="<font style='background: #ff8080'>"+
	_Roxen.html_encode_string(line)+"</font>";
    }
    lines -= ({0});
    if(Stdio.write_file("makelog.html",
			 "<pre><a href='#bottom'>Bottom of file</a>\n"+
			lines*"\n"+"\n<a name='bottom'></a></pre>\n"))
      rm("makelog.txt");
  }
}
