// Xenofarm lyskom server result parser

inherit "../../result_parser.pike";

Sql.Sql xfdb = Sql.Sql(Stdio.read_file("/home/ceder/.xeno-mysql-url"));

string work_dir   = "tmp";
string result_dir = "/lysator/www/projects/xenofarm/lyskom-server/results/";
string web_dir    = "/lysator/www/projects/xenofarm/lyskom-server/files/";
