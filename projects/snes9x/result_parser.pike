#!/usr/bin/env pike

// Xenofarm Snes9X result parser
// By Peter Bortas, derived from Martin Nilsson's Pike project parser
// $Id: result_parser.pike,v 1.1 2003/07/03 02:13:59 zino Exp $

inherit "../../result_parser.pike";

string result_dir = "/mnt/moreweb/projekt/snes9x/results/";
string work_dir = "/mnt/moreweb/projekt/snes9x/work/results/";
string web_dir = "/mnt/moreweb/projekt/snes9x/parsed-results/";

string dburl = getenv("DBURL") || Stdio.read_file("mysql.url")
  || Stdio.read_file(combine_path(getenv("HOME"),".mysql.url"));
Sql.sql xfdb = Sql.sql( dburl-"\n" );

void create() {
//   if(!this_object()->pike_version) {
//     werror("This program is not intended to be run.\n");
//     exit(1);
//   }
#define FIX(X) X += "head/";
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
  foreach(res->tasks, array task) {

//     if(task[0]=="post_build/verify") {
//       // We don't consider verify passed if there was a leak.
//       string log = Stdio.read_file("verifylog.txt");
//       if(log && has_value(log, "==LEAK==")) {
// 	task[1] = "FAIL";
// 	return;
//       }
//     }

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
