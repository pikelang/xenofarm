
// Xenofarm result parser
// By Martin Nilsson
// $Id: result_parser.pike,v 1.4 2002/05/25 00:15:26 mani Exp $

constant db_def1 = "CREATE TABLE system (id INT UNSIGNED AUTO INCREMENT NOT NULL PRIMARY KEY, "
                   "name VARCHAR(255) NOT NULL, "
                   "platform VARCHAR(255) NOT NULL)";

constant db_def2 = "CREATE TABLE result (build INT UNSIGNED NOT NULL, " // FK build.id
                   "system INT UNSIGNED NOT NULL, " // FK system.id
                   "status ENUM('failed','built','verified','exported') NOT NULL, "
                   "warnings INT UNSIGNED NOT NULL, "
                   "time_spent INT UNSIGNED NOT NULL)";

Sql.Sql xfdb;
int result_poll = 60;
string result_dir;
string work_dir;
string web_dir;

string build_id_file = "buildid";
string machine_id_file = "machineid";
string main_log_file = "mainlog";
string compilation_log_file = "compilelog";

multiset(string) processed_results = (<>);
multiset(string) ignored_warnings = (<>);

void parse_build_id(string fn, mapping res) {
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) return;
  file = String.trim_all_whites( (file/"\n")[0] );
  if(!file) return;
  res->build = file;
}

void parse_machine_id(string fn, mapping res) {
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) return;
  array parts = file/"\n";
  if(sizeof(parts)<2);
  res->platform = String.trim_all_whites(parts[0]);
  res->host = String.trim_all_whites(parts[1]);
}

void parse_log(string fn, mapping res) {
  res->status = "red";
  string file = Stdio.read_file(fn);
  if(!file || !sizeof(file)) return;
  array parts = (file/"\n")/2;

  string last_item;
  int last_time;
  foreach(parts, array thing) {
    if(sizeof(thing)!=2) return;
    int new = Calendar.ISO.dwim_time(thing[1])->unix_time();
    if(last_item)
      res["time_"+last_item] = new-last_time;
    last_time = new;
    sscanf(thing[0], "Begin %s", last_item);
  }
}

void count_warnings(string fn, mapping res) {
  Stdio.FILE file = Stdio.FILE(fn);
  if(!file) return;

  int warnings;
 newline:
  foreach(file->line_iterator(1);; string line) {
    line = lower_case(line);
    if( has_value(line, "warning") ) {
      foreach(indices(ignored_warnings), string ignore)
	if(glob(ignore,line)) continue newline;
	warnings++;
    }
  }
    res->warnings = warnings;
}

void store_result(mapping res) {
  write("%O\n", res);
  return;
  array qres = xfdb->query("SELECT id FROM system WHERE name=%s && platform=%s",
			   res->name, res->platform);
  int id;
  if(sizeof(qres))
    id = qres[0]->id;
  else {
    xfdb->query("INSERT INTO system (name, platform) VALUES (%s,%s)",
		res->name, res->platform);
    //    id = xfdb->query("SELECT")[0];
  }
}

void low_process_package() {
  mapping result = ([]);

  parse_build_id(build_id_file, result);
  if(!result->build) {
    write("Failed to parse build id.\n");
    return;
  }

  parse_machine_id(machine_id_file, result);
  if(!result->host || !result->platform) {
    write("Failed to parse machine id.\n");
    return;
  }

  parse_log(main_log_file, result);
  count_warnings(compilation_log_file, result);
  store_result(result);
}

void process_package(string fn) {

  if(!Process.system("tar -xzf "+fn)) {
    //    write("Unable to unpack %O to %O\n", fn, getcwd());
    //    return;
  }

  low_process_package();

  // mv dir, webdir

  //  if(!rm(fn))
  //    write("Unable to remove %O\n", fn);
  //  else
  //    processed_result[fn]=1;
}

int main(int num, array(string) args) {

  if(!cd(work_dir)) {
    write("Could not cd to working dir %O\n", work_dir);
    return 1;
  }
  if(sizeof(get_dir("."))) {
    write("Working dir %O is not empty.\n", work_dir);
    return 1;
  }

  while(1) {
    foreach(get_dir(result_dir), string fn) {
      fn = result_dir + fn;
      if(processed_results[fn]) continue;
      write("Found new result %O\n", fn);
      process_package(fn);
    }
    sleep(result_poll);
  }

}
