// Xenofarm Python result parser

inherit "../../../result_parser.pike";

Sql.Sql xfdb = Sql.Sql(Stdio.read_file("/home/sfarmer/.xeno-mysql-url"));

string work_dir   = "/lysator/www/projects/xenofarm/python/tmp-result/";
string result_dir = "/lysator/www/projects/xenofarm/python/results/";
string web_dir    = "/lysator/www/projects/xenofarm/python/files/";
