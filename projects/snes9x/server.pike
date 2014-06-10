#! /usr/bin/env pike

// Xenofarm server for the Snes project
// By Martin Nilsson

// The Xenofarm server program is not really intended to be run
// verbatim, since almost all projects have their own little funny
// things to take care of. This is an adaptation for the Snes9X.

inherit "../../server.pike";

// Set default values to variables, so that we don't have to remember
// to give them when starting the program unless we really want to.
string dburl = getenv("DBURL") || Stdio.read_file("mysql.url")
  || Stdio.read_file(combine_path(getenv("HOME"),".mysql.url"));
Sql.sql xfdb = Sql.sql( dburl-"\n" );

string pike_version;

void create() {
//   if(!this_object()->pike_version) {
//     werror("This program is not intended to be run.\n");
//     exit(1);
//   }
#define FIX(X) X += "head/";
  FIX(web_dir);
  FIX(work_dir);
  //  FIX(result_dir);
//  project += this_object()->pike_version;
}

string project  = "snes9x";
string web_dir  = "/mnt/moreweb/projekt/snes9x/builds/";
string work_dir = "/mnt/moreweb/projekt/snes9x/work/";
//string result_dir = "/pike/data/pikefarm/results/";
string repository = "pbortas@fliptw.tarnar.net:/cvsroot";
string cvs_module = "snes9x"; // Not used.

constant latest_snes_checkin = "";

string make_export_name(int latest_checkin)
{
  Calendar.TimeRange o = Calendar.ISO_UTC.Second(latest_checkin);
  return sprintf("snes9x-%s-%s.tar.gz", 
		 o->format_ymd_short(), o->format_tod_short());
}

TimeStampCommitId get_latest_checkin()
{
  string timestamp;
  array err = catch {
    timestamp = Protocols.HTTP.get_url_data(latest_snes_checkin);
  };

  if(err) {
    write(describe_backtrace(err));
    return 0;
  }

  err = catch {
    int ts = Calendar.ISO_UTC.dwim_time(timestamp)->unix_time();
    return TimeStampCommitId(ts);
  };

  if(err)
    write(describe_backtrace(err));
  return 0;
}

string make_build_low(TimeStampCommitId t) {
  string ret = make_build_low_low(t->unix_time());
  array res = persistent_query("SELECT id FROM build "
			       "WHERE time=%d AND project=%s AND branch=%s",
			       t->unix_time(), project, branch);
  if(!sizeof(res)) {
    debug("Id not found with time as key. Something is broken.\n");
    return ret;
  }

  debug("Build id is %O\n", res[0]->id);
  //  string target_dir = result_dir + res[0]->id;
  //  mkdir(target_dir);
//   if(!mv(work_dir+"Pike/"+pike_version+"/export_result.txt",
// 	 target_dir+"/export_result.txt"))
//     debug("Failed to move %O to %O.\n",
// 	  work_dir+"Pike/"+pike_version+"/export_result.txt",
// 	  target_dir+"/export_result.txt");
  return ret;
}

constant stamp=#"Snes9X export stamp
time:%t
major:%maj
minor:%min
build:%bld
year:%Y
month:%M
day:%D
hour:%h
minute:%m
second:%s
";

//Partially faked version
array(int) getversion()
{
  return ({ 1, 39, 1 });
}

string make_buildid(int latest_checkin)
{
  mapping m = gmtime(latest_checkin);
  array(int) version = getversion();
  mapping symbols=([
    "%maj":(string) version[0],
    "%min":(string) version[1],
    "%bld":(string) version[2],
    "%Y":sprintf("%04d",1900+m->year),
    "%M":sprintf("%02d",1+m->mon),
    "%D":sprintf("%02d",m->mday),
    "%h":sprintf("%02d",m->hour),
    "%m":sprintf("%02d",m->min),
    "%s":sprintf("%02d",m->sec),
    "%t":(string)latest_checkin,
  ]);

  return replace(stamp, symbols);
}

string make_build_low_low(int latest_checkin)
{
  string cvsmodule = "snes9x";

  cd(work_dir);
  Stdio.recursive_rm(cvsmodule);

  Calendar.TimeRange at = Calendar.ISO_UTC.Second(latest_checkin);
  object checkout =
    Process.create_process(({ "cvs", "-Q", "-d", repository, "co", "-D",
			      at->set_timezone("localtime")->format_time(),
			      cvsmodule }));
  if(checkout->wait())
    return 0; // something went wrong

  string name = make_export_name(latest_checkin);
  cd(cvsmodule);
  Stdio.write_file("buildid.txt", make_buildid(latest_checkin));
  cd("snes9x");
  string status="PASS";
  if(Process.system("autoconf")) {
    status="FAIL";
  } else {
    cd(work_dir);
    debug("Making archive %s\n", work_dir+"/"+name);
    if(Process.system("tar czf "+ work_dir+"/"+name +" snes9x"))
      status="FAIL";
  }

  persistent_query("INSERT INTO build (time, project, branch, export) "
		   "VALUES (%d, %s, %s, '"+status+"')",
		   latest_checkin, project, branch);
  if(status == "FAIL")
    return 0;

  return name;
}

constant prog_id = "Xenofarm Snes server\n";
constant prog_doc = #"
server.pike <arguments> <project>
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
