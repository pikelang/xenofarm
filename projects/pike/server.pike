
// Xenofarm server for the Pike project
// By Martin Nilsson
// $Id: server.pike,v 1.7 2002/05/15 01:11:01 mani Exp $

// The Xenofarm server program is not really intended to be run verbatim, since almost
// all projects have their own little funny things to take care of. This is an
// adaptation for the Pike programming language itself.

inherit "server.pike";

// Set default values to variables, so that we don't have to remember to give them
// when starting the program.
Sql.Sql xfdb = Sql.Sql("mysql://localhost/xenofarm");
string project = "pike7.3";
string web_dir = "/home/nilsson/xenofarm/out/";
string work_dir = "/home/nilsson/xenofarm/temp/";
string repository = ""; // Ignore this.

string pike_version = "7.3";

// Also, our database has a few more fields than the standard definition.
constant db_def = "CREATE TABLE build (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, "
                  "time INT UNSIGNED NOT NULL, "
                  "project ENUM('pike7.3') NOT NULL, "
                  "export ENUM('yes','no') NOT NULL DEFAULT 'yes', "
                  "documentation ENUM('yes','no') )";

constant latest_pike73_checkin = "http://pelix.ida.liu.se/development/cvs/latest-Pike-commit";

// XXXX-YYYYMMDD-hhmmss.tar.gz
int time_from_filename(string fn) {
  int Y,M,D,h,m,s;
  if( sscanf(fn, "%*s-%4d%2d%2d-%2d%2d%2d",
	     Y,M,D,h,m,s)!=7 )
    return 0;
  return mktime(s,m,h,D,M,Y,0,0);
}

int get_latest_checkin()
{
  string timestamp = Protocols.HTTP.get_url_data(latest_pike73_checkin);
  return Calendar.set_timezone("UTC")->dwim_time(timestamp)->unix_time();
}

string make_build_low() {
  cd(work_dir);
  Stdio.recursive_rm("Pike");
  if(Process.system("cvs -Q -d :ext:nilsson@pelix.ida.liu.se:/pike/data/cvsroot co Pike/"+pike_version))
    return 0;
  cd("Pike/"+pike_version);
  if(Process.system("make autobuild_export"))
     return 0;

  array potential_build_names = glob("Pike*", get_dir("."));
  if(!sizeof(potential_build_names)) {
    xfdb->query("INSERT INTO builds (time, project, export) VALUES (%d,%s,'no')", latest_build, project);
    return 0;
  }

  int new_time = time_from_filename(potential_build_names[0]);
  if(new_time)
    latest_build = new_time;

  return potential_build_names[0];
}
