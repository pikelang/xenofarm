#! /usr/bin/env pike

// $Id: pike_client.pike,v 1.5 2003/05/23 13:48:28 mani Exp $
//
// A Pike implementation of client.sh, intended for Windows use.
// Synchronized with client.sh 1.72.

#define DEBUG
#ifdef DEBUG
#define WERR(X...) werror(X)
#else
#define WERR(X...)
#endif

// --- Global variables

string config_dir = "config/";

mapping(string:string) system;
array(Config) configs = ({});


// --- Utility functions

//! Enhanced exit function that outputs error messages to stderr
//! before exiting, if provided.
//!
//! @int
//!   @value 0
//!     Exited without errors or was stopped by a signal
//!   @value 1
//!     Unsupported argument
//!   @value 2
//!     Client already running
//!   @value 5
//!     dont_run file found
//!   @value 9
//!     Admin email not configured
//!   @value 12
//!     Configuration directory not found
//!   @value 15
//!     Error in configuration file or unknown config format.
//!   @value 16
//!     Unknown parameter in config file.
//! @endint
void exit(int code, void|string why, mixed ... extra) {
  if(!why) predef::exit(code);
  if(code==0)
    write(why, @extra);
  else
    werror(why, @extra);
  clean_exit();
  predef::exit(code);
}

//! Remove the pid file.
void clean_exit() {
  if(!system->node) return;
  rm("xenofarm-"+system->node+".pid");
}

ADT.Stack dirs = ADT.Stack();

//! Put current work directory on a stack and change directory
//! to @[dir].
//! @seealso
//!   @[popd]
void pushd(string dir) {
  dirs->push(getcwd());
  if(!cd(dir)) {
    dirs->pop();
    error("Could not cd into %O\n", dir);
  }
}

//! Return to the previous directory.
//! @seealso
//!   @[pushd]
void popd() {
  if(!sizeof(dirs)) error("Directory stack is empty.\n");
  cd(dirs->pop());
}

//! Returns the data found at @[url].
string web_get(string url) {
  WERR("Fetching %s.\n",url);
  Protocols.HTTP.Query r = Protocols.HTTP.get_url(url);
  if(r->status==200) return r->data();
  if(r->status==302 && r->headers->location)
    return web_get(r->headers->location);
  return 0;
}

//! Returns the posix time when the data at @[url] was
//! last modified.
int web_head(string url) {
  WERR("HEAD %s.\n", url);
  Protocols.HTTP.Query r = Protocols.HTTP.do_method("HEAD", url);

  string date;
  if(r->status==200 && (date=r->headers["last-modified"])) {
    catch {
      return Calendar.ISO.dwim_time(date)->unix_time();
    };
    write("Couldn't decode date %s.\n", date);
    return 0;
  }
  if(r->status==302 && r->headers->location)
    return web_head(r->headers->location);
  return 0;
}


// --- Classes

//! Object representing the content and state of a .cfg file.
class Config {
  string project;
  string projectdir;
  string snapshoturl;
  string resulturl;
  int mindelay;
  array(string) test_order = ({});
  mapping(string:string) tests = ([]);

  //! @[file] is the contents of the @tt{.cfg@} file the object
  //! represents. The @[filename] of the @tt{.cfg@} file can optionally
  //! be provided to create better error messages.
  void create(string file, void|string filename) {
    filename = filename||"unknown file";
    WERR("Creating config object for %s.\n", filename);

    string running_default_tests;

    foreach(file/"\n"; int line_no; string line) {

      // Skip comments.
      if(!sizeof(line) || line[0]=='#') continue;

      string key,value;
      if(sscanf(line, "%s:%*[ \t]%s", key, value)!=3)
        exit(15, "Error in configure file (%s), line %d.\n",
	     filename, line_no);
      value = String.trim_all_whites(value);
      if(value=="")
	exit(15, "Empty value in key %O, line %d, %s.\n",
	     key, line_no, filename);

      if(line==0) {
	if(key!="configformat")
	  exit(15, "Unknown config format in %s.\n", filename);
	if(value!="2")
	  exit(15, "Unknown config format %s in %s.\n", value, filename);
      }

      switch(key) {

      case "project":
      case "projectdir":
      case "snapshoturl":
      case "resulturl":
	this_object()[key]=value;
	break;

      case "mindelay":
	this_object()[key]=(int)value;
	break;

      case "test":
	if(running_default_tests=="false") continue;
	running_default_tests="true";
	if(sscanf(value, "%s%*[ \t]%s", key, value)!=3)
	  exit(15, "Error in configure file (%s), line %d.\n",
	       filename, line_no);
	test_order += ({ key });
	tests[key] = value;
	break;

      case "environment":
	exit(16, "environment: nor supported in config format v2.\n");

      default:
	string node;
	if(sscanf(key, "test-%s", node)==1) {
	  if(running_default_tests=="true") continue;
	  if(node!=system->node) continue;
	  running_default_tests="false";
	  if(sscanf(value, "%s%*[ \t]%s", key, value)!=3)
	    exit(15, "Error in configure file (%s), line %d.\n",
		 filename, line_no);
	  test_order += ({ key });
	  tests[key] = value;
	  break;
	}
	exit(16, "%O is not a supported key.\n", key);
      }
    }

    // Make sure we have all information needed to complete a build
    // cycle.
    if(!project || !projectdir || !snapshoturl ||
       !resulturl || !sizeof(tests))
      exit(15, "Missing information in configure file (%s).\n", filename);

    if(projectdir[-1]!='/') projectdir+="/";
    projectdir += system->node + "/";
  }

  static int last_download;

  int(0..1) prepare() {
    WERR("Preparing %s.\n", project);
    Stdio.mkdirhier(projectdir);
    pushd(projectdir);
    int ret = low_prepare();
    popd();
    return ret;
  }

  int(0..1) low_prepare() {
    if(!last_download) {
      Stdio.Stat st = file_stat("snapshot.tar.gz");
      if(st)
	last_download = st->mtime;
    }
    if(web_head(snapshoturl)<=last_download)
      return 0;

    string data = web_get(snapshoturl);
    if(!data) {
      write("Failed to read from %s\n", snapshoturl);
      return 0;
    }

    Stdio.write_file("snapshot.tar.gz", data);
    rm("snapshot.tar");

    return 1;
  }

  void run_tests() {
    WERR("Running tests in %s.\n", project);
    pushd(projectdir);
    if(!file_stat("snapshot.tar")) {
      WERR("  Unpacking snapshot (gz).\n");
      // We could unpack the file in smaller blocks, but
      // we need to read the entire file below when reading
      // the tar file, so we won't save any memory in reality,
      // only delay its allocation.
      string file = Gz.File("snapshot.tar.gz")->read();
      Stdio.write_file("snapshot.tar", file);
    }

    foreach(tests; string name; string cmd) {
      WERR("  Running test %s.\n", name);
      Stdio.recursive_rm(name);
      mkdir(name);
      pushd(name);
      run_test(name, cmd);
      popd();
    }

    popd();
  }

  void run_test(string name, string cmd) {

    Filesystem.Tar("../snapshot.tar");
    // untar here

    int chdir;
    foreach(get_dir("."), string fn)
      if(Stdio.is_dir(fn) && cd(fn)) {
	chdir=1;
	break;
      }
    if(!chdir) write("fail");

    // create resultdir
    // run cmd
  }

  void debug() {
    foreach(indices(this_object()), string i)
      write("%O:%O\n", i, this_object()[i]);
  }
}


// --- Application level functions

//! Reads all the @tt{.cfg@} files from the @[config_dir],
//! parses its contents and adds a @[Config] object to the
//! @[configs] array.
void read_configs() {
  foreach(get_dir(config_dir), string f) {
    if(!has_suffix(f, ".cfg")) continue;

    // FIXME: Is this correct interpretation of get_nodeconfig()?
    string nodeconfig = config_dir + "/" + f[..sizeof(f)-5] + "." +
      system->node;
    if(stat_file(nodeconfig))
      configs += ({ Config(Stdio.read_file(nodeconfig)) });
    else
      configs += ({ Config(Stdio.read_file(config_dir + "/" +f)) });
  }
}

//! Reads the email, either from the @tt{contact.txt@} file in
//! @[config_dir], or if such a file does not exists, prompt the
//! user for an email. The above mentioned file is created and
//! the email is stored in it.
string get_email() {
  string email="";
  if( file_stat(config_dir + "contact.txt") ) {
    email = Stdio.read_file(config_dir + "contact.txt");
    sscanf(email, "contact: %s\n", email);
    return email;
  }
  Stdio.Readline r = Stdio.Readline();
  write("%-=60s\n",   "Please enter a mail adress where "
	"the project maintainer can reach you.");
  do {
    email = r->edit( email, "Address: ", ({ "bold" }) );
  } while( !email || !has_value(email, "@") );
  Stdio.write_file(config_dir + "contact.txt", "contact: "+email+"\n");
  return email;
}

void setup_system_info() {
  system = uname();
  // Make alias
  system->node = system->nodename;
  system->unames = system->sysname;
  system->unamer = system->release;
  system->unamem = system->machine;
  system->unamev = system->version;

  // FIXME Apply longest_nodename() here.
}

void setup_pidfile() {
  string pidf = "xenofarm-"+system->node+".pid";

  // We should see if the process is still running, but I do not know
  // how under Windows, so for now we always abort if we find a pid-file
  // lying around...
  if(file_stat(pidf))
    exit(2, "Already running xenofarm pid %s.\n", Stdio.read_file(pidf));
  Stdio.write_file(pidf, (string)getpid());
}

//! Remove the pid file when this program object is destructed.
void destroy() {
  clean_exit();
}

int main(int num, array(string) args) {

  // Check cwd for a "dont_run" file, in which case we'll abort.
  if(has_value(get_dir("."), "dont_run"))
    exit(5, "FATAL: dont_run file found. Doing that.\n");

  // We don't trap signals as client.sh do since the Windows signal
  // system doesn't work.

#ifndef __NT__
  setenv("PATH", getenv("PATH")+":/usr/local/bin:/sw/local/bin");
  setenv("LC_ALL","C");
#endif

  // Get user input.
  foreach(Getopt.find_all_options(args, ({
    ({ "config",  Getopt.HAS_ARG, "-c,--config-dir,--configdir"/"," }),
    ({ "help",    Getopt.NO_ARG,  "-h,--help"/","                   }),
    ({ "version", Getopt.NO_ARG,  "-v,--version"/","                }),
    ({ "nolimits",Getopt.NO_ARG,  "--nolimit,--no-limit,--nolimits,--no-limits"/","  }),
  }) ), array opt)
    {
      switch(opt[0]) {
      case "config":
	config_dir = opt[1];
	if(config_dir[-1]!='/') config_dir+="/";
	break;

      case "help":
	exit(0, "Xenofarm client\n\n"
	     "If you encounter problems, see the README for requirements and help.\n\n"
	     "    Arguments:\n\n"
	     "      --config-dir:    Specify an alternate configuration directory.\n"
	     "      --help:          This information.\n"
	     "      --version:       Displays client version.\n");
	break;

      case "version":
	exit(0, "$Id: pike_client.pike,v 1.5 2003/05/23 13:48:28 mani Exp $\n"
	     "Mimics client.sh revision 1.72\n");
	break;

      case "nolimits":
	exit(1, "--no-limits not supported.\n");
	break;
      }
    }

  // FIXME: Check for unknown arguments here.

  if(!file_stat(config_dir))
    exit(12, "Could not open config dir %s\n", config_dir);

  // We don't set up unlimits as client.sh do, since it won't work on Windows.

  string email = get_email();
  WERR("Email: %s\n",email);

  // We don't check multi machine compilation setup since sprsh doesn't run
  // under Windows.

  setup_system_info();
  setup_pidfile();

  // We don't set putname nor compile put, since we are using an internal
  // solution. Nor do we check for the availability of wget or gzip, since
  // we use internal solutions there too. The Pike however needs to be compiled
  // with gz, but we'll get a compilation error while trying to start this
  // program if that is not the case.

  read_configs();
  while(1) {
    foreach(configs, Config config) {
      if(config->prepare())
	config->run_tests();
    }
    sleep(5*60);
  }
}
