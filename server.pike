#! /usr/bin/env pike

// Xenofarm server
// By Martin Nilsson
// Made useable on its own by Per Cederqvist
// $Id: server.pike,v 1.47 2003/01/11 14:03:26 mani Exp $

Sql.Sql xfdb;

constant checkin_state_file = "state/checkin.timestamp";

int min_build_distance = 60*60*2;
int fail_build_divisor = 2*6;
int checkin_poll = 60;
int checkin_latency = 60*5;

string project;
string web_dir;
string repository;
string cvs_module;
string work_dir;
string source_transformer;
array(string) update_opts = ({});

int(0..1) verbose;
int latest_build;
string latest_state="FAIL";


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
	write("Database query failed. Continue to try...\n");
	if(arrayp(err) && sizeof(err) && stringp(err[0]))
	  debug("(%s)\n", err[0][..sizeof(err)-2]);
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

string fmt_time(int t) {
  if(t<60)
    return sprintf("%02d seconds", t);
  if(t/60 < 60)
    return sprintf("%02d:%02d minutes", t/60, t%60);
  return sprintf("%02d:%02d:%02d hours", t/3600, (t%3600)/60, t%60);
}


//
// "API" functions
//

// Should return the (UTC) unixtime of the latest build package made for
// this project.
int get_latest_build()
{
  array res = persistent_query("SELECT time AS latest_build, export "
			       "FROM build ORDER BY -time LIMIT 1");
  if(!res || !sizeof(res)) return 0;
  latest_state = res[0]->export;
  return (int)(res[0]->latest_build);
}

// The get_latest_checkin function should return the (UTC) unixtime of
// the latest checkin. This version actually returns the time we last
// detected that something has been checked in. That is good enough.
int get_latest_checkin()
{
  if(!file_stat(cvs_module) || !file_stat(cvs_module)->isdir) {
    write("Please check out %O inside %O and re-run this script.\n", 
	  cvs_module, work_dir);
    exit(1);
  }

  debug("Running cvs update.\n");
  Calendar.TimeRange now = Calendar.Second();
  object update =
    Process.create_process(({ "cvs", "-q", "update", "-D", now->format_time(),
			      @update_opts }),
			   ([ "cwd"    : cvs_module,
			      "stdout" : Stdio.File("tmp/update.log", "cwt"),
			      "stderr" : Stdio.File("/dev/null", "cwt") ]));
  if(update->wait())
  {
    write("Failed to update CVS module %O in %O.\n", cvs_module, getcwd());
    exit(1);
  }

  int latest_checkin = (int)Stdio.read_file(checkin_state_file);
  array(string) log;
  log = filter(Stdio.read_file("tmp/update.log") / "\n" - ({ "" }),
	       lambda(string row) { return !has_prefix(row, "? "); });
  if(sizeof(log))
  {
    debug("Something changed: \n  %s", log * "\n  ");
    latest_checkin = now->unix_time();
    Stdio.write_file(checkin_state_file, latest_checkin + "\n");
  }
  else {
    debug("Nothing changed\n");
  }

  // Handle a missing checkin_state_file file.  This should only happen
  // the first time server.pike is run.
  if(latest_checkin == 0)
  {
    debug("No checkin timestamp found; assuming something changed.\n");
    latest_checkin = now->unix_time();
    Stdio.write_file(checkin_state_file, latest_checkin + "\n");
  }

  return latest_checkin;
}

// Return true on success, false on error.
int(0..1) transform_source(string cvs_module, string name, string buildid) {
  if(source_transformer) {
    if(Process.create_process( ({ source_transformer, cvs_module, name, buildid }),
			       ([]) )->wait() ) {
      write(source_transformer+" failed\n");
      return 0;
    }
  } 
  else {
    string stamp = cvs_module+"/buildid.txt";
    if(file_stat(stamp)) {
      write(stamp+" exists!\n");
      exit(1);
    }
    Stdio.write_file(stamp, buildid+"\n");
    if(Process.create_process( ({ "tar", "cf", name+".tar", cvs_module }),
			       ([]) )->wait() ) {
      write("Failed to create %s.tar\n", name);
      rm(stamp);
      return 0;
    }
    if(Process.create_process( ({ "gzip", "-9", name+".tar" }), ([]) )->wait() ) {
      write("Failed to compress %s.tar\n", name);
      rm(stamp);
      return 0;
    }
    rm(stamp);
  }
  return 1;
}

string make_build_low(int latest_checkin)
{
  int latest_build = latest_checkin;
  object at = Calendar.ISO_UTC.Second("unix", latest_build);
  string name = sprintf("%s-%s-%s", project,
			at->format_ymd_short(),
			at->format_tod_short());
  persistent_query("INSERT INTO build (time, export) VALUES (%d,'PASS')",
		   latest_build);

  string buildid;
  mixed err = catch {
    buildid = xfdb->query("SELECT LAST_INSERT_ID() AS id")[0]->id;
  };
  if(err) {
    catch(xfdb->query("DELETE FROM build WHERE time=%d", latest_build));
    return 0;
  }

  if (!transform_source(cvs_module, name, buildid)) {
    persistent_query("UPDATE build SET export='FAIL' WHERE id=%d", (int)buildid);
    return 0;
  }

  return name+".tar.gz";
}

void make_build(int timestamp)
{
  debug("Making new build.\n");

  string build_name = make_build_low(timestamp);
  if(!build_name) {
    write("No source distribution was created by make_build_low...\n");
    return;
  }
  debug("The source distribution %s assembled.\n", build_name);

  string fn = (build_name/"/")[-1];

  if(Process.create_process( ({ "mv", build_name, web_dir+fn }) )) {
    write("Unable to move %s to %s.\n", build_name, web_dir+fn);
    return;
  }
}


//
// Main program code
//

void check_settings() {
  if(!xfdb) {
    write("No database found.\n");
    exit(1);
  }

  if(work_dir) {
    if(!file_stat(work_dir) || !file_stat(work_dir)->isdir) {
      write("Working directory %s does not exist.\n", work_dir);
      exit(1);
    }
    cd(work_dir);
    mkdir("tmp");		// Ignore errors. It should normally exist.
    mkdir("state");		// Ignore errors. It should normally exist.
    // FIXME: Check write privileges.
  }

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

  if(!cvs_module) {
    write("No CVS module selected.\n");
    exit(1);
  }

  // FIXME: Check CVSROOT?

  if(!project) {
    write("No project set.\n");
    exit(1);
  }

  if(verbose) {
    write("Database   : %s\n", xfdb->host_info());
    write("Project    : %s\n", project);
    write("CVS module : %s\n", cvs_module);
    write("Repository : %s\n", repository||"(implicit)");
    write("Work dir   : %s\n", work_dir);
    write("Web dir    : %s\n", web_dir);
    write("\n");
  }
}

int main(int num, array(string) args)
{
  write(prog_id);
  int (0..1) force_build;
  int (0..1) once_only = 0;

  foreach(Getopt.find_all_options(args, ({
    ({ "db",          Getopt.HAS_ARG, "--db"           }),
    ({ "distance",    Getopt.HAS_ARG, "--min-distance" }),
    ({ "force",       Getopt.NO_ARG,  "--force"        }),
    ({ "help",        Getopt.NO_ARG,  "--help"         }),
    ({ "latency",     Getopt.HAS_ARG, "--latency"      }),
    ({ "module",      Getopt.HAS_ARG, "--cvs-module"   }),
    ({ "once",        Getopt.NO_ARG,  "--once"         }),
    ({ "poll",        Getopt.HAS_ARG, "--poll"         }),
    ({ "repository",  Getopt.HAS_ARG, "--repository"   }),
    ({ "verbose",     Getopt.NO_ARG,  "--verbose"      }),
    ({ "webdir",      Getopt.HAS_ARG, "--web-dir"      }),
    ({ "workdir",     Getopt.HAS_ARG, "--work-dir"     }),
    ({ "transformer", Getopt.HAS_ARG, "--transformer" }),
    ({ "updateopts",  Getopt.HAS_ARG, "--update-opts" }),
  }) ),array opt)
    {
      switch(opt[0])
      {
      case "db":
	xfdb = Sql.Sql( opt[1] );
	break;

      case "distance":
	min_build_distance = (int)opt[1];
	break;

      case "force":
	force_build = 1;
	break;

      case "help":
	write(prog_doc);
	return 0;

      case "latency":
	checkin_latency = (int)opt[1];
	break;

      case "module":
	cvs_module = opt[1];
	break;

      case "once":
	once_only = 1;

      case "poll":
	checkin_poll = (int)opt[1];
	break;

      case "repository":
	repository = opt[1];
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

      case "transformer":
	source_transformer = opt[1];
	break;

      case "updateopts":
	update_opts += ({ opt[1] });
	break;
      }
    }
  if(!sizeof(update_opts))
    update_opts = ({ "-Pd" });
  args -= ({ 0 });

  if(sizeof(args)>1) {
    project = args[1];
  }

  check_settings();

  if(force_build)
  {
    get_latest_checkin();
    make_build(time());
    exit(0);
  }

  latest_build = get_latest_build();
  if(latest_build)
    debug("Latest build was %s ago.\n", fmt_time(time()-latest_build));
  else
    debug("No previous builds found.\n");

  int sleep_for;
  int(0..1) sit_quietly;
  while(1)
  {
    int now = Calendar.now()->unix_time();
    int delta = now - latest_build;
    int min_distance = min_build_distance;

    if (latest_state == "FAIL") min_distance /= fail_build_divisor;

    if(delta < min_distance) // Enforce minimum time between builds
    {
      sleep_for = min_distance - delta;
      debug("Enforcing minimum build distance. Quarantine left: %s.\n",
	    fmt_time(sleep_for));
      sit_quietly = 0;
    }
    else // After the next commit + inactivity cycle it's time for a new build
    {
      int latest_checkin = get_latest_checkin();

      if(!sit_quietly) {
	debug("Latest checkin was %s ago.\n", fmt_time(now - latest_checkin));
	sit_quietly = 1;
      }
      if(latest_checkin > latest_build)
      {
	if(latest_checkin + checkin_latency <= now)
	{
	  sleep_for = 0;
	  int timestamp = time();
	  if(checkin_latency) {
	    // Put the timestamp between latest checkin and now
	    // to avoid mid-checkins.
	    timestamp = timestamp - checkin_latency + 1;
	  }
	  if(timestamp < latest_checkin) {
	    debug("System time < latest checkin!\n");
	    timestamp = latest_checkin;
	  }
	  make_build(timestamp);
	  latest_build = get_latest_build();
	}
	else // Enforce minimum time of inactivity after a commit
	{
	  sleep_for = latest_checkin + checkin_latency - now;
	  debug("A new build is scheduled to run in %s.\n",
		fmt_time(sleep_for));
	}
	sit_quietly = 0;
      }
      else // Polling for the first post-build-quarantine commit
      {
	sit_quietly = 1; // until something happens in the repository
	sleep_for = checkin_poll; // poll frequency
      }
    }

    if (once_only)
	return 0;

    if(!sit_quietly)
      debug("Sleeping for %d seconds...\n", sleep_for);
    sleep(sleep_for);
  }
}

constant prog_id = "Xenofarm generic server\n"
"$Id: server.pike,v 1.47 2003/01/11 14:03:26 mani Exp $\n";
constant prog_doc = #"
server.pike <arguments> <project>
Where the arguments db, cvs-module, web-dir and work-dir are
mandatory and the project is the name of the project.
Possible arguments:

--cvs-module   The CVS module the server should use.
--db           The database URL, e.g. mysql://localhost/xenofarm.
--force        Make a new build and exit.
--help         Displays this text.
--latency      The enforced latency between the latest checkin and
               when the next build is run. Defaults to 300 seconds
               (5 minutes).
--min-distance The enforced minimum distance between to builds.
               Defaults to 7200 seconds (two hours).
--once         Run just once.
--poll         How often the CVS is queried for new checkins.
               Defaults to every 60 seconds.
--repository   The CVS repository the server should use.
--transformer  Program that builds the source package (see README).
--update-opts  CVS options to append to \"cvs -q update\".  Default: \"-d\".
               \"--update-opts=-Pd\" also makes sense.
--verbose      Send messages about everything that happens to stdout.
--web-dir      Where the outgoing build packages should be put.
--work-dir     Where temporary files should be put.
";
