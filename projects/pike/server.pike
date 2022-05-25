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
array(string) branches = ({ "master", "8.0", "8.1", "7.8", "7.6", "7.4", });

Sql.Sql xfdb = Sql.Sql("mysql://pikefarm@:/tmp/mariadb101.sock/pikefarm");

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

// Reduce the minimum build distance for some of the branches.
int get_min_build_distance()
{
  int i = search(branches, branch);
  if (!i) return min_build_distance/4;		// Primary branch.
  if (i == 1) return min_build_distance/2;	// Secondary branch.
  return min_build_distance;			// Other branches.
}

// Overload and disable the base clients
class CVSClient {
  constant arguments = "";
  void create() { error("Not allowed repository method for Pike.\n"); }
}
class StarTeam {
  constant arguments = "";
  void create() { error("Not allowed repository method for Pike.\n"); }
}

class Sha1CommitId
{
  inherit ::this_program;

  string dist_name()
  {
    object at = Calendar.ISO_UTC.Second("unix", unix_time());
    return sprintf("%s%s-%s-%s", project, branch,
                  at->format_ymd_short(),
                  at->format_tod_short());
  }
}

class PikeRepositoryClient
{
  inherit GitClient;

  void parse_arguments(array(string) args) { }
  string module() { return branch; }
  string name() { return "PikeRepository"; }

  string last_name;

  int(0..1) transform_source(string module, string name, string buildid,
			     CommitId latest_checkin)
  {
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

    string full_name = work_dir + "/" + branch + "/" + name + ".tar.gz";

    if (res->exitcode || !file_stat(full_name)) {
      if(!file_stat(full_name))
	write("Could not find %O from %O.\n", full_name, getcwd());
      return 0;
    }

    werror("CWD: %O\n"
	   "full_name: %O\n"
	   "name: %O\n",
	   getcwd(), full_name, name);

    last_name = full_name;

    return 1;
  }
}

int(0..1) transform_source(string module, string name, string buildid,
			   CommitId latest_commit)
{
  if (!client->transform_source(module, name, buildid, latest_commit)) return 0;
  return 1;
}

string make_build_low(Sha1CommitId t)
{
  int buildid = t->create_build_id();
  debug("Build id is %O\n", buildid);

  string name = t->dist_name();
  if (!transform_source(client->module(), name, (string)buildid, t)) {
    persistent_query("UPDATE build SET export='FAIL' WHERE id=%d", buildid);
    return 0;
  }

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
