
// Xenofarm server for the Pike project
// By Martin Nilsson
// $Id: server.pike,v 1.1 2002/05/03 15:46:57 mani Exp $

// The Xenofarm server program is not really intended to be run verbatim, since almost
// all projects have their own little funny things to take care of. This is an
// adaptation for the Pike programming language itself.

inherit "server.pike";

Sql.Sql xfdb = Sql.Sql("mysql://localhost/xenofarm");
string project = "pike7.3";
string web_dir = "/home/build/xenofarm/out/";

// Also, our database has a few more fields than the standard definition.
constant db_def = "CREATE TABLE build (id INT UNSIGNED NOT NULL AUTO INCREMENT PRIMARY KEY, "
                  "time INT UNSIGNED NOT NULL, "
                  "project ENUM('pike7.3') NOT NULL, "
                  "export ENUM('yes','no') NOT NULL, "
                  "documentation ENUM('yes','no') )";

int get_latest_checkin() {
  // Insert jhs mysql thing here.
}

string make_build_low() {
  // "cvs co "+Pike/7.3
  // "cd "+Pike/7.3
  // "make autobuild_export"

  array potential_build_names = glob("Pike*", get_dir("."));
  if(!sizeof(potential_build_names)) {
    // Register export failure (db?)
    // Remove build tree
    return;
  }
  return potential_build_names[0];
}
