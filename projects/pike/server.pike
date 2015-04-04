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

RepositoryClient get_client()
{
  RepositoryClient client = PikeRepositoryClient();
  return client;
}

string project = "Pike";
array(string) branches = ({ "8.1", "8.0", "7.8", "7.6", "7.4", });

Sql.Sql xfdb = Sql.Sql("mysql://pikefarm@/pikefarm");

#ifdef NILSSON
string web_format = "/home/nilsson/xenofarm/projects/pike/out/%B/";
string work_dir = "/home/nilsson/xenofarm/projects/pike/out_work/";
string result_dir = "/home/nilsson/html/xenofarm/";
string repository = ":ext:nilsson@pike.ida.liu.se:/pike/data/cvsroot";
#else
string web_format = "/space/www/pikefarm/packages/%B/";
string work_dir = "/space/www/pikefarm/out_work/";
string result_dir = "/space/www/pikefarm/results/";
string repository = "/gitdir";
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
  return sprintf("Pike%s-%s-%s.tar.gz", branch,
		 o->format_ymd_short(), o->format_tod_short());
}

class PikeRepositoryClient
{
  inherit GitClient;

  void parse_arguments(array(string) args) { }
  string module() { return branch; }
  string name() { return "PikeRepository"; }

  string last_name;

  void update_source(Sha1CommitId latest_checkin)
  {
    ::update_source(latest_checkin);

    // Stdio.recursive_rm("Pike");

    string name = make_export_name(latest_checkin->unix_time());

    mapping res = Process.run(({ "make", "xenofarm_export",
#if 0
#ifndef NILSSON
				 "CONFIGUREARGS=--with-site-prefixes=/pike/sw",
#endif
#endif
				 "EXPORTARGS=--timestamp=" + latest_checkin->unix_time(),
			      }), ([
				"cwd": work_dir + "/" + branch,
			      ]));

    string full_name = work_dir + "/" + branch + "/" + name;

    if (res->exitcode || !file_stat(full_name)) {
      if(!file_stat(full_name))
	write("Could not find %O from %O.\n", full_name, getcwd());
      persistent_query("INSERT INTO build (time, project, branch, export) "
		       "VALUES (%d, %s, %s, 'FAIL')",
		       latest_checkin->unix_time(), project, branch);
      return;
    }

    persistent_query("INSERT INTO build (time, project, branch, export) "
		     "VALUES (%d, %s, %s, 'PASS')",
		     latest_checkin->unix_time(), project, branch);

    werror("CWD: %O\n"
	   "full_name: %O\n"
	   "name: %O\n",
	   getcwd(), full_name, name);

    last_name = full_name;
  }
}


string make_build_low(Sha1CommitId t)
{
  int buildid = t->create_build_id();

  debug("Build id is %O\n", buildid);
  string target_dir = result_dir + branch + "/" + buildid;
  mkdir(target_dir);
  if(!mv(work_dir+branch+"/export_result.txt",
	 target_dir+"/export_result.txt")) {
    string export_res =
      Stdio.read_bytes(work_dir+branch+"/export_result.txt");
    if (!export_res ||
	(Stdio.write_file(target_dir+"/export_result.txt", export_res) !=
	 sizeof(export_res))) {
      debug("Failed to move/copy %O to %O.\n",
	    work_dir+branch+"/export_result.txt",
	    target_dir+"/export_result.txt");
    }
  }
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
