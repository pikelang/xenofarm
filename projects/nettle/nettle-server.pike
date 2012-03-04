#! /bin/env pike

// Xenofarm Nettle source packager

inherit "../../server.pike";

Sql.Sql xfdb = Sql.Sql(Stdio.read_file("/home/nisse/.xeno-nettle-url"));

string project    = "nettle";
string client_type = "git";
string web_dir    = "/lysator/lyswww/projects/roxen/xenofarm/nettle/export/";
string work_dir   = "/lysator/lyswww/projects/roxen/xenofarm/nettle/tmp-server/";

int checkin_poll  = 180;
int min_build_distance = 1200;

string source_transformer = getcwd() + "/source-transform.sh";
