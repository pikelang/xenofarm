// Xenofarm lyskom server result parser

inherit "../../server.pike";

Sql.Sql xfdb = Sql.Sql(Stdio.read_file("/home/ceder/.xeno-mysql-url"));

string project    = "lyskom-server";
string cvs_module = project;
string web_dir    = "/lysator/www/projects/xenofarm/lyskom-server/export/";
string work_dir   = "/lysator/www/projects/xenofarm/lyskom-server/tmp/";

int checkin_poll  = 180;
int min_build_distance = 1800;

string source_transformer = getcwd() + "/source-transform.sh";
