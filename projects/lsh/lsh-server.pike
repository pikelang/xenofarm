#! /usr/bin/env pike

// Xenofarm lsh source packager

inherit "../../server.pike";

Sql.Sql xfdb = Sql.Sql(Stdio.read_file("/home/nisse/.xeno-mysql-url"));

string project    = "lsh";
string cvs_module = project;
string web_dir    = "/lysator/www/projects/xenofarm/lsh/export/";
// string work_dir   = "/lysator/www/projects/xenofarm/lsh/tmp-server/";
string work_dir   = "/lysator/slaskdisk/tmp/nisse/xeno/lsh";

int checkin_poll  = 180;
int min_build_distance = 1800;

string source_transformer = getcwd() + "/source-transform.sh";
