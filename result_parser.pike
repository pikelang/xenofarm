
// Xenofarm result parser
// By Martin Nilsson
// $Id: result_parser.pike,v 1.3 2002/05/11 01:58:40 mani Exp $

constant db_def1 = "CREATE TABLE system (id INT UNSIGNED AUTO INCREMENT NOT NULL PRIMARY KEY, "
                   "name VARCHAR(255) NOT NULL, "
                   "platform VARCHAR(255) NOT NULL)";

constant db_def2 = "CREATE TABLE result (build INT UNSIGNED NOT NULL, " // FK build.id
                   "system INT UNSIGNED NOT NULL, " // FK system.id
                   "status ENUM('failed','built','verified','exported') NOT NULL, "
                   "warnings INT UNSIGNED NOT NULL, "
                   "time_spent INT UNSIGNED NOT NULL)";

Sql.Sql xfdb;
string result_dir;

void parse_build_id(string fn, mapping res) {
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) return;

  int year;
  if( sscanf("%*syear:%d", year)!=2 ) return;
  int month;
  if( sscanf("%*smonth:%d", month)!=2 ) return;
  int day;
  if( sscanf("%*sday:%d", day)!=2 ) return;
  int hour;
  if( sscanf("%*shour:%d", hour)!=2 ) return;
  int min;
  if( sscanf("%*sminute:%d", min)!=2 ) return;
  int sec;
  if( sscanf("%*ssecond:%d", sec)!=2 ) return;

  res->build = sprintf("%04d%02d%02d-%02d%02d%02d",
		    year, month, day, hour, min, sec);
}

void parse_id(string fn, mapping res) {
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) return;
  sscanf(file, "%s\n", file);
  res->machine = String.trim_all_whites(file);
  // res->host
}

void parse_log(string fn, mapping res) {
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) return;

}

void count_warnings(string fn, mapping res) {
  Stdio.FILE file = Stdio.FILE(fn);
  if(!file) return;

  int warnings;
  foreach(file->line_iterator(1);; string line) {
    if( has_value(lower_case(line), "warning")
	warnings++;
  }
    res->warnings = warnings;
}

void store_result(mapping res) {
  array qres = xfdb->query("SELECT id FROM system WHERE name=%s && platform=%s",
			   res->name, res->platform);
  int id;
  if(sizeof(qres))
    id = qres[0]->id;
  else {
    xfdb->query("INSERT INTO system (name, platform) VALUES (%s,%s)",
		res->name, res->platform);
    id = xfdb->query("SELECT")[0];
  }
}

void process_package(string fn) {
  // unzip
  // untar

  mapping result = ([]);
  parse_build_id(buildidfile, result);
  parse_id(idfile, result);
  if(!result->name || !result->platform)
    return;

  parse_log(logfile, result);
  count_warnings(compilelog, result);
  store_result(result);

  // mv dir, webdir
}

int main(int num, array(string) args) {

process_package(file);

}
