
// Xenofarm result parser
// By Martin Nilsson
// $Id: result_parser.pike,v 1.14 2002/08/14 16:56:40 mani Exp $

constant db_def1 = "CREATE TABLE system (id INT UNSIGNED AUTO INCREMENT NOT NULL PRIMARY KEY, "
                   "name VARCHAR(255) NOT NULL, "
                   "platform VARCHAR(255) NOT NULL)";

constant db_def2 = "CREATE TABLE result (build INT UNSIGNED NOT NULL, " // FK build.id
                   "system INT UNSIGNED NOT NULL, " // FK system.id
                   "status ENUM('failed','built') NOT NULL, "
                   "warnings INT UNSIGNED NOT NULL, "
                   "time_spent INT UNSIGNED NOT NULL, "
                   "PRIMARY KEY (build, system) )";

Sql.Sql xfdb;
int result_poll = 60;
string result_dir;
string work_dir;
string web_dir;

string build_id_file = "buildid.txt";
string machine_id_file = "machineid.txt";
string main_log_file = "mainlog.txt";
string compilation_log_file = "compilelog.txt";

int(0..1) verbose;
int(0..1) dry_run;

multiset(string) processed_results = (<>);
multiset(string) ignored_warnings = (<>);

void debug(string msg, mixed ... args) {
  if(verbose)
    write("[" + Calendar.ISO.now()->format_tod() + "] "+msg, @args);
}

void parse_build_id(string fn, mapping res) {
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) return;
  file = String.trim_all_whites( (file/"\n")[0] );
  if(!file) return;
  res->build = (int)file;
}

void parse_machine_id(string fn, mapping res) {
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) return;
  array parts = file/"\n";
  if(sizeof(parts)<2);
  res->platform = String.trim_all_whites(parts[0]);
  res->host = String.trim_all_whites(parts[1]);
}

void parse_log(string fn, mapping res) {
  res->status = "failed";
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) return;
  array parts = (file/"\n")/2;

  string last_item;
  int last_time;
  foreach(parts, array thing) {
    if(sizeof(thing)!=2) return;
    int new = Calendar.ISO.dwim_time(thing[1])->unix_time();
    if(last_item)
      res["time_"+last_item] = new-last_time;
    last_time = new;
    if(thing[0]=="Xenofarm OK")
      res->status = "built";
    sscanf(thing[0], "Begin %s", last_item);
  }
  int total;
  foreach(res; string ind; mixed val) {
    if(has_prefix(ind, "time_"))
      total += val;
  }
  res->total_time = total;
}

void count_warnings(string fn, mapping res) {
  Stdio.FILE file;
  catch {
    file = Stdio.FILE(fn);
  };
  if(!file) return;

  int warnings;
 newline:
  foreach(file->line_iterator(1);; string line) {
    line = lower_case(line);
    if( has_value(line, "warning") ) {
      foreach(indices(ignored_warnings), string ignore)
	if(glob(ignore,line)) continue newline;
	warnings++;
    }
  }
  res->warnings = warnings;
}

void store_result(mapping res) {
  if(!res->host || !res->platform)
    return;

  array qres = xfdb->query("SELECT id FROM system WHERE name=%s && platform=%s",
			   res->host, res->platform);

  if(sizeof(qres))
    res->system = (int)qres[0]->id;
  else {
    xfdb->query("INSERT INTO system (name, platform) VALUES (%s,%s)",
		res->host, res->platform);
    res->system = (int)xfdb->query("SELECT LAST_INSERT_ID() AS id")[0]->id;
  }

  xfdb->query("REPLACE INTO result (build,system,status,warnings,time_spent) "
	      "values (%d,%d,%s,%d,%d)", res->build, res->system,
	      res->status, res->warnings, res->total_time);
}

mapping low_process_package() {
  mapping result = ([]);

  parse_build_id(build_id_file, result);
  if(!result->build) {
    write("Failed to parse build id.\n");
    return result;
  }

  parse_machine_id(machine_id_file, result);
  if(!result->host || !result->platform) {
    write("Failed to parse machine id.\n");
    return result;
  }
  debug("Build: %O Host: %O Platform: %O\n", result->build, result->host, result->platform);

  if(!result->status) {
    parse_log(main_log_file, result);
    count_warnings(compilation_log_file, result);
  }

  if(!dry_run)
    store_result(result);
  return result;
}

void process_package(string fn) {

  // Clear working dir
  if(sizeof(get_dir("."))) {
    Process.system("rm *");
    if(sizeof(get_dir("."))) {
      write("Working dir not empty\n");
      return;
    }
  }

  Process.system("tar -xzf "+fn);
  if(!sizeof(get_dir("."))) {
    write("Unable to unpack %O to %O\n", fn, getcwd());
    processed_results[fn]=1;
    return;
  }

  mapping result = low_process_package();
  if(dry_run) {
    werror("%O\n", result);
    return;
  }

  if(result->build && result->system) {
    string dest = web_dir + result->build+"_"+result->system;
    mkdir(dest);
    int fail;
    foreach(get_dir("."), string f)
      if( Process.system(sprintf("mv %s %s", f, dest+"/"+f)) )
	fail = 1;
    if(fail || !rm(fn) )
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

int main(int num, array(string) args) {
  write(prog_id);

  foreach(Getopt.find_all_options(args, ({
    ({ "db",        Getopt.HAS_ARG, "--db"           }),
    ({ "dry",       Getopt.NO_ARG,  "--dry-run"      }),
    ({ "help",      Getopt.NO_ARG,  "--help"         }),
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

  while(1) {
    foreach(get_dir(result_dir), string fn) {
      fn = result_dir + fn;
      if(processed_results[fn]) continue;
      debug("Found new result %O\n", fn);
      process_package(fn);
    }
    sleep(result_poll);
  }

}

constant prog_id = "Xenofarm generic result parser\n"
"$Id: result_parser.pike,v 1.14 2002/08/14 16:56:40 mani Exp $\n";
constant prog_doc = #"
result_parser.pike <arguments> [<result files>]
--db         The database URL, e.g. mysql://localhost/xenofarm.
--dry-run    Do not store any results or alter any files outside
             of the working directory.
--help       Displays this text.
--poll       How often the result directory is checked for new
             result files.
--result-dir Where incoming result files are read from.
--verbose    Send messages about everything that happens to stdout.
--web-dir    Where the contents of the result files chould be
             copied to.
--work-dir   Where temporary files should be put.
";
