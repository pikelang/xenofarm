
// Xenofarm server
// By Martin Nilsson
// $Id: server.pike,v 1.12 2002/07/25 02:05:50 mani Exp $

Sql.Sql xfdb;

// One way to improve the database is to use an enum for the project column.
constant db_def = "CREATE TABLE build (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, "
                  "time INT UNSIGNED NOT NULL, "
                  "project VARCHAR(255) NOT NULL)";

int min_build_distance = 60*60*2;
int checkin_poll = 60;
int checkin_latency = 60*5;

string project;
string web_dir;
string repository;
string work_dir;

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

int get_latest_checkin() {
  // Parse history file
  return 0;
}

string make_build_low() {
  if(!Process.system("cvs co "+repository)) {
    write("Failed to check out from CVS repository %O to %O.\n", repository, getcwd());
    return 0;
  }

  if(!Process.system("tar -c "+repository+" > "+project+".tar")) {
    write("Failed to create %s.tar\n", project);
    return 0;
  }

  if(!Process.system("gzip -9 "+project+".tar")) {
    write("Failed to compress %s.tar\n", project);
    return 0;
  }

  return project+".tar.gz";
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

  xfdb->query("INSERT INTO build (time, project) VALUES (%d,%s)", latest_build, project);
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


  if(!repository) {
    write("No repository selected.\n");
    exit(1);
  }

  if(!project) {
    write("No project set.\n");
    exit(1);
  }

  if(verbose) {
    write("Database   : %s\n", xfdb->host_info());
    write("Project    : %s\n", project);
    write("Repository : %s\n", repository);
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
    ({ "help",      Getopt.NO_ARG,  "--help"         }),
    ({ "latency",   Getopt.HAS_ARG, "--latency"      }),
    ({ "poll",      Getopt.HAS_ARG, "--poll"         }),
    ({ "webdir",    Getopt.HAS_ARG, "--web-dir"      }),
    ({ "repository",Getopt.HAS_ARG, "--repository"   }),
    ({ "verbose",   Getopt.NO_ARG,  "--verbose"      }),
    ({ "workdir",   Getopt.HAS_ARG, "--work-dir"     }),
    ({ "force",     Getopt.NO_ARG,  "--force"        }),
  }) ),array opt)
    {
      switch(opt[0])
      {
      case "help":
	write(prog_doc);
	return 0;

      case "distance":
	min_build_distance = opt[1];
	break;

      case "poll":
	checkin_poll = opt[1];
	break;

      case "latency":
	checkin_latency = opt[1];
	break;

      case "db":
	xfdb = Sql.Sql( opt[1] );
	break;

      case "webdir":
	web_dir = opt[1];
	break;

      case "workdir":
	work_dir = opt[1];
	break;

      case "repository":
	repository = opt[1];
	break;

      case "verbose":
	verbose = 1;
	break;

      case "force":
	force_build = 1;
	break;
      }
    }
  args -= ({ 0 });

  if(sizeof(args)>2) {
    project = args[1];
  }

  check_settings();

  if(force_build) {
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
      continue;
    }

    // Enforce build distances
    if(time()-latest_build < min_build_distance) {
      debug("Enforce build distances. Quarantine left %s.\n",
	    fmt_time(min_build_distance-(time()-latest_build)));
      real_checkin_poll = min_build_distance - (time()-latest_build);
      continue;
    }

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
      }
    }

  }

  return 1;
}

constant prog_id = "Xenofarm generic server\n"
"$Id: server.pike,v 1.12 2002/07/25 02:05:50 mani Exp $\n";
constant prog_doc = #"
Blah blah.";
