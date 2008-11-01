#! /usr/bin/env pike

// Xenofarm lsh result parser

inherit "../../result_parser.pike";

Sql.Sql xfdb = Sql.Sql(Stdio.read_file("/home/nisse/.xeno-mysql-url"));
// Sql.Sql xfdb = Sql.Sql("mysql://nisse@:/home/nisse/hack/xenofarm/mysql/secret/mysql.sock/", "xeno_lsh");

string work_dir   = "/lysator/lyswww/projects/roxen/xenofarm/lsh/tmp-result";
string result_dir = "/lysator/lyswww/projects/roxen/xenofarm/lsh/results/";
string web_dir    = "/lysator/lyswww/projects/roxen/xenofarm/lsh/files/";

string base = "/home/nisse/hack/xenofarm/";
string post_script = base + "updatehtml --verbose " + 
		     base + "projects/lsh";
