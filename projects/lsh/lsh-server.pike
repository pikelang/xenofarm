#! /bin/env pike

// Xenofarm lsh source packager

inherit "../../server.pike";

Sql.Sql xfdb = Sql.Sql(Stdio.read_file("/home/nisse/.xeno-mysql-url"));
// Sql.Sql xfdb = Sql.Sql("mysql://nisse@:/home/nisse/hack/xenofarm/mysql/secret/mysql.sock/", "xeno_lsh");

string project    = "lsh";
string cvs_module = project;
string web_dir    = "/lysator/lyswww/projects/roxen/xenofarm/lsh/export/";
string work_dir   = "/lysator/lyswww/projects/roxen/xenofarm/lsh/tmp-server/";
// string web_dir    = "/net/sherman/web/projects/xenofarm/lsh/export/";
// string work_dir   = "/net/sherman/web/projects/xenofarm/lsh/tmp-server/";
// string work_dir   = "/lysator/slaskdisk/tmp/nisse/xeno/";

int checkin_poll  = 180;
int min_build_distance = 1200;

string source_transformer = getcwd() + "/source-transform.sh";
