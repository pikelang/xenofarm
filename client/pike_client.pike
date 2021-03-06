#! /usr/bin/env pike

// A Pike implementation of client.sh, intended for Windows use.
// Synchronized with client.sh 1.73.

constant VERSION = "1.3";

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
//!   @value 31
//!     Other error.
//! @endint
void exit(int code, void|string why, mixed ... extra) {
  if(!why) predef::exit(code);
  if(code==0)
    write(why, @extra);
  else
    werror(why, @extra);
  predef::exit(code);
}

#ifdef PID_FILE
//! Remove the pid file.
void clean_exit() {
  if(!system->node) return;
  rm("xenofarm-"+system->node+".pid");
}
#endif /* PID_FILE */

ADT.Stack dirs = ADT.Stack();

//! Put current work directory on a stack and change directory
//! to @[dir].
//! @seealso
//!   @[popd]
int(1..1) pushd(string dir) {
  dirs->push(getcwd());
  if(!cd(dir)) {
    dirs->pop();
    error("Could not cd into %O\n", dir);
  }
  return 1;
}

//! Return to the previous directory.
//! @seealso
//!   @[pushd]
void popd() {
  if(!sizeof(dirs)) error("Directory stack is empty.\n");
  cd(dirs->pop());
}

//! Returns the data found at @[url].
array(string|int) web_get(string url) {
  WERR("Fetching %s.\n",url);
  Protocols.HTTP.Query r = Protocols.HTTP.get_url(url);
  if(!r)
    error("Failed to connect to %O.\n", url);
  if(r->status==200) {
    int t;
    mixed err = catch {
      t=Calendar.ISO.dwim_time(r->headers["last-modified"])->unix_time();
    };
    if(err)
      werror("Failed to decode timestamp %O.\n%s\n",
	     r->headers["last-modified"], describe_backtrace(err));
    return ({ r->data(), t });
  }
  if(r->status==302 && r->headers->location)
    return web_get(r->headers->location);
  return ({ 0, 0 });
}

//! Returns the posix time when the data at @[url] was
//! last modified.
int web_head(string url) {
  WERR("HEAD %s. ", url);
  Protocols.HTTP.Query r = Protocols.HTTP.do_method("HEAD", url);
  WERR("done\n");

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

//! Untars the the tar file system @[fs]. @[dir] is the current
//! working directory inside the tar file system.
void untar_dir(string fn) {
  WERR("  Reading tar file %O.", fn);
  object fs = Filesystem.Tar(fn);
  untar_dir_low(fs);
  WERR("\n");
  fs->tar->fd->close();
}

void untar_dir_low(object fs) {
  WERR(".");
  foreach(fs->get_dir(), string path) {
    string fn = (path/"/")[-1];
    if(fs->stat(path)->isdir()) {
      if(!mkdir(fn))
	exit(31, "Unable to create directory %O.\n", fn);
      pushd(fn);
      untar_dir_low(fs->cd(fn));
      popd();
    }
    else {
      Stdio.write_file(fn, fs->open(fn, "r")->read());
#if constant(System.utime)
      System.utime(fn, fs->stat(fn)->atime, fs->stat(fn)->mtime);
#endif
    }
  }
}

// Pads the string @[in] with "\0" characters to the length @[size].
string zero_pad(string in, int size) {
  if(sizeof(in)>size) error("In-string is too big.\n");
  return in+"\0"*(size-sizeof(in));
}

//! Creates a tar file of the current directory and writes to @[fn].
//! If @[avoid] is given, the file with that name will not be added to
//! the tar package. @[tar_dir] doesn't recurse into subdirectories.
void tar_dir(string fn, void|string avoid) {
  Stdio.File out = Stdio.File(fn, "cwt");
  foreach(get_dir("."), string fn) {

    if(fn==avoid) continue;

    string head = "";
    head += zero_pad(fn,100); // Filename
    Stdio.Stat st=file_stat(fn);
    head += sprintf("%07o\0", st->mode); // mode
    head += sprintf("%07o\0", st->uid); // uid
    head += sprintf("%07o\0", st->gid); // gid
    head += sprintf("%011o\0", st->size); // size
    head += sprintf("%011o\0", st->mtime); // mtime
    head += "        "; // checksum placeholder
    head += "0"; // typeflag
    head += zero_pad("",100); // linkname
    head += "ustar\0"; // magic
    head += "00"; // version

    // uname
#if constant(getpwuid)
    if(getpwuid(st->uid))
      head += zero_pad(getpwuid(st->uid)[0], 32);
    else
#endif
      head += zero_pad("xenofarm", 32);

    // gname
#if constant(getgrgid)
    if(getgrgid(st->gid))
      head += zero_pad(getgrgid(st->gid)[0], 32);
    else
#endif
      head += zero_pad("xenofarm", 32);

    head += zero_pad("", 8); // devmajor
    head += zero_pad("", 8); // devminor
    head += zero_pad("", 155); // prefix

    // Replace checksum placeholder with actual checksum.
    int chksum = Array.sum((array)head);
    head = head[..147]+sprintf("%06o\0", chksum)+head[155..];

    out->write(head);
    out->write("\0"*12); // Pad header to blocksize
    out->write(Stdio.read_file(fn));
    out->write("\0"*( 512-(512+st->size)%512 )); // Pad content to blocksize
  }
  out->write("\0"*512); // End of Archive
  out->write("\0"*( 10240-(10240+out->tell())%10240 )); // Pad to 10240 blocks
  out->close();
}

//! Uncompresses the gz file @[path_a] into the file @[path_b].
void gunzip(string path_a, string path_b) {
  Gz.File a = Gz.File(path_a);
  Stdio.File b = Stdio.File(path_b, "cwt");
  string buf;
  do {
    WERR(".");
    buf = a->read(1<<17);
    b->write(buf);
  } while( sizeof(buf)==1<<17 );
  WERR("\n");
}


// --- Classes

//! Object representing the content and state of a .cfg file.
class Config {
  string project;
  string projectdir;
  string snapshoturl;
  string resulturl;
  int mindelay;
  mapping environment = ([]);
  array(string) test_order = ({});
  mapping(string:string) tests = ([]);

  //! @[file] is the contents of the @tt{.cfg@} file the object
  //! represents. The @[filename] of the @tt{.cfg@} file can optionally
  //! be provided to create better error messages.
  void create(string file, void|string filename) {
    filename = filename||"unknown file";
    WERR("Creating config object for %s.\n", filename);

    int format;
    string running_default_tests;

    foreach(file/"\n"; int line_no; string line) {

      // Skip comments.
      if(!sizeof(line) || line[0]=='#') continue;

      // Parse key and value pair.
      string key,value;
      if(sscanf(line, "%s:%*[ \t]%s", key, value)!=3)
        exit(15, "Error in configure file (%s), line %d.\n",
	     filename, line_no);
      value = String.trim_all_whites(value);
      if(value=="")
	exit(15, "Empty value in key %O, line %d, %s.\n",
	     key, line_no, filename);

      // First line must be a configformat key with value 2.
      if(line_no==0) {
	if(key!="configformat")
	  exit(15, "Unknown config format in %s.\n", filename);
	if( !(< "2", "3" >)[value] )
	  exit(15, "Unknown config format %s in %s.\n", value, filename);
	format = (int)value;
	continue;
      }

      // Set things according to keys.
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
	// This key is new in v3.
	if(format<3)
	  exit(16, "environment: not supported in config format v%d.\n",
	       format);
	if(sizeof(tests))
	  exit(16, "environment statement after test statement.\n");
	sscanf(value, "%s=%s", string ekey, string evalue);
	if(!ekey || !evalue || !sizeof(ekey))
	  exit(16, "error in environment: %O.\n", value);
	environment[ekey] = evalue;
	break;

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
	exit(16, "%O is not a supported key (line %d).\n", key, line_no);
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

  static int last_serverchange;
  static int last_download;

  // Creates a project directory, enters it, calls low_prepare and
  // leaves the directory.
  int(0..1) prepare() {
    if(file_stat("dont_run"))
      exit(5, "FATAL: dont_run file found. Doing that.\n");

    WERR("Preparing %s.\n", project);
    Stdio.mkdirhier(projectdir);
    pushd(projectdir);
    int ret = low_prepare();
    popd();
    return ret;
  }

  // Compares last downloaded package with what resides on the server.
  // If the server has a newer version, it is downloaded.
  int(0..1) low_prepare() {
    // This is an improvement over client.sh.
    if(file_stat("dont_run"))
      exit(5, "FATAL: dont_run file found. Doing that.\n");

    if(!last_download) {
      string dlfile = Stdio.read_file("localtime_lastdl");
      if(dlfile)
	sscanf(dlfile, "servertime:%d\nlocaltime:%d",
	       last_serverchange, last_download);
    }
    if(last_serverchange && web_head(snapshoturl)<=last_serverchange)
      return 0;

    string data;
    int t;
    [ data, t ] = web_get(snapshoturl);
    if(!data) {
      write("Failed to read from %s\n", snapshoturl);
      return 0;
    }
    WERR("Writing data to disk.\n");
    last_serverchange = t;
    last_download = time();

    Stdio.write_file("snapshot.tar.gz", data);
    Stdio.write_file("localtime_lastdl",
		     "servertime:"+last_serverchange+
		     "\nlocaltime:"+last_download+"\n");
    rm("snapshot.tar");
    foreach(get_dir("."), string fn)
      if(Stdio.is_dir(fn)) Stdio.recursive_rm(fn);

    return 1;
  }

  // Decompresses the gz package, iterates over all tests and
  // calls run_test for each of them.
  void run_tests() {
    WERR("Running tests in %s.\n", project);
    pushd(projectdir);
    if(!file_stat("snapshot.tar")) {
      WERR("  Uncompressing archive.");
      gunzip("snapshot.tar.gz", "snapshot.tar");
    }

    foreach(tests; string name; string cmd) {
      WERR("  Running test %s.\n", name);

      if(file_stat("../last_"+name)) {
	int build_time = (int)Stdio.read_file("../last_"+name);
	if(build_time>last_download) {
	  WERR("  NOTE: Already built %O: %O. Skipping.\n",
	       project, name);
	  continue;
	}
      }

      // WARNING: client.sh uses a HH:MM format instead.
      Stdio.write_file("current_"+name, time()+"\n");

      Stdio.recursive_rm(name);
      mkdir(name);
      pushd(name);
      run_test(name, cmd);
      popd();

      mv("current_"+name, "last_"+name);
    }

    popd();
  }

  void run_test(string name, string cmd) {

    untar_dir("../snapshot.tar");

    // Enter the directory found in the tar.
    int(0..1) chdir;
    foreach(get_dir("."), string fn)
      if(Stdio.is_dir(fn) && pushd(fn)) {
	chdir=1;
	break;
      }
    if(!chdir) exit(31, "No directory to cd to in snapshot tar.\n");
    WERR("  Building and running test %O: %O\n", name, cmd);

    string result_dir = combine_path(getcwd(), "../../result_"+name+"/");
    !Stdio.recursive_rm(result_dir);
    if(!mkdir(result_dir))
      exit(19, "Could not create new result directory.\n");

    if(!Stdio.cp("buildid.txt", result_dir+"/buildid.txt"))
      exit(20, "Could not copy buildid.txt to result directory.\n");

    Process.Process p;
    mapping(string:mixed) data = ([]);

    // We don't honor build specific environment variables here, as
    // is done in client.sh.
    data->env = getenv() | environment;

    Stdio.File log = Stdio.File(result_dir + "xenofarmclient.txt", "cwt");
    data->stdout = log;
    data->stderr = log;
#ifdef __NT__
    if(!has_value(cmd, "\""))
      cmd = "\""+cmd+"\"";
    p = Process.create_process( ({ "cmd", "/c", cmd }), data);
#else
    p = Process.create_process( ({ "/bin/sh", "-c", cmd }), data);
#endif
    int ret = p->wait();
    if(ret == -1)
      WERR("Build command was killed.\n");
    else if(ret != 0)
      WERR("Build command failed, exit code %d.\n", ret);

    // We do not check the state for multimachine compilation here,
    // as is done in client.sh.


    if(Stdio.is_dir("xenofarm_result")) {
      cd("xenofarm_result");
    }
    else if(file_stat("xenofarm_result.tar.gz")) {
      if(!mv("xenofarm_result.tar.gz", result_dir))
	exit(25, "Could not move xenofarm result file to result directory.\n");
      popd();
      pushd(result_dir);
      Stdio.recursive_rm("repack");
      mkdir("repack");
      gunzip("xenofarm_result.tar.gz", "xenofarm_result.tar");
      cd("repack");
      untar_dir("../xenofarm_result.tar");
    }
    else {
      popd();
      pushd(result_dir);
    }

    make_machineid(name, cmd);

    tar_dir("xenofarm_result.tar", "xenofarm_result.tar");

    // FIXME: We could reduce memory consumption with a iterative feeding.
    Gz.File c = Gz.File("xenofarm_result.tar.gz", "wb");
    c->write(Stdio.read_file("xenofarm_result.tar"));
    c->close();

    WERR("Upload result to %s\n", resulturl);
    Protocols.HTTP.put_url(resulturl,
			   Stdio.read_file("xenofarm_result.tar.gz"));
    popd();
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
    string config_name = f[..sizeof(f)-5]; // Remove ".cfg" from f.
    if(file_stat(nodeconfig))
      configs += ({ Config(Stdio.read_file(nodeconfig), config_name) });
    else
      configs += ({ Config(Stdio.read_file(config_dir + "/" +f),
			   config_name) });
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

void make_machineid(string test, string cmd) {
  Stdio.File f = Stdio.File("machineid.txt", "cwt");
  f->write("sysname: "+system->unames+"\n");
  f->write("release: "+system->unamer+"\n");
  f->write("version: "+system->unamev+"\n");
  f->write("machine: "+system->unamem+"\n");
  f->write("nodename: "+system->node+"\n");
  f->write("testname: "+test+"\n");
  f->write("command: "+cmd+"\n");
  f->write("clientversion: pike_client.pike " + VERSION + "\n");
  // We don't use put, so we don't add putversion to machineid.
  f->write("contact: "+system->email+"\n");
}

#ifdef PID_FILE
void setup_pidfile() {
  string pidf = "xenofarm-"+system->node+".pid";

  // We should see if the process is still running, but I do not know
  // how under Windows, so for now we always abort if we find a pid-file
  // lying around...
  if(file_stat(pidf))
    exit(2, "Already running xenofarm pid %s.\n", Stdio.read_file(pidf));
  Stdio.write_file(pidf, (string)getpid());
  atexit(clean_exit);
}
#endif /* PID_FILE */

int main(int num, array(string) args) {
  WERR("%O started.\n", args[0]);

  // Check cwd for a "dont_run" file, in which case we'll abort.
  if(file_stat("dont_run"))
    exit(5, "FATAL: dont_run file found. Doing that.\n");

  // We don't trap signals as client.sh do since the Windows signal
  // system doesn't work.

#ifndef __NT__
  putenv("PATH", getenv("PATH")+":/usr/local/bin:/sw/local/bin");
  putenv("LC_ALL","C");
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
	exit(0, "pike_client.pike " + VERSION + "\n"
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

  setup_system_info();
#ifdef PID_FILE
  setup_pidfile();
#endif /* PID_FILE */

  system->email = get_email();
  WERR("Email: %s\n", system->email);

  // We don't check multi machine compilation setup since sprsh doesn't run
  // under Windows.

  // We don't set putname nor compile put, since we are using an internal
  // solution. Nor do we check for the availability of wget or gzip, since
  // we use internal solutions there too. The Pike however needs to be compiled
  // with gz, but we'll get a compilation error while trying to start this
  // program if that is not the case.

  read_configs();
  while(1) {
    foreach(configs, Config config) {
      WERR("Building project %s from %s.\n",
	   config->project, config->snapshoturl);
      if(config->prepare())
	config->run_tests();
    }
    WERR("Sleep for 5 minutes...\n");
    sleep(5*60);
  }
}
