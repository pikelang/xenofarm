#! /usr/bin/env pike

// Xenofarm lsh result parser

inherit "../../result_parser.pike";

Sql.Sql xfdb = Sql.Sql(Stdio.read_file("/home/nisse/.xeno-mysql-url"));

string work_dir   = "/lysator/www/projects/xenofarm/lsh/tmp-result";
string result_dir = "/lysator/www/projects/xenofarm/lsh/results/";
string web_dir    = "/lysator/www/projects/xenofarm/lsh/files/";

string base = "/home/nisse/hack/xenofarm/";
string post_script = base + "updatehtml --verbose " + 
		     base + "projects/lsh";
