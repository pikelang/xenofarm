#! /usr/bin/env pike

// Xenofarm server for the Pike project
// By Martin Nilsson
// $Id: server.pike,v 1.23 2002/10/15 19:52:42 mani Exp $

// The Xenofarm server program is not really intended to be run
// verbatim, since almost all projects have their own little funny
// things to take care of. This is an adaptation for the Pike
// programming language itself.

inherit "../../server.pike";

// Set default values to variables, so that we don't have to remember to give them
// when starting the program.
#ifdef NILSSON
Sql.Sql xfdb = Sql.Sql("mysql://localhost/xenofarm");
#else
Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/xenofarm");
#endif

string project = "pike7.3";
#ifdef NILSSON
string web_dir = "/home/nilsson/xenofarm/projects/pike/out/";
string work_dir = "/home/nilsson/xenofarm/projects/pike/out_work/";
string repository = ":ext:nilsson@pike.ida.liu.se:/pike/data/cvsroot";
#else
string web_dir = "/pike/home/manual/pikefarm/out/";
string work_dir = "/pike/home/manual/pikefarm/out_work/";
string repository = "/pike/data/cvsroot";
#endif
string cvs_module = "(ignored)"; // Ignore this.

string pike_version = "7.3";

// Also, our database has a few more fields than the standard definition.
constant db_def = "CREATE TABLE build (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, "
                  "time INT UNSIGNED NOT NULL, "
                  "project ENUM('pike7.3') NOT NULL, "
                  "export ENUM('yes','no') NOT NULL DEFAULT 'yes', "
                  "documentation ENUM('yes','no') )";

constant latest_pike73_checkin = "http://pike.ida.liu.se/development/cvs/latest-Pike-commit";

string make_export_name(int t) {
  object o=Calendar.set_timezone("UTC")->Second("unix", t);
  return sprintf("Pike%s-%s-%s.tar.gz", pike_version,
		 o->format_ymd_short(), o->format_tod_short());
}

int get_latest_checkin()
{
  string timestamp;
  array err = catch {
    timestamp = Protocols.HTTP.get_url_data(latest_pike73_checkin);
  };

  if(err) {
    write(describe_backtrace(err));
    return 0;
  }

  err = catch {
    int ts = Calendar.set_timezone("UTC")->dwim_time(timestamp)->unix_time();
    return ts;
  };

  if(err)
    write(describe_backtrace(err));
  return 0;
}

string make_build_low() {
  cd(work_dir);
  Stdio.recursive_rm("Pike");

  int t = time();
  if(Process.system("cvs -Q "+repository+" co Pike/"+
		    pike_version))
    return 0;

  string name = make_export_name(t);
  cd("Pike/"+pike_version);
  if(Process.system("make xenofarm_export "
#ifndef NILSSON
    		    "CONFIGUREARGS=\"--with-site-prefixes=/pike/sw/\" "
#endif
		    "EXPORTARGS=\"--timestamp=" + t + "\"") ||
     !file_stat(name) ) {
    if(!file_stat(name))
       write("Could not find %O from %O.\n", name, getcwd());
    xfdb->query("INSERT INTO build (time, project, export) VALUES (%d,%s,'no')",
		t, project);
    return 0;
  }

  latest_build = t;
  xfdb->query("INSERT INTO build (time, project, export) VALUES (%d,%s,'yes')",
	      t, project);

  return name;
}

constant prog_id = "Xenofarm Pike server\n"
"$Id: server.pike,v 1.23 2002/10/15 19:52:42 mani Exp $\n";
constant prog_doc = #"
server.pike <arguments> <project>
Project defaults to pike7.3.
Possible arguments:

--db           The database URL. Defaults to
               mysql://localhost/xenofarm.
--force        Make a new build and exit.
--help         Displays this text.
--latency      The enforced latency between the latest checkin and
               when the next build is run. Defaults to 300 seconds
               (5 minutes).
--min-distance The enforced minimum distance between to builds.
               Defaults to 7200 seconds (two hours).
--poll         How often the CVS is queried for new checkins.
               Defaults to 60 seconds.
--verbose      Send messages about everything that happens to stdout.
--web-dir      Where the outgoing source packages should be put.
               Defaults to /home/nilsson/xenofarm/out/.
--work-dir     Where temporary files should be put. Defaults to
               /home/nilsson/xenofarm/temp/.
";
