
// Xenofarm server
// By Martin Nilsson
// $Id: server.pike,v 1.1 2002/05/03 15:46:57 mani Exp $

Sql.Sql xfdb;

// One way to improve the database is to use an enum for the project column.
constant db_def = "CREATE TABLE build (id INT UNSIGNED NOT NULL AUTO INCREMENT PRIMARY KEY, "
                  "time INT UNSIGNED NOT NULL, "
                  "project VARCHAR(255) NOT NULL)";

int min_build_distance = 60*60*2;
int checkin_poll = 60;
int checkin_latency = 60*5;

string project;
string web_dir;

int latest_build;

int get_latest_build() {
  array res = xfdb->query("SELECT MAX(time) AS latest_build FROM build WHERE project=%s", project);
  if(!sizeof(res)) return 0;
  return res[0]->latest_build;
}

int get_latest_checkin() {
  // Parser.RCS code here.
  return 0;
}

string make_build_low() {
  // cvs co project
  // tar project
  // gzip project
  return filename;
}

void make_build() {

  string build_name = make_build_low();
  if(!build_name) return;

  if(!mv(build_name, web_dir))
    return;

  xfdb->query("INSERT INTO builds (time, project) VALUES (%d,%s)", latest_build, project);
}

void check_settings() {
  if(!xfdb) {
    werror("No database found.\n");
    exit(1);
  }

  if(!web_dir) {
    werror("No web dir found.\n");
    exit(1);
  }
  if(!file_stat(web_dir)) {
    werror("%s does not exist.\n", web_dir);
    exit(1);
  }
  if(!fil_stat(web_dir)->isdir) {
    werror("%s is no directory.\n", web_dir);
    exit(1);
  }

  if(!project) {
    werror("No project set.\n");
    exit(1);
  }
}

int main(int num, array(string) args) {
  werror(prog_name);

  foreach(Getopt.find_all_options(argv, ({
    ({ "db",        Getopt.HAS_ARG, "--db"           }),
    ({ "distance",  Getopt.HAS_ARG, "--min-distance" }),
    ({ "help",      Getopt.NO_ARG,  "--help"         }),
    ({ "latency",   Getopt.HAS_ARG, "--latency"      }),
    ({ "poll",      Getopt.HAS_ARG, "--poll"         }),
    ({ "webdir",   Getopt.HAS_ARG, "--web-dir"      }),
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

      case "webdir":
	web_dir = opt[1];
      }
    }

  if(sizeof(args)>2) {
    project = args[1];
  }

  check_settings();

  latest_build = get_latest_build();

  int real_checkin_poll;
  int next_build;

  while(1) {
    sleep(real_checkin_poll);
    real_checkin_poll = checkin_poll;

    // Is there a queued build?
    if(next_build) {
      if(next_build<time()) {
	make_build();
	latest_build = get_latest_build();
	next_build = 0;
      }
      continue;
    }

    // Enforce build distances
    if(time()-latest_build < min_build_distance)
      continue;

    int new_checkin = get_latest_checkin();
    if(new_checkin>latest_build)
      next_build = new_checkin+checkin_latency;

  }

  return 1;
}

constant prog_id = "Xenofarm generic server\n";
constant prog_doc = #"
Blah blah.";
