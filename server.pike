#! /usr/bin/env pike

// Xenofarm server
// By Martin Nilsson
// Made useable on its own by Per Cederqvist
// $Id: server.pike,v 1.24 2002/08/30 01:42:25 mani Exp $

Sql.Sql xfdb;

// One way to improve the database is to use an enum for the project column.
constant db_def = "CREATE TABLE build (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, "
                  "time INT UNSIGNED NOT NULL, "
                  "project VARCHAR(255) NOT NULL)";

constant checkin_state_file = "state/checkin.timestamp";

int min_build_distance = 60*60*2;
int checkin_poll = 60;
int checkin_latency = 60*5;

string project;
string web_dir;
string repository;
string cvs_module;
string work_dir;
string source_transformer;
string update_opts = "-d";

int(0..1) verbose;
int latest_build;

void debug(string msg, mixed ... args) {
  if(verbose)
    write("[" + Calendar.ISO.now()->format_tod() + "] "+msg, @args);
}

int get_latest_build() {
  array res = xfdb->query("SELECT MAX(time) AS latest_build FROM build WHERE project=%s",
			  project);
  if(!sizeof(res)) return 0;
  return (int)res[0]->latest_build;
}

// The get_latest_checkin function should return the time of the
// latest checkin. This version actually returns the time we last
// detected that something has been checked in. That is good enough.
int get_latest_checkin() {
  int latest_checkin;

  if(!file_stat(cvs_module) || !file_stat(cvs_module)->isdir) {
    write("Please check out %O inside %O and re-run this script.\n", 
	  cvs_module, work_dir);
    exit(1);
  }
  debug("Running cvs update\n");
  if(Process.system("(cd "+cvs_module+" && cvs -q update "+update_opts+")"
		    +" > tmp/update.log")) {
    write("Failed to update CVS module %O in %O.\n", cvs_module, getcwd());
    exit(1);
  }

  latest_checkin = (int)Stdio.read_file(checkin_state_file);

  if(Stdio.read_file("tmp/update.log") != "") {
    debug("Something changed: \n%s", Stdio.read_file("tmp/update.log"));
    latest_checkin = time();
    Stdio.write_file(checkin_state_file, sprintf("%d\n", latest_checkin));
  }
  else {
    debug("Nothing changed\n");
  }

  // Handle a missing checkin_state_file file.  This should only happen
  // the first time server.pike is run.
  if (latest_checkin == 0) {
    debug("No checkin timestamp found.  Assuming something changed.\n");
    latest_checkin = time();
    Stdio.write_file(checkin_state_file, sprintf("%d\n", latest_checkin));
  }

  return latest_checkin;
}

// Return true on success, false on error.
int transform_source(string cvs_module, string name, string buildid) {
  if(source_transformer) {
    // FIXME: quoting.
    if(Process.system(source_transformer+" "+cvs_module+" "+name+" "
		      +buildid)) {
      write(source_transformer+" failed\n");
      return 0;
    }
  } 
  else {
    string stamp1 = cvs_module+"/export.stamp";
    string stamp2 = cvs_module+"/exportstamp.txt";
    string stamp3 = cvs_module+"/buildid.txt";
    if(file_stat(stamp1) || file_stat(stamp2) || file_stat(stamp3)) {
      write(stamp1+" or "+stamp2+" or "+stamp3+" exists!\n");
      exit(1);
    }
    Stdio.write_file(stamp1, buildid+"\n");
    Stdio.write_file(stamp2, buildid+"\n");
    Stdio.write_file(stamp3, buildid+"\n");
    if(Process.system("tar cf "+name+".tar "+cvs_module)) {
      write("Failed to create %s.tar\n", name);
      rm(stamp1);
      rm(stamp2);
      rm(stamp3);
      return 0;
    }
    if(Process.system("gzip -9 "+name+".tar")) {
      write("Failed to compress %s.tar\n", name);
      rm(stamp1);
      rm(stamp2);
      rm(stamp3);
      return 0;
    }
    rm(stamp1);
    rm(stamp2);
    rm(stamp3);
  }
  return 1;
}

string make_build_low() {
  object now = Calendar.now()->set_timezone("UTC");
  string name = sprintf("%s-%s-%s", project,
			now->format_ymd_short(),
			now->format_tod_short());
  
  latest_build = now->unix_time();

  xfdb->query("INSERT INTO build (time, project) VALUES (%d,%s)", 
	      latest_build, project);
  string buildid = xfdb->query("SELECT LAST_INSERT_ID() AS id")[0]->id;

  if (!transform_source(cvs_module, name, buildid)) {
    xfdb->query("DELETE FROM build WHERE id = %s", buildid);
    return 0;
  }

  return name+".tar.gz";
}

void make_build() {
  debug("Making new build.\n");

  int old_build_time = latest_build;

  string build_name = make_build_low();
  if(!build_name) {
    write("No source distribution was created by make_build_low...\n");
    return;
  }
  debug("The source distribution %s assembled.\n", build_name);

  if(latest_build == old_build_time)
    latest_build = time();

  string fn = (build_name/"/")[-1];

  if(!mv(build_name, web_dir+fn)) {
    write("Unable to move %s to %s.\n", build_name, web_dir+fn);
    return;
  }
}

string fmt_time(int t) {
  if(t<60)
    return sprintf("%02d seconds", t);
  if(t/60 < 60)
    return sprintf("%02d:%02d minutes", t/60, t%60);
  return sprintf("%02d:%02d:%02d hours", t/3600, (t%3600)/60, t%60);
}

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

  if(repository)
    repository = "-d "+repository;
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

int main(int num, array(string) args) {
  write(prog_id);

  int (0..1) force_build;

  foreach(Getopt.find_all_options(args, ({
    ({ "db",        Getopt.HAS_ARG, "--db"           }),
    ({ "distance",  Getopt.HAS_ARG, "--min-distance" }),
    ({ "force",     Getopt.NO_ARG,  "--force"        }),
    ({ "help",      Getopt.NO_ARG,  "--help"         }),
    ({ "latency",   Getopt.HAS_ARG, "--latency"      }),
    ({ "module",    Getopt.HAS_ARG, "--cvs-module"   }),
    ({ "poll",      Getopt.HAS_ARG, "--poll"         }),
    ({ "repository",Getopt.HAS_ARG, "--repository"   }),
    ({ "verbose",   Getopt.NO_ARG,  "--verbose"      }),
    ({ "webdir",    Getopt.HAS_ARG, "--web-dir"      }),
    ({ "workdir",   Getopt.HAS_ARG, "--work-dir"     }),
    ({ "sourcetransformer", Getopt.HAS_ARG, "--source-transform" }),
    ({ "updateopts", Getopt.HAS_ARG, "--update-opts" }),
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

      case "sourcetransformer":
	source_transformer = opt[1];
	break;

      case "updateopts":
	update_opts = opt[1];
	break;
      }
    }
  args -= ({ 0 });

  if(sizeof(args)>1) {
    project = args[1];
  }

  check_settings();

  if(force_build) {
    get_latest_checkin();
    make_build();
    return 0;
  }

  latest_build = get_latest_build();
  if(latest_build)
    debug("Latest build was %s ago.\n", fmt_time(time()-latest_build));
  else
    debug("No previous builds found.\n");

  int real_checkin_poll;
  int next_build;
  int waitloop_state;

  while(1) {
    if(checkin_poll==real_checkin_poll)
      waitloop_state = 1;
    else
      waitloop_state = 0;

    if(!waitloop_state) debug("Sleep %d seconds...\n", real_checkin_poll);
    sleep(real_checkin_poll);
    real_checkin_poll = checkin_poll;

    // Enforce build distances
    if(time()-latest_build < min_build_distance) {
      debug("Enforce build distances. Quarantine left %s.\n",
	    fmt_time(min_build_distance-(time()-latest_build)));
      real_checkin_poll = min_build_distance - (time()-latest_build);
      continue;
    }

    // Queue a build
    int new_checkin = get_latest_checkin();
    if(!waitloop_state) debug("Latest checkin was %s ago.\n", fmt_time(time()-new_checkin));
    if(new_checkin>latest_build) {
      if(new_checkin + checkin_latency < time()) {
	next_build = time()-1;
	debug("A new build is scheduled to run at once.\n");
	real_checkin_poll = 0;
      }
      else {
	next_build = time()+checkin_latency;
	debug("A new build is scheduled to run in %s.\n", fmt_time(checkin_latency));
	real_checkin_poll = checkin_latency;
	continue;
      }
    }

    // Is there a queued build?
    if(next_build) {
      if(verbose) {
	int diff = next_build-time();
	if(diff<=0)
	  debug("New build scheduled to run at once.\n");
	else
	  debug("New build scheduled to run in %s.\n", fmt_time(diff));
      }
      if(next_build<=time()) {
	make_build();
	latest_build = get_latest_build();
	next_build = 0;
      }
    }

  }

  return 1;
}

constant prog_id = "Xenofarm generic server\n"
"$Id: server.pike,v 1.24 2002/08/30 01:42:25 mani Exp $\n";
constant prog_doc = #"
server.pike <arguments> <project>
Where the arguments db, cvs-module, web-dir and work-dir are
mandatory and the project is the name of the project.
Possible arguments:

--cvs-module   The CVS module the server should use.
--update-opts  CVS options to append to \"cvs -q update\".  Default: \"-d\".
               \"--update-opts=-Pd\" also makes sense.
--db           The database URL, e.g. mysql://localhost/xenofarm.
--force        Make a new build and exit.
--help         Displays this text.
--latency      The enforced latency between the latest checkin and
               when the next build is run. Defaults to 300 seconds
               (5 minutes).
--min-distance The enforced minimum distance between to builds.
               Defaults to 7200 seconds (two hours).
--poll         How often the CVS is queried for new checkins.
               Defaults to 60 seconds.
--repository   The CVS repository the server should use.
--verbose      Send messages about everything that happens to stdout.
--web-dir      Where the outgoing build packages should be put.
--work-dir     Where temporary files should be put.
--source-transform Program that builds the source package (see README).
";
