
// Xenofarm server for the Pike project
// By Martin Nilsson
// $Id: server.pike,v 1.3 2002/05/03 21:56:13 mani Exp $

// The Xenofarm server program is not really intended to be run verbatim, since almost
// all projects have their own little funny things to take care of. This is an
// adaptation for the Pike programming language itself.

inherit "server.pike";

Sql.Sql xfdb = Sql.Sql("mysql://localhost/xenofarm");
string project = "pike7.3";
string web_dir = "/home/nilsson/xenofarm/out/";
string repository = ""; // Ignore this.

string pike_version = "7.3";

// Also, our database has a few more fields than the standard definition.
constant db_def = "CREATE TABLE build (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, "
                  "time INT UNSIGNED NOT NULL, "
                  "project ENUM('pike7.3') NOT NULL, "
                  "export ENUM('yes','no') NOT NULL DEFAULT 'yes', "
                  "documentation ENUM('yes','no') )";

int get_latest_checkin() {
  // Insert jhs mysql thing here.
}

string make_build_low() {
  if(Process.system("cvs co Pike/"+pike_version))
    return 0;
  cd("Pike/"+pike_version);
  if(Process.system("make autobuild_export"))
     return 0;

  array potential_build_names = glob("Pike*", get_dir("."));
  if(!sizeof(potential_build_names)) {
    xfdb->query("INSERT INTO builds (time, project, export) VALUES (%d,%s,'no')", latest_build, project);
    Stdio.recursive_rm("Pike/"+pike_version);
    return 0;
  }
  return potential_build_names[0];
}
