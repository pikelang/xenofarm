#! /usr/bin/env pike

// Xenofarm server for the Pike project
// By Martin Nilsson

// The Xenofarm server program is not really intended to be run
// verbatim, since almost all projects have their own little funny
// things to take care of. This is an adaptation for the Pike
// programming language itself.

inherit "../../server.pike";

// Set default values to variables, so that we don't have to remember
// to give them when starting the program unless we really want to.

string pike_version;

void create() {
  if(!this_object()->pike_version) {
    werror("This program is not intended to be run.\n");
    exit(1);
  }
#define FIX(X) X += this_object()->pike_version + "/";
  FIX(web_dir);
  FIX(work_dir);
  FIX(result_dir);
  project += this_object()->pike_version;
  client = PikeRepositoryClient();
}

string project = "pike";
#ifdef NILSSON
string web_dir = "/home/nilsson/xenofarm/projects/pike/out/";
string work_dir = "/home/nilsson/xenofarm/projects/pike/out_work/";
string result_dir = "/home/nilsson/html/xenofarm/";
string repository = ":ext:nilsson@pike.ida.liu.se:/pike/data/cvsroot";
#else
string web_dir = "/pike/data/pikefarm/out/";
string work_dir = "/pike/data/pikefarm/out_work/";
string result_dir = "/pike/data/pikefarm/results/";
string repository = "/pike/data/cvsroot";
#endif
string cvs_module = "(ignored)"; // Not used.

constant latest_pike_checkin = "";

// Overload and disable the base clients
class CVSClient {
  constant arguments = "";
  void create() { error("Not allowed repository method for Pike.\n"); }
}
class StarTeam {
  constant arguments = "";
  void create() { error("Not allowed repository method for Pike.\n"); }
}

string make_export_name(int latest_checkin)
{
  Calendar.TimeRange o = Calendar.ISO_UTC.Second(latest_checkin);
  return sprintf("Pike%s-%s-%s.tar.gz", pike_version,
		 o->format_ymd_short(), o->format_tod_short());
}

class PikeRepositoryClient {
  inherit RepositoryClient;

  void parse_arguments(array(string) args) { }
  string module() { return pike_version; }
  string name() { return "PikeRepository"; }

  TimeStampCommitId get_latest_checkin() {
    string timestamp;
    array err = catch {
      timestamp = Protocols.HTTP.get_url_data(latest_pike_checkin);
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

  string last_name;
  void update_source(TimeStampCommitId latest_checkin) {
    cd(work_dir);
    Stdio.recursive_rm("Pike");

    Calendar.TimeRange at = Calendar.ISO_UTC.Second(latest_checkin->unix_time());
    object checkout =
      Process.create_process(({ "cvs", "-Q", "-d", repository, "co", "-D",
				at->set_timezone("localtime")->format_time(),
				"Pike/" + pike_version }));
    if(checkout->wait())
      return 0; // something went wrong

    string name = make_export_name(latest_checkin->unix_time());
    cd("Pike/"+pike_version);
    if(Process.system("make xenofarm_export "
#ifndef NILSSON
		      "CONFIGUREARGS=\"--with-site-prefixes=/pike/sw/\" "
#endif
		      "EXPORTARGS=\"--timestamp=" + latest_checkin->unix_time() + "\"") ||
       !file_stat(name) ) {
      if(!file_stat(name))
	write("Could not find %O from %O.\n", name, getcwd());
      persistent_query("INSERT INTO build (time, project, branch, export) "
		       "VALUES (%d, %s, %s, 'FAIL')",
		       latest_checkin->unix_time(), project, branch);
      return 0;
    }

    persistent_query("INSERT INTO build (time, project, branch, export) "
		     "VALUES (%d, %s, %s, 'PASS')",
		     latest_checkin->unix_time(), project, branch);

    last_name = name;
  }
}


string make_build_low(TimeStampCommitId t) {
  array res = persistent_query("SELECT id FROM build "
			       "WHERE time=%d AND project=%s AND branch=%s",
			       t->unix_time(), project, branch);
  if(!sizeof(res)) {
    debug("Id not found with time as key. Something is broken.\n");
    return client->last_name;
  }

  debug("Build id is %O\n", res[0]->id);
  string target_dir = result_dir + res[0]->id;
  mkdir(target_dir);
  if(!mv(work_dir+"Pike/"+pike_version+"/export_result.txt",
	 target_dir+"/export_result.txt"))
    debug("Failed to move %O to %O.\n",
	  work_dir+"Pike/"+pike_version+"/export_result.txt",
	  target_dir+"/export_result.txt");
  return client->last_name;
}

constant prog_id = "Xenofarm Pike server\n";
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
