
// Xenofarm Pike result parser
// By Martin Nilsson
// $Id: result_parser.pike,v 1.2 2002/05/30 14:49:38 mani Exp $

inherit "result_parser.pike";

Sql.Sql xfdb = Sql.Sql("mysql://localhost/xenofarm");
string result_dir = "/home/nilsson/xenofarm/in/";
string work_dir = "/tmp/xtmp/";
string web_dir = "/home/nilsson/html/angel/";

string build_id_file = "exportstamp.txt";
string machine_id_file = "machineid.txt";
string main_log_file = "xenofarmlog.txt";
string compilation_log_file = "makelog.txt";

multiset(string) ignored_warnings = (<
  "configure: warning: found bash as /*.",
  "configure: warning: defaulting to --with-poll since the os is *.",
  "checking for irritating if-if-else-else warnings... no (good)",
  "configure: warning: no login-related functions",
  "configure: warning: defaulting to unsigned int.",
  >);

void parse_build_id(string fn, mapping res) {
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) return;

  int year;
  if( sscanf(file, "%*syear:%d", year)!=2 ) return;
  int month;
  if( sscanf(file, "%*smonth:%d", month)!=2 ) return;
  int day;
  if( sscanf(file, "%*sday:%d", day)!=2 ) return;
  int hour;
  if( sscanf(file, "%*shour:%d", hour)!=2 ) return;
  int min;
  if( sscanf(file, "%*sminute:%d", min)!=2 ) return;
  int sec;
  if( sscanf(file, "%*ssecond:%d", sec)!=2 ) return;

  res->build = sprintf("%04d%02d%02d-%02d%02d%02d",
		    year, month, day, hour, min, sec);
}

