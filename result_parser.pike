#! /usr/bin/env pike

// Xenofarm result parser
// By Martin Nilsson
// $Id: result_parser.pike,v 1.44 2010/07/11 13:40:06 zino Exp $

Sql.Sql xfdb;
int result_poll = 60;
string project;
string result_dir;
string work_dir;
string web_dir;

string build_id_file = "buildid.txt";
string machine_id_file = "machineid.txt";
string main_log_file = "mainlog.txt";
string compilation_step_name = "build/compile";
string compilation_log_file = "compilelog.txt";
string post_script;

int(0..1) verbose;
int(0..1) dry_run;
int(0..1) keep_going = 1;

multiset(string) processed_results = (<>);
array(string) ignored_warnings = ({});

class Stack {
  inherit ADT.Stack;
#if _MINOR_<3
  int _sizeof() { return ptr; }
  array _values() { return values(arr[..ptr-1]); }
#endif
}

//
// Helper functions
//

void debug(string msg, mixed ... args) {
  if(verbose)
    write("[" + Calendar.ISO.now()->format_tod() + "] "+msg, @args);
}

array persistent_query( string q, mixed ... args ) {
  int(0..) try;
  mixed err;
  array res;
  do {
    try++;
    err = catch {
      res = xfdb->query(q, @args);
    };
    if(err) {
      switch(try) {
      case 1:
	write("Database query %s failed. Continue to try...\n",
	      sprintf(q, @Array.map(args, lambda (mixed x) {
					    if (intp(x))
					      return x;
					    else if (stringp(x))
					      return "'" + xfdb->quote(x) + "'";
					    else
					      return "'" + xfdb->quote(sprintf("%O", x)) + "'";
					  }) ));
	if(arrayp(err) && sizeof(err) && stringp(err[0]))
	  debug("(%s)\n", err[0..sizeof(err)-2] * ":");
	break;
      case 2..5:
	sleep(1);
	break;
      default:
	sleep(60);
	if(!try%10) debug("Continue to try... (try %d)\n", try);
      }
    }
  } while(err);
  return res;
}


//
// "API" functions
//

//! Reads the contents of the build id file @[fn] and adds the number
//! on the first line of the file to the @[res] mapping under the key
//! "build". The value will be casted to an int.
void parse_build_id(string fn, mapping res) {
  //TODO: pelix had a local hack to limit this to 65k
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) return;
  file = String.trim_all_whites( (file/"\n")[0] );
  if(!file) return;
  res->build = (int)file;
}

//! Reads the contents of the machine id file @[fn] and adds the key-
//! value pairs in it to the @[res] mapping. If several pairs with the same
//! key is defined in the file, the last one is added. Previous values
//! in the @[res] mapping (eg. build) will be overwritten if their keys are
//! present in the machine id file.
//!
//! If the @[res] mapping contains the keys sysname, release, machine and
//! not the key platform, after importing all keys from the machine id file,
//! a key platform will be added containing the expected output from
//! "uname -s -r -m" concatenated with the test name, unless the test name
//! is "default".
void parse_machine_id(string fn, mapping res)
{
  object(Stdio.File) f = Stdio.File();
  if (!f->open(fn, "r")) return;

  foreach(f->line_iterator(1);;string pair) {
    string key = 0;
    string value = 0;
    sscanf(pair, "%s: %s", key, value);
    if(key && value)
      res[key] = String.trim_all_whites(value);
  }
  f->close();

  if(res->sysname=="AIX" && res->version && res->release)
    res->release = res->version + "." + res->release;

  if(res->sysname && res->release && res->machine && !res->platform) {
    res->platform = res->sysname + " " + res->release + " " + res->machine;
    if(res->testname && res->testname!="default")
      res->platform += " " + res->testname;
  }
}

//! Reads the contents of the main log at @[fn] and adds all the found
//! tasks in the array tasks in @[res]. The array has the following
//! layout;
//!
//! @array
//!   @elem string 0
//!     The name of the task. The task name will be composed as a
//!     string, e.g. if a task configure is performed inside the task
//!     build it will be represented as @tt{"build/configure"@}.
//!   @elem string 0
//!     Contains the status of the task. One of @tt{"FAIL"@},
//!     @tt{"WARN"@} or @tt{"PASS"@}.
//!   @elem int 1
//!     The time the task took, in seconds.
//!   @elem int 2
//!     The number of warnings generated.
//! @endarray
//!
//! @tt{"status"@} in @[res] will be set to the overall status of the
//! build, one of @tt{"FAIL"@}, @tt{"WARN"@} or @tt{"PASS"@}. If the
//! task @tt{"build"@} fails the status will be @tt{"FAIL"@}. If there
//! is any warnings or failures in any of the build tasks the status
//! will be @tt{"WARN"@}. Otherwise it will be @tt{"PASS"@}.
//!
//! @tt{"total_time"@} in @[res] will be set to the time it took to
//! complete all tasks, calculated as the sum of the time it took for
//! all the top level tasks to complete.
void parse_log(string fn, mapping res)
{
  res->status = "FAIL";
  res->tasks=({});

  object(Stdio.File) f = Stdio.File();

  if (!f->open(fn, "r")) return;

  multiset done_tasks = (<>);

  Stack begin = Stack();
  Stack tasks = Stack();

  int push_next;
  string pending_pop;
  foreach(f->line_iterator(1);int pos; string line) {
    if (!pos) {
      if (line != "FORMAT 2") {
	debug("Log format not \"FORMAT 2\" (%O).\n", line);
	return;
      }
      continue;
    } if (push_next) {
      begin->push(line);
      push_next = 0;
      continue;
    } if (pending_pop) {
      int warnings;
      sscanf(pending_pop, "%s %d", pending_pop, warnings);

      string begun = begin->pop();
      int time;
      if(catch(time = Calendar.ISO.dwim_time(line)->unix_time()
	       - Calendar.ISO.dwim_time(begun)->unix_time())
      || time < 0)
        {
	  debug("Error parsing time (%O %O).\n", begun, line);
	  time = 0;
        }

      string task = values(tasks)*"/";
      tasks->pop();

      if(done_tasks[task]) {
	debug("Task %O present twice.\n", task);
	pending_pop = 0;
	continue;
      }

      done_tasks[ task ] = 1;
      res->tasks += ({ ({ task, pending_pop, time, warnings }) });
      pending_pop = 0;
      continue;
    } else {
      if(line=="END") break;

      if(has_prefix(line, "BEGIN")) {
        string task;
        sscanf(line, "BEGIN %s", task);
        if(!task || !sizeof(task)) {
	  debug("Empty/missing task name in main log.\n");
	  return;
        }
        if(has_value(task, "/")) {
	  debug("Task contains forbidden character '/'.\n");
	  return;
        }
        tasks->push(task);
	push_next = 1;
        continue;
      }

      if(line=="PASS" || line=="FAIL" || has_prefix(line, "WARN")) {
	pending_pop = line;
	continue;
      }
      debug("Error in main log: %O.\n", line);
      break;
    }
  }
  f->close();

  while(sizeof(tasks)) {
    string task = values(tasks)*"/";
    tasks->pop();
    if(done_tasks[task]) {
      debug("Task %O present twice.\n", task);
      continue;
    }
    done_tasks[ task ] = 1;
    res->tasks += ({ ({ task, "FAIL", 0, 0 }) });
  }

  int total_time, badness;
  foreach(res->tasks, [string task, string status, int time, int warnings])
  {
    if(!has_value(task, "/"))
      total_time += time;
    if(status=="WARN" || status=="FAIL")
      badness = 1;
  }
  res->total_time = total_time;
  foreach(res->tasks, [string task, string status, int time, int warnings])
    if(task=="build" && status!="FAIL")
      res->status = badness ? "WARN" : "PASS";
}

void count_compilation_warnings(mapping result)
{
  foreach(result->tasks, array x) {
    if(x[0]==compilation_step_name)
      x[3] = count_warnings(compilation_log_file);
  }
}

//! Reads the file @[fn] and counts how many warnings it contains. A
//! warning is a line that contains the string "warning" or "(w)" (in
//! any case) and does not match any of the globs listed in the array
//! ignored_warnings.
int count_warnings(string fn)
{
  object(Stdio.File) f = Stdio.File();

  if (!f->open(fn, "r")) return 0;

  int warnings;

 newline:
  foreach(f->line_iterator();;string line) {
    line = lower_case(line);
    if( has_value(line, "warning")||has_value(line, "(w)") ) {
      foreach(ignored_warnings, string ignore)
        if(glob(ignore,line)) continue newline;
        warnings++;
    }
  }
  f->close();
  return warnings;
}

//! Calculates the sorting order of a new task.
class TaskOrderGenie {

  static mapping state = ([]);

  //! Every already done @[task] is fed into this method to update the
  //! genie state.
  void done(array(string)|string task) {
    if(stringp(task)) task=task/"/";
    mapping state = state;
    foreach(task, string part) {
      if(!state[part])
	state[part] = ([]);
      state = state[part];
    }
  }

  //! Gives the correct(?) sorting order of a new task in context of
  //! the already completed tasks. This method might renumber some
  //! tasks in the task table in order to sqeeze in a task between two
  //! tasks.
  int(1..) get_order(array(string) task, int(0..) parent) {
    mapping state = state;
    foreach(task[..sizeof(task)-2], string part) {
      if(!state[part]) {
	// It could be that the state is out of sync with reality, but
	// in the current code we also get here when we are traversing
	// a path, eg. when "build/compile" is added (and the state is
	// empty) we will get state["build"] which is 0.
	state = ([]);
	continue;
      }

      state = state[part];
    }
    if(state[task[-1]])
      error("Task is already stored.\n%O\n%O\n", state, task);

    array res = xfdb->query("SELECT name,sort_order FROM task\n"
			    "WHERE project = %s AND parent=%d",
			    project, parent);

    if(!sizeof(res))
      return 1;

    if(sizeof(res)==sizeof(state))
      return max( @(array(int))res->sort_order )+1;

    res = filter(res, lambda(mapping in) { return state[in->name]; });
    int order = max( 0, @(array(int))res->sort_order );
    xfdb->query("UPDATE task SET sort_order=sort_order+1\n"
		"WHERE project = %s AND parent=%d AND sort_order>%d",
		project, parent, order);
    return order+1;
  }
}

//! Returns the id of the task @[tasks], which may be either a string
//! with the "path" to the task with slashes as delimiters, eg. 
//! @tt{build/compile/stage1@}, or an array with the path, eg. @tt{({
//! "build", "compile", "stage1" })@}. If the task is not already in
//! the task table in the database it will be created.
int get_task_id(array(string)|string tasks, TaskOrderGenie gen) {
  if(stringp(tasks)) tasks /= "/";

  int parent;
  if(sizeof(tasks)>1)
    parent = get_task_id( tasks[..sizeof(tasks)-2], gen );
  string task = tasks[-1];

  array res = xfdb->query("SELECT id FROM task\n"
			  "WHERE project = %s AND name=%s AND parent=%d",
			  project, task, parent);

  if(sizeof(res)) return (int)res[0]->id;

  xfdb->query("INSERT INTO task\n"
	      "SET sort_order = %d, project = %s, parent = %d, name = %s",
	      gen->get_order(tasks, parent), project, parent, task);

  return (int)xfdb->query("SELECT LAST_INSERT_ID() AS id")[0]->id;
}

// res->nodename must have a value.
// res->tasks must have a value (at least an empty array).
// res->tesname must have a value.
void store_result(mapping res) {
  if(!res->nodename)
    return;
  string testname = res->testname;
  if(testname=="default") testname="";

  array qres = persistent_query("SELECT id FROM system WHERE name=%s && "
				"sysname=%s && release=%s && version=%s "
				"&& machine=%s && testname=%s",
				res->nodename, res->sysname||"",
				res->release||"", res->version||"",
				res->machine||"", testname);

  if(sizeof(qres))
    res->system = (int)qres[0]->id;
  else {
    xfdb->query("INSERT INTO system (name, sysname, release, version, "
		"machine, testname) VALUES (%s,%s,%s,%s,%s,%s)",
		res->nodename, res->sysname||"", res->release||"",
		res->version||"", res->machine||"", testname);
    res->system = (int)xfdb->query("SELECT LAST_INSERT_ID() AS id")[0]->id;
  }

  if(!res->tasks) return;
  TaskOrderGenie g = TaskOrderGenie();
  foreach(res->tasks, [string task, string status, int time, int warnings]) {
    int task_id = get_task_id(task, g);
    xfdb->query("REPLACE INTO task_result "
		"(build, system, task, status, warnings, time_spent) "
		"VALUES (%d, %d, %d, %s, %d, %d)",
		res->build, res->system, task_id,
		status, warnings, time );
    g->done(task);
  }
}

mapping low_process_package() {
  mapping result = ([]);

  parse_build_id(build_id_file, result);
  if(!result->build) {
    write("Failed to parse build id.\n");
    return result;
  }

  parse_machine_id(machine_id_file, result);
  if(!result->nodename || !result->platform) {
    write("Failed to parse machine id.\n");
    return result;
  }
  debug("Build: %O Host: %O Platform: %O\n",
	result->build, result->nodename, result->platform);

  if(!result->status) {
    parse_log(main_log_file, result);
    if(!result->tasks)
      write("No tasks found in result log.\n");
    else
      count_compilation_warnings(result);
  }

  if(!dry_run)
    store_result(result);
  return result;
}


//
// Main functions
//

void process_package(string fn) {

  // Clear working dir
  if(sizeof(get_dir("."))) {
    Process.system("rm *");
    if(sizeof(get_dir("."))) {
      write("Working dir not empty\n");
      return;
    }
  }

  Stdio.File f=Stdio.File("tmp", "wtc");
  if(Process.create_process( ({ "gunzip", "-c", fn }),
			     ([ "stdout" : f ]) )->wait()) {
    write("Unable to decompress %O to %O.\n", fn, getcwd());
    processed_results[fn]=1;
    return;
  }
  f->close();

  Stdio.File fo = Stdio.File();
  object pipe = fo->pipe(Stdio.PROP_IPC);
  if(!pipe) return;
  Process.create_process( ({ "tar", "tf", "tmp" }), ([ "stdout":pipe ]) );
  pipe->close();
  string content = fo->read();
  fo->close();
  if(!content) return;

  if(has_value(content, "/")) {
    write("Refusing to process %O since %s contains a slash.\n", fn,
	  String.implode_nicely(filter(content/"\n", has_value, "/")) );
    processed_results[fn]=1;
    return;
  }

  Process.create_process( ({ "tar", "xf", "tmp" }), ([]) )->wait();
  if(!sizeof(get_dir("."))) {
    write("Unable to unpack %O to %O\n", fn, getcwd());
    processed_results[fn]=1;
    return;
  }

  foreach(get_dir("."), string pkgfile) {
    chmod(pkgfile, file_stat(pkgfile)[0] | 0444);
  }

  mapping result = low_process_package();
  if(dry_run) {
    processed_results[fn]=1;
    werror("%O\n", result);
    return;
  }

  rm("tmp");

  if(result->build && result->system) {
    string dest = web_dir + result->build+"_"+result->system;

    if(Stdio.is_dir(dest)) {
      debug("Result dir %O already exists.\n", dest);
      if(!Stdio.recursive_rm(dest))
	write("Unable to remove previous result directory.\n");
    }
    Stdio.mkdirhier(dest);

    int fail;
    foreach(get_dir("."), string f) {
      if( !.io.mv(f, dest+"/"+f) ) {
	write("Failed to move %O to %O: %s\n", f, dest+"/"+f,
	      strerror(errno()));
	fail = 1;
      }
    }
    if(fail)
      write("Unable to move file(s) to %O. Keeping %O.\n", dest, fn);

    if(!fail && !rm(fn) )
      write("Unable to remove %O\n", fn);
    else
      processed_results[fn]=1;
  }
  else
    processed_results[fn]=1;
}

void check_settings(void|int(0..1) no_result_dir) {
  if(!xfdb && !dry_run) {
    write("No database found.\n");
    exit(1);
  }

  if(!work_dir) {
    write("No work dir found.\n");
    exit(1);
  }
  if(work_dir[-1]!='/')
    work_dir += "/";
  if(!file_stat(work_dir) || !file_stat(work_dir)->isdir) {
    write("Working directory %s does not exist.\n", work_dir);
    exit(1);
  }
  cd(work_dir);
  // FIXME: Check write privileges.
  if(sizeof(get_dir("."))) {
    // FIXME: Empty dir ourselves?
    write("Working dir %O is not empty.\n", work_dir);
    exit(1);
  }

  if(!dry_run) {
    if(!web_dir) {
      write("No web dir found.\n");
      exit(1);
    }
    if(web_dir[-1]!='/')
      web_dir += "/";
    if(!file_stat(web_dir)) {
      write("%s does not exist.\n", web_dir);
      exit(1);
    }
    if(!file_stat(web_dir)->isdir) {
      write("%s is no directory.\n", web_dir);
      exit(1);
    }
    // FIXME: Check web dir write privileges.
  }

  if(!no_result_dir) {
    if(!result_dir) {
      write("No result dir found.\n");
      exit(1);
    }
    if(result_dir[-1]!='/')
      result_dir += "/";
    if(!file_stat(result_dir) || !file_stat(result_dir)->isdir) {
      write("Result directory %s does not exist.\n", result_dir);
      exit(1);
    }
  }

  if(verbose) {
    if(xfdb) write("Database   : %s\n", xfdb->host_info());
    write("Work dir   : %s\n", work_dir);
    if(web_dir) write("Web dir    : %s\n", web_dir);
    if(result_dir) write("Result dir : %s\n", result_dir);
    write("\n");
  }
}

void got_termination_request(int sig)
{
  keep_going = 0;
  debug("Initiating a clean shutdown.  This can take some time...\n");
}

int main(int num, array(string) args) {
  int (0..1) once_only = 0;
  write(prog_id);

  foreach(Getopt.find_all_options(args, ({
    ({ "db",        Getopt.HAS_ARG, "--db"           }),
    ({ "dry",       Getopt.NO_ARG,  "--dry-run"      }),
    ({ "help",      Getopt.NO_ARG,  "--help"         }),
    ({ "once",      Getopt.NO_ARG,  "--once"         }),
    ({ "poll",      Getopt.HAS_ARG, "--poll"         }),
    ({ "resultdir", Getopt.HAS_ARG, "--result-dir"   }),
    ({ "verbose",   Getopt.NO_ARG,  "--verbose"      }),
    ({ "webdir",    Getopt.HAS_ARG, "--web-dir"      }),
    ({ "workdir",   Getopt.HAS_ARG, "--work-dir"     }),
  }) ),array opt)
    {
      switch(opt[0])
      {
      case "db":
	xfdb = Sql.Sql( opt[1] );
	break;

      case "dry":
	dry_run = 1;
	verbose = 1;
	break;

      case "help":
	write(prog_doc);
	return 0;

      case "once":
	once_only = 1;

      case "poll":
	result_poll = (int)opt[1];
	break;

      case "resultdir":
	result_dir = opt[1];
	break;

      case "verbose":
	verbose = 1;
	break;

      case "webdir":
	web_dir = opt[1];
	break;

      case "workdir":
	work_dir = opt[1];
	break;
      }
    }

  args -= ({ 0 });
  if(sizeof(args)>1) {
    check_settings(1);
    foreach(args[1..], string fn) {
      debug("Begin processing result %O\n", fn);
      process_package(fn);
    }
    return 0;
  }

  check_settings();

  signal(signum("TERM"), got_termination_request);
  signal(signum("INT"), got_termination_request);

  while(keep_going) {
    int(0..1) got_any;
    foreach(sort(filter(get_dir(result_dir), has_prefix, "res")), string fn) {
      fn = result_dir + fn;
      if(processed_results[fn]) continue;
      debug("Found new result %O\n", fn);
      process_package(fn);
      got_any = 1;
      if (once_only || !keep_going)
	break;
    }

    if (post_script && got_any && Process.system(post_script)) {
      werror("Postscript %O failed\n", post_script);
    }

    if (once_only)
	return 0;

    sleep(result_poll, 1);
    sleep(0);
  }

}

constant prog_id = "Xenofarm generic result parser\n"
"$Id: result_parser.pike,v 1.44 2010/07/11 13:40:06 zino Exp $\n";
constant prog_doc = #"
result_parser.pike <arguments> [<result files>]
--db         The database URL, e.g. mysql://localhost/xenofarm.
--dry-run    Do not store any results or alter any files outside
             of the working directory.
--help       Displays this text.
--once       Run just once.
--poll       How often the result directory is checked for new
             result files.
--result-dir Where incoming result files are read from.
--verbose    Send messages about everything that happens to stdout.
--web-dir    Where the contents of the result files should be
             copied to.
--work-dir   Where temporary files should be put.
";
