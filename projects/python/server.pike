// Xenofarm Python result parser

inherit "../../server.pike";

Sql.Sql xfdb = Sql.Sql(Stdio.read_file("/home/sfarmer/.xeno-mysql-url"));

string project    = "python";
string cvs_module = project;
string web_dir    = "/lysator/www/projects/xenofarm/python/export/";
string work_dir   = "/lysator/www/projects/xenofarm/python/tmp-server/";

int checkin_poll  = 600;
int min_build_distance = 60;

string source_transformer = getcwd() + "/source-transform.sh";
