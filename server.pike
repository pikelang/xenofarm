#! /usr/bin/env pike

// Xenofarm server
// By Martin Nilsson
// Made useable on its own by Per Cederqvist
// $Id: server.pike,v 1.56 2009/03/07 13:12:38 grubba Exp $

Sql.Sql xfdb;

constant checkin_state_file = "state/checkin.timestamp";

int min_build_distance = 60*60*2;
int fail_build_divisor = 2*6;
int checkin_poll = 60;
int checkin_latency = 60*5;

string project;
string web_dir;		// --web-dir
string repository;	// --repository
string cvs_module;	// --cvs-module
string svn_module;	// --svn-module
string branch;		// --branch
string tag_format;	// --tag
string work_dir;	// --work-dir
string source_transformer;
array(string) update_opts = ({});

int(0..1) verbose;
string latest_state="FAIL";

int(0..1) keep_going = 1;

class CommitId
{
  int unix_time();
  int unix_time_available();
  int create_build_id();
  int build_needed(CommitId new_commit);
  int pending_latency();

  string dist_name()
  {
    object at = Calendar.ISO_UTC.Second("unix", unix_time());
    return sprintf("%s-%s-%s", project,
                  at->format_ymd_short(),
                  at->format_tod_short());
  }
}

class TimeStampCommitId
{
  inherit CommitId;

  int timestamp;

  void create(int timestamp)
  {
    this->timestamp = timestamp;
  }

  int unix_time()
  {
    return timestamp;
  }

  int unix_time_available()
  {
    return true;
  }

  int build_needed(CommitId new_commit)
  {
    return new_commit->unix_time() > unix_time();
  }

  int pending_latency()
  {
    int rv = unix_time() + checkin_latency - time();
    if(rv < 0)
      rv = 0;
    return rv;
  }

  int create_build_id()
  {
    persistent_query("INSERT INTO build (time, export, project, branch) "
                    "VALUES (%d, 'PASS', %s, %s)",
                    unix_time(), project, branch);
    int buildid;
    mixed err = catch {
       buildid = (int)xfdb->query("SELECT LAST_INSERT_ID() AS id")[0]->id;
      };
    if(err) {
      catch(xfdb->query("DELETE FROM build "
                       "WHERE project=%s AND branch=%s AND time=%d",
                       project, branch, unix_time()));
      return 0;
    }
    return buildid;
  }
}

string last_sha1_seen = 0;
int last_sha1_first_seen = 0;
class Sha1CommitId
{
  inherit CommitId;

  string commit_id;
  int build_time;

  void create(string commit_id,
	      int build_time)
  {
    this->commit_id = commit_id;
    this->build_time = build_time;
    if(!build_time && last_sha1_seen != commit_id)
      {
	last_sha1_seen = commit_id;
	last_sha1_first_seen = time();
      }
  }

  int unix_time()
  {
    if( !build_time )
      error("build_time not yet set on Git commit %s\n", commit_id);
    return build_time;
  }

  int unix_time_available()
  {
    return !!build_time;
  }

  int build_needed(CommitId new_commit)
  {
    return new_commit->commit_id != commit_id;
  }

  int pending_latency()
  {
    if(last_sha1_seen == commit_id)
      {
	int rv = last_sha1_first_seen + checkin_latency - time();
	if(rv < 0)
	  rv = 0;
	return rv;
      }
    // This should never happen.
    debug("Commits all mixed up; no latency (%s != %s).\n",
	  commit_id, last_sha1_seen);
    return 0;
  }

  int create_build_id()
  {
    if(build_time == 0)
      build_time = time();

    persistent_query("INSERT INTO build\n"
		     "SET time = %d, export='PASS', commit_id = %s,\n"
		     "    project = %s, branch = %s",
		     unix_time(), commit_id, project, branch);
    int buildid;
    mixed err = catch {
	buildid = (int)xfdb->query("SELECT LAST_INSERT_ID() AS id")[0]->id;
      };
    if(err) {
      catch(xfdb->query("DELETE FROM build\n"
			"WHERE project=%s AND branch=%s\n"
			"      AND time=%d AND commit_id=%s",
			project, branch, unix_time(), commit_id));
      return 0;
    }
    return buildid;
  }
}

//
// Repository classes
//
string client_type;
class RepositoryClient {

  // Returns the posix time when the latest checkin was committed.
  CommitId get_latest_checkin();

  // This method gets called when the local source tree should
  // be updated.
  void update_source(CommitId commit_id);

  // A string with descriptions of the special arguments this repository
  // client accepts.
  constant arguments = "";

  // This method is called during startup and is fed the command line
  // arguments for parsing.
  void parse_arguments(array(string));

  // Should return the name of the repository module.
  string module();

  // Should return the name of the repository client.
  string name();
}

// Base class for version control systems that cannot check out the
// code as it was at a certain time.  This class instead performs a
// full checkout in get_latest_checkin() and returns the current time,
// and update_source essentially becomes a no-op or a call to
// get_latest_checkin().
class FakeTimeClient {
  inherit RepositoryClient;

  static int latest_checkin;

  // The get_latest_checkin function should return the (UTC) unixtime of
  // the latest check in. This version actually returns the time we last
  // detected that something has been checked in. That is good enough.
  TimeStampCommitId get_latest_checkin()
  {
    check_work_dir();
    Calendar.TimeRange now = Calendar.Second();
    array(string) log = update_to_current_source();
    latest_checkin = (int)Stdio.read_file(checkin_state_file);
    latest_checkin = time_of_change(log, checkin_state_file,
				    latest_checkin, now);
    return TimeStampCommitId(latest_checkin);
  }

  int time_of_change(array(string) log,
		     string checkin_state_file,
		     int latest_checkin,
		     Calendar.TimeRange now)
  {
    if(sizeof(log))
    {
      debug("Something changed: \n  %s", log * "\n  " + "\n");
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
	debug("No check in timestamp found; assuming something changed.\n");
	latest_checkin = now->unix_time();
	Stdio.write_file(checkin_state_file, latest_checkin + "\n");
    }

    return latest_checkin;
  }

  void update_source(TimeStampCommitId when) {
    if(!latest_checkin || when->unix_time() > latest_checkin)
      get_latest_checkin();
  }

  // Check that we have a working copy of the source tree.  Do exit(1)
  // otherwise.
  void check_work_dir();

  // Do "cvs update" or the corresponding command.  Return a non-empty
  // log file if anything changed.
  array(string) update_to_current_source();
}

class CVSClient {
  inherit FakeTimeClient;
  constant arguments =
  "\nCVS specific arguments:\n\n"
  "--cvs-module   The CVS module the server should use.\n"
  "--update-opts  CVS options to append to \"cvs -q update\".\n"
  "               Default: \"-d\". \"--update-opts=-Pd\" also makes sense.\n"
  "--repository   The CVS repository the server should use.\n";

  void parse_arguments(array(string) args) { }

  string module() {
    return cvs_module;
  }

  string name() {
    return "CVS";
  }

  void check_work_dir()
  {
    if(!file_stat(cvs_module) || !file_stat(cvs_module)->isdir) {
      write("Please check out %O inside %O and re-run this script.\n", 
	    cvs_module, work_dir);
      exit(1);
    }
  }

  array(string) update_to_current_source()
  {
    debug("Running cvs update.\n");
    set_status("Running cvs update.");
    object update =
      Process.create_process(({ "cvs", "-q", "update",
				@update_opts }),
			     ([ "cwd"    : cvs_module,
				"stdout" : Stdio.File("tmp/update.log", "cwt"),
				"stderr" : Stdio.File("/dev/null", "cwt") ]));
    if(update->wait())
    {
	write("Failed to update CVS module %O in %O.\n", cvs_module, getcwd());
	exit(1);
    }

    return filter(Stdio.read_file("tmp/update.log") / "\n" - ({ "" }),
		  lambda(string row) { return !has_prefix(row, "? "); });
  }
}

class GitClient {
  inherit RepositoryClient;
  constant arguments =
    "\nGit specific arguments:\n\n"
    "--branch       The branch of the repository to monitor.\n";

  void parse_arguments(array(string) args) {
    foreach(Getopt.find_all_options(args, ({
      ({ "branch",  Getopt.HAS_ARG, "--branch" }),}) ),array opt)
      {
	switch(opt[0])
	{
	  case "branch":
	    branch = opt[1];
	    break;
	}
      }
  }

  string module() {
    return branch;
  }

  string name() {
    return "Git";
  }

  string current_commit_id()
  {
    Stdio.File stdout = Stdio.File();

    object stat =
      Process.create_process(({ "git", "rev-parse", "HEAD" }),
			     ([ "stdout" : stdout.pipe(),
				"stderr" : Stdio.File("/dev/null", "cwt") ]));
    if(stat->wait())
    {
      write("Failed to stat Git branch %O in %O.\n",
	    branch||"HEAD", getcwd());
      exit(1);
    }

    return String.trim_all_whites(stdout.read());
  }

  Sha1CommitId get_latest_checkin()
  {
    check_work_dir();
    update_to_current_source();
    return Sha1CommitId(current_commit_id(), 0);
  }

  void check_work_dir()
  {
    if(!file_stat(".git") || !file_stat(".git")->isdir) {
      write("Please clone %O to the %O directory and re-run this script.\n", 
	    project, work_dir);
      exit(1);
    }
  }

  int working_on_a_branch()
  {
    object symref =
      Process.create_process( ({ "git", "symbolic-ref", "-q", "HEAD" }),
			      ([ "stdout": Stdio.File("/dev/null", "cwt") ]) );
    switch( symref->wait() )
      {
      case 0:
	return 1;
      case 1:
	return 0;
      default:
	write("Failed to run git symbolic-ref.\n");
	exit(1);
      }
  }

  array(string) update_to_current_source()
  {
    // If the latest update_source() put us on a detached head, move
    // back to the branch we came from.
    if( !working_on_a_branch() )
      checkout("@{-1}");

    string before = current_commit_id();

    debug("Running git pull.\n");
    set_status("Running git pull.");
    object update =
      Process.create_process(({ "git", "pull", "-q" }),
			     ([ "stdout" : Stdio.File("tmp/update.log", "cwt"),
				"stderr" : Stdio.File("/dev/null", "cwt") ]));
    if(update->wait())
    {
      write("Failed to update Git in %O for project %O.\n", getcwd(), project);
      exit(1);
    }

    string after = current_commit_id();

    array(string) log_lines = ({ });

    if( after != before )
    {
      object log =
          Process.create_process(
              ({ "git", "log", before + ".." + after }),
              ([ "stdout": Stdio.File("tmp/log.log", "cwt")]));
      if(log->wait())
      {
        write("Failed to get Git log in %O for project %O.\n",
              getcwd(), project);
        exit(1);
      }
      log_lines = Stdio.read_file("tmp/log.log") / "\n";
    }
    return log_lines;
  }

  void checkout(string commit_id)
  {
    object stat =
      Process.create_process(({ "git", "checkout", commit_id }),
			     ([ "stdout" : Stdio.File("tmp/co.log", "cwt"),
				"stderr" : Stdio.File("/dev/null", "cwt") ]));
    if(stat->wait())
    {
      write("Failed to check out %O.\n", commit_id);
      exit(1);
    }
  }

  void update_source(Sha1CommitId commit_id)
  {
    // Shortcut for the common case that we already have the requested
    // version.
    if(current_commit_id() == commit_id->commit_id)
      return;

    checkout(commit_id->commit_id);

    if(current_commit_id() == commit_id->commit_id)
      return;

    write("FATAL: Failed to update tree to %s: got %s.\n",
	  commit_id->commit_id, current_commit_id());
    exit(1);
  }

  void tag_source(int buildno) {
    debug("Running git tag.\n");
    string commit_id = current_commit_id();
    object tag =
      Process.create_process(({ "git", "tag",
				sprintf(tag_format, buildno),
				commit_id }),
			     ([ "stdout" : Stdio.File("tmp/tag.log", "cwt"),
				"stderr" : Stdio.File("/dev/null", "cwt") ]));
    if(tag->wait())
    {
      write("Failed to tag Git commit %O as %O on branch %O in %O.\n",
	    commit_id, sprintf(tag_format, buildno), branch||"HEAD", getcwd());
      exit(1);
    }
    
    // FIXME: Optional push of the tag?
  }
}

class SVNClient {
  inherit FakeTimeClient;
  constant arguments =
  "\nSVN specific arguments:\n\n"
  "--svn-module   The Subversion module the server should use.\n";

  void parse_arguments(array(string) args) {
    foreach(Getopt.find_all_options(args, ({
      ({ "svn_module",  Getopt.HAS_ARG, "--svn-module" }),}) ),array opt)
      {
	switch(opt[0])
	{
	  case "svn_module":
	    svn_module = opt[1];
	    break;
	}
      }
  }

  string module() {
    return svn_module;
  }

  string name() {
    return "SVN";
  }

  void check_work_dir()
  {
    if(!file_stat(svn_module) || !file_stat(svn_module)->isdir) {
      write("Please check out %O inside %O and re-run this script.\n", 
	    svn_module, work_dir);
      exit(1);
    }
  }

  array(string) update_to_current_source()
  {
    debug("Running svn update.\n");
    set_status("Running svn update.");
    object update =
      Process.create_process(({ "svn", "update" }),
			     ([ "cwd"    : svn_module,
				"stdout" : Stdio.File("tmp/update.log", "cwt"),
				"stderr" : Stdio.File("/dev/null", "cwt") ]));
    if(update->wait())
    {
	write("Failed to update SVN module %O in %O.\n", svn_module, getcwd());
	exit(1);
    }

    return filter(Stdio.read_file("tmp/update.log") / "\n" - ({ "" }),
		  lambda(string row) {
		    return !(has_prefix(row, "? ")
			     ||has_prefix(row, "At revision"));
		  });
  }
}

class StarTeamClient {
  inherit FakeTimeClient;

  string st_module;
  string st_project;
  string st_pwdfile;

  constant arguments =
  "\nStarteam specific arguments:\n\n"
  "--st-module    basename of dir where contents of the view folder will reside.\n"
  "               Similar to the cvs-module option for the CVS client.\n"
  "--st-project   username:password@host:port/project/view/folder/\n"
  "--st-pwdfile   password filename\n";

  void parse_arguments(array(string) args) {
    foreach(Getopt.find_all_options(args, ({
      ({ "st_module",   Getopt.HAS_ARG, "--st-module" }),
      ({ "st_project",  Getopt.HAS_ARG, "--st-project" }),
      ({ "st_pwdfile",  Getopt.HAS_ARG, "--st-pwdfile" }),}) ),array opt)
      {
	switch(opt[0])
	{
	  case "st_module":
	    st_module = opt[1];
	    break;
	  case "st_project":
	    st_project = opt[1];
	    break;
	  case "st_pwdfile":
	    st_pwdfile = opt[1];
	    break;
	}
      }
  }

  string module() {
    return st_module;
  }

  string name() {
    return "StarTeam";
  }

  void check_work_dir()
  {
    //check out into work-dir/st_module
    if(!file_stat(module()) || !file_stat(module())->isdir) {
      write("Please check out %O inside %O and re-run this script.\n", 
	    module(), work_dir);
      exit(1);
    }
  }

  array(string) update_to_current_source()
  {
    debug("Running stcmd co.\n");
    set_status("Running stcmd co.");
    object update =
      Process.create_process(({ "stcmd", "co", "-nologo", "-is", "-p",
				st_project, "-pwdfile", st_pwdfile, "-fp",
				work_dir + "/" + module() }),
			     ([ "cwd"    : module(),
				"stdout" : Stdio.File("tmp/update.log", "cwt"),
				"stderr" : Stdio.File("tmp/update.err", "cwt")
			     ]));
    debug("Ran stcmd co -nologo -is -p " + st_project + " -pwdfile " +
	  st_pwdfile  + " -fp " + work_dir + "/" + module() + "\n");
    if(update->wait())
    {
	write("Failed to check out module %O in %O.\n", module(), getcwd());
	exit(1);
    }

    return filter(Stdio.read_file("tmp/update.log") / "\n" - ({ "" }),
		  lambda(string row) {
		    return has_suffix(row, ": checked out");});
  }
}

class CustomClient {
  inherit FakeTimeClient;

  string custom_module;
  string prog;

  constant arguments =
  "\nCustom client specific arguments:\n\n"
  "--custom_module module argument passed to custom program.\n"
  "--program the custom program to run.\n"
  "(the custom prg will also be passed -D <time>, like CVS)\n";

  void parse_arguments(array(string) args) {
    foreach(Getopt.find_all_options(args, ({
      ({ "module",   Getopt.HAS_ARG, "--custom_module" }),
      ({ "program",   Getopt.HAS_ARG, "--program" }), }) ),array opt)
      {
        switch(opt[0])
        {
          case "module":
            custom_module = opt[1];
            break;
        }
        switch(opt[0])
        {
          case "program":
            prog = opt[1];
            break;
        }
      }
  }

  string module() {
    return custom_module;
  }

  string name() {
    return "Custom";
  }

  void check_work_dir()
  {
    // We assume that the user knows what he is doing, so no checks here.
  }

  array(string) update_to_current_source()
  {
    debug("Running custom client.\n");
    Calendar.TimeRange now = Calendar.Second();
    array cmd = ({ prog, "-D", now->format_time(), custom_module });
    object update =
	Process.create_process( cmd,
			     ([ "cwd"    : work_dir,
				"stdout" : Stdio.File("tmp/update.log", "cwt"),
				"stderr" : Stdio.File("/dev/null", "cwt") ]));
    string actual_command = sprintf("'%s'", cmd * "' '");
    debug("Running custom checker %s\n", actual_command);
    set_status("Running custom checker " + actual_command + ".");
    if(update->wait())
    {
	write("Failed to check for updates using: '%s'.\n", actual_command);
	exit(1);
    }
    write("Checked for updates.\n");
    return Stdio.read_file("tmp/update.log")/"\n"  - ({ "" });
  }
}

RepositoryClient client;

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
	  debug("(%s)\n", err[0][..sizeof(err[0])-2]);
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
CommitId get_latest_build()
{
  array res = persistent_query("SELECT time AS latest_build,\n"
			       "  export, commit_id\n"
			       "FROM build\n"
			       "WHERE project = %s AND branch = %s\n"
			       "ORDER BY time DESC LIMIT 1",
			       project, branch);
  if(!res || !sizeof(res))
    return 0;
  latest_state = res[0]->export;
  int ts = (int)(res[0]->latest_build);
  if( res[0]->commit_id )
    return Sha1CommitId(res[0]->commit_id, ts);
  else
    return TimeStampCommitId(ts);
}

// Return true on success, false on error.
int(0..1) transform_source(string module, string name, string buildid) {
  if(source_transformer) {
    if(Process.create_process( ({ source_transformer, module, name, buildid }),
			       ([]) )->wait() ) {
      write(source_transformer+" failed\n");
      return 0;
    }
  } 
  else {
    string stamp = module+"/buildid.txt";
    if(file_stat(stamp)) {
      write(stamp+" exists!\n");
      exit(1);
    }
    Stdio.write_file(stamp, buildid+"\n");
    if(Process.create_process( ({ "tar", "cf", name+".tar", module }),
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

string make_build_low(CommitId latest_checkin)
{
  int buildid = latest_checkin->create_build_id();
  string name = latest_checkin->dist_name();

  if (tag_format && client->tag_source) {
    // FIXME: Consider formatting the tag label here
    //        instead of in the tag_source() function.
    set_status("Tagging the source code.");
    client->tag_source(buildid);
  }

  set_status("Creating source code dist.");
  if (!transform_source(client->module(), name, (string)buildid)) {
    persistent_query("UPDATE build SET export='FAIL' WHERE id=%d", buildid);
    return 0;
  }

  return name+".tar.gz";
}

void make_build(CommitId timestamp)
{
  debug("Making new build.\n");

  set_status("Updating the source tree.");
  client->update_source(timestamp);
  string build_name = make_build_low(timestamp);
  if(!build_name) {
    write("No source distribution was created by make_build_low...\n");
    return;
  }
  debug("The source distribution %s assembled.\n", build_name);

  string fn = (build_name/"/")[-1];

  if(Process.create_process( ({ "mv", build_name, web_dir+fn }) )->wait()) {
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

  if(!client->module()) {
    write("No client module selected.\n");
    exit(1);
  }

  // FIXME: Check CVSROOT?

  if(!project) {
    write("No project set.\n");
    exit(1);
  }

  if (tag_format && !client->tag_source) {
    write("Tagging not supported with the %s client.\n", client->name());
    exit(1);
  }

  if(verbose) {
    write("Client:    : %s\n", client->name());
    write("Database   : %s\n", xfdb->host_info());
    write("Project    : %s\n", project);
    write("Module     : %s\n", client->module());
    write("Repository : %s\n", repository||"(implicit)");
    write("Work dir   : %s\n", work_dir);
    write("Web dir    : %s\n", web_dir);
    write("\n");
  }
}

RepositoryClient get_client()
{
  switch(client_type)
  {
  case "starteam":
    return StarTeamClient();
  case "cvs":
    return CVSClient();
  case "git":
    return GitClient();
  case "svn":
    return SVNClient();
  case "custom":
    return CustomClient();
  default:
    return CVSClient();
  }
}


void set_status(string intent, void|int when)
{
  if( when )
    intent = sprintf(intent, Calendar.Second(time() + when)->format_time());

  array res = persistent_query("SELECT count(*) AS count"
			       " FROM server_status"
			       " WHERE project = %s AND branch = %s",
			       project, branch);
  if( (int)res[0]->count > 0 )
    xfdb->query("UPDATE server_status"
		" SET updated = NOW(), message = %s"
		" WHERE project = %s AND branch = %s",
		intent, project, branch);
  else
    xfdb->query("INSERT INTO server_status (project, branch, updated, message)"
		" VALUES (%s, %s, NOW(), %s)",
		project, branch, intent);
}


void got_termination_request(int sig)
{
  keep_going = 0;
  debug("Initiating a clean shutdown.  This can take some time...\n");
}

int main(int num, array(string) args)
{
  write(prog_id);
  int (0..1) force_build;
  int (0..1) once_only = 0;

  foreach(Getopt.find_all_options(args, ({
    ({ "client_type", Getopt.HAS_ARG, "--client-type"  }),
    ({ "db",          Getopt.HAS_ARG, "--db"           }),
    ({ "distance",    Getopt.HAS_ARG, "--min-distance" }),
    ({ "force",       Getopt.NO_ARG,  "--force"        }),
    ({ "help",        Getopt.NO_ARG,  "--help"         }),
    ({ "latency",     Getopt.HAS_ARG, "--latency"      }),
    ({ "module",      Getopt.HAS_ARG, "--cvs-module"   }),
    ({ "once",        Getopt.NO_ARG,  "--once"         }),
    ({ "poll",        Getopt.HAS_ARG, "--poll"         }),
    ({ "repository",  Getopt.HAS_ARG, "--repository"   }),
    ({ "tag",         Getopt.HAS_ARG, "--tag"          }),
    ({ "verbose",     Getopt.NO_ARG,  "--verbose"      }),
    ({ "webdir",      Getopt.HAS_ARG, "--web-dir"      }),
    ({ "workdir",     Getopt.HAS_ARG, "--work-dir"     }),
    ({ "transformer", Getopt.HAS_ARG, "--transformer" }),
    ({ "updateopts",  Getopt.HAS_ARG, "--update-opts" }),
  }) ),array opt)
    {
      switch(opt[0])
      {
      case "client_type":
	client_type = opt[1];
	break;

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
	foreach(glob("*Client", indices(this)), string pn)
	  write( this[pn]->arguments );
	write("\n");
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

      case "tag":
	tag_format = opt[1];
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

  client = get_client();

  client->parse_arguments(args);
  args -= ({ 0 });

  if(sizeof(args)>1) {
    project = args[1];
  }

  check_settings();

  signal(signum("TERM"), got_termination_request);
  signal(signum("INT"), got_termination_request);

  if(force_build)
  {
    set_status("Making a forced build.");
    make_build(client->get_latest_checkin());
    set_status("Exiting.");
    exit(0);
  }

  set_status("Starting up...");
  CommitId latest_build = get_latest_build();
  if(latest_build)
    debug("Latest build was %s ago.\n",
          fmt_time(time()-latest_build->unix_time()));
  else
    debug("No previous builds found.\n");

  int sleep_for;
  int(0..1) sit_quietly;
  while(keep_going)
  {
    int delta;
    if(latest_build)
      delta = time() - latest_build->unix_time();
    else
      {
	debug("First build. No quarantine.\n");
	delta = min_build_distance;
      }

    int min_distance = min_build_distance;

    if (latest_state == "FAIL") min_distance /= fail_build_divisor;

    if(delta < min_distance) // Enforce minimum time between builds
    {
      sleep_for = min_distance - delta;
      debug("Enforcing minimum build distance. Quarantine left: %s.\n",
	    fmt_time(sleep_for));
      sit_quietly = 0;
      set_status("Waiting until %s to enforce build distance.", sleep_for);
    }
    else // After the next commit + inactivity cycle it's time for a new build
    {
      CommitId latest_checkin = client->get_latest_checkin();
      if(!latest_checkin && !keep_going)
	break;

      if(!sit_quietly) {
	if(!latest_checkin)
	  debug("No checkin available\n");
	else if(latest_checkin->unix_time_available()) {
	  debug("Latest check in was %s ago.\n",
		fmt_time(time() - latest_checkin->unix_time()));
	} else {
	  debug("Latest commit was %s.\n", latest_checkin->commit_id);
	}
	sit_quietly = 1;
      }
      if(latest_checkin &&
	 (latest_build ? latest_build->build_needed(latest_checkin) : 1))
      {
	sleep_for = latest_checkin->pending_latency();
	if(sleep_for == 0)
	{
	  make_build(latest_checkin);
	  latest_build = get_latest_build();
	}
	else // Enforce minimum time of inactivity after a commit
	{
	  set_status("Will create new build at %s unless new commits found.",
		     sleep_for);
	  debug("A new build is scheduled to run in %s.\n",
		fmt_time(sleep_for));
	}
	sit_quietly = 0;
      }
      else // Polling for the first post-build-quarantine commit
      {
	sit_quietly = 1; // until something happens in the repository
	sleep_for = checkin_poll; // poll frequency
	set_status("Idle; waiting for new commits.");
      }
    }

    if (once_only)
	return 0;

    if(!sit_quietly)
      debug("Sleeping for %d seconds...\n", sleep_for);
    sleep(sleep_for, 1);

    // This sleep(0) is here to enforce Pike running the signal
    // handler got_term() before it evaluates the while loop
    // condition.  Without this, if the sleep is interrupted, Pike
    // would still run the loop one more time.
    sleep(0);
  }

  set_status("Server stopped.");
}

constant prog_id = "Xenofarm generic server\n"
"$Id: server.pike,v 1.56 2009/03/07 13:12:38 grubba Exp $\n";
constant prog_doc = #"
server.pike <arguments> <project>
Where the arguments db, cvs-module, web-dir and work-dir are
mandatory and the project is the name of the project.
Possible arguments:

--client-type  The repository client to use, \"cvs\", \"git\", \"svn\",
               \"starteam\" or \"custom\". Defaults to \"cvs\".
--db           The database URL, e.g. mysql://localhost/xenofarm.
--force        Make a new build and exit.
--help         Displays this text.
--latency      The enforced latency between the latest check in and
               when the next build is run. Defaults to 300 seconds
               (5 minutes).
--min-distance The enforced minimum distance between to builds.
               Defaults to 7200 seconds (two hours).
--once         Run just once.
--poll         How often the the repository client is queried for new check ins.
               Defaults to every 60 seconds.
--tag          Tag the builds.
--transformer  Program that builds the source package (see README).
--verbose      Send messages about everything that happens to stdout.
--web-dir      Where the outgoing build packages should be put.
--work-dir     Where temporary files should be put.
";
