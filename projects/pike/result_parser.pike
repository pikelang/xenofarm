
// Xenofarm Pike result parser
// By Martin Nilsson
// $Id: result_parser.pike,v 1.24 2002/12/12 01:33:11 mani Exp $

inherit "../../result_parser.pike";

string result_dir = "/pike/data/pikefarm/in/";
string work_dir = "/pike/data/pikefarm/in_work/";
string web_dir = "/pike/data/pikefarm/results/pikefarm/";

void create() {
  if(!this_object()->pike_version) {
    werror("This program is not intended to be run.\n");
    exit(1);
  }
#define FIX(X) X += this_object()->pike_version + "/";
  FIX(web_dir);
  FIX(work_dir);
  FIX(result_dir);

  foreach(ignored_warnings, string w)
    if(lower_case(w)!=w)
      werror("Warning %O not lower cased.\n");
  foreach(removed_warnings, string w)
    if(lower_case(w)!=w)
      werror("Warning %O not lower cased.\n");
}

// These warnings will not be counted as real warnings.
array(string) ignored_warnings = ({
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
  "warning added -lpthread to $libs!",
  "configure: warning: gnome 1.0.x not supported",
  "makefile:*: warning: overriding commands for target `depend'",
  "makefile:*: warning: ignoring old commands for target `depend'",
});

constant removed_warnings = ({
  "configure: warning: cleaning the environment from autoconf 2.5x pollution",
  "cc: 1501-245 warning: hard ulimit has been reduced to less than "
    "rlim_infinity.  there may not be enough space to complete the "
    "compilation.",
  "cc1: warning: -fpic ignored (all code is position independent)",
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
    res->build = (int)xfdb->query("SELECT id FROM build WHERE time=%d",
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

void parse_log(string fn, mapping res)
{
  ::parse_log(fn, res);

  // We sometimes get empty _core-files.
  Stdio.Stat st = file_stat("_core.txt");
  if(st && !st->size)
    rm("_core.txt");
  else
    mv("_core.txt", "core.txt");

  if(!res->tasks) return;
  foreach(res->tasks, [string task, string status, int time, int warnings]) {

    if(task=="post_build/verify") {
      // We don't consider verify passed if there was a leak.
      string log = Stdio.read_file("verifylog.txt");
      if(log && has_value(log, "==LEAK==")) {
	res->tasks["build/verify"][0] = "FAIL";
	return;
      }
    }

  }
}

int count_warnings(string fn) {

  // Highlight warnings.
  if(file_stat("compilelog.txt")) {
    array lines = Stdio.read_file("compilelog.txt")/"\n";
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
      foreach(ignored_warnings, string ignore)
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

  return ::count_warnings(fn);
}
