
// Xenofarm result parser
// By Martin Nilsson
// $Id: result_parser.pike,v 1.1 2002/05/03 15:46:57 mani Exp $

constant db_def = "CREATE TABLE system (id INT UNSIGNED AUTO INCREMENT NOT NULL PRIMARY KEY, "
                  "name VARCHAR(255) NOT NULL, "
                  "platform VARCHAR(255) NOT NULL)";

constant db_def = "CREATE TABLE result (build INT UNSIGNED NOT NULL, " // FK build.id
                  "system INT UNSIGNED NOT NULL, " // FK system.id
                  "status ENUM('failed','built','verified','exported') NOT NULL, "
                  "warnings INT UNSIGNED NOT NULL, "
                  "time_spent INT UNSIGNED NOT NULL)";

Sql.Sql xfdb;
string result_dir;

void parse_id(string fn, mapping res) {
}

void parse_log(string fn, mapping res) {
}

void count_warnings(string fn, mapping res) {
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
