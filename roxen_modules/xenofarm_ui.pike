// This is a Roxen WebServer module.
// Copyright 2002 Martin Nilsson

#include <module.h>
inherit "module";

constant cvs_version = "$Id: xenofarm_ui.pike,v 1.11 2002/08/14 19:28:36 jhs Exp $";
constant thread_safe = 1;
constant module_type = MODULE_TAG;
constant module_name = "Xenofarm: UI module";
constant module_doc  = "...";
constant module_unique = 1;

class DatabaseVar
{
  inherit Variable.StringChoice;
  array get_choice_list( )
  {
    return ({ " none" })
           + sort(DBManager.list( my_configuration() ));
  }
}

void create()
{
  defvar("db", DatabaseVar(" none", ({}), 0, "Default database",
			   "If this is defined, it's the database "
			   "the xenofarm tags will use by default "
			   "when no db attribute has been given, "
			   "for all build and result data."));

  defvar("results", 10, "Number of results", TYPE_INT,
	 "The maximum number of results" );

  defvar("latency", 60, "Overview update latency", TYPE_INT,
	 "The number of seconds between successive updates of the "
	 "module's internal state from the Xenofarm database. The "
	 "lower the value, the higher the load on your poor dbm.");
}

string default_db;

void start()
{
  default_db = query("db");
}

string in_red(string msg)
{
  return sprintf("<font color=\"red\">%s</font>", msg);
}

string status()
{
  if(default_db != " none")
  {
    mixed err = catch
    {
      object o = DBManager.get(default_db, my_configuration());
      if(!o)
	error("The database specified as default database does not exist");
      return sprintf("The default database is connected to %s server on %s."
                     "<br />\n",
                     Roxen.html_encode_string(o->server_info()),
                     Roxen.html_encode_string(o->host_info()));
    };
    if(err)
    {
      return in_red("The default database is not connected:") + "<br />\n" +
	     replace(Roxen.html_encode_string(describe_error(err)),
		     "\n", "<br />\n") + "<br />\n";
    }
  } else
    return in_red("Please set up a default database under the DBs tab.");
  return "";
}

string fmt_time(int t)
{
  return Calendar.ISO.Second(t)->format_time();
}

string fmt_timespan(int t) {
  string res = "";
  if(t>3600) {
    res += (t/3600)+" h, ";
    t = t%3600;
  }
  if(t>60) {
    res += (t/60)+" m, ";
    t = t%60;
  }
  res += t+" s";
  return res;
}

constant WHITE = 0, RED = 1, YELLOW = 2, GREEN = 3;

static class Build(int(0..) id,
		   int(0..3) summary, int(0..) build_datetime,
		   int(0..1) export_ok, int(0..2) docs_status)
{
  constant color = ([ WHITE : "white",
			RED : "red",
		     YELLOW : "yellow",
		      GREEN : "green" ]);
  constant export_color = ({ "red", "green" });		// int(0..1) export_ok
  constant docs_color = ({ "white", "red", "green" }); // int(0..2) docs_status

  //! client:status
  mapping(int(0..):string) results = ([]);

  //! client:warnings
  mapping(int(0..):int(0..)) warnings = ([]);

  //! client:time
  mapping(int(0..):int(0..)) time_spent = ([]);

  mapping(string:int(0..)) status_summary = ([
    "results" : 0,
    "build" : 0,
    "verify" : 0,
    "export" : 0,
  ]);

  constant ratings = ([
    "failed" : RED,
    "built" : YELLOW,
    "verified" : YELLOW,
    "exported" : GREEN
  ]);

  int(0..1) update_results(Sql.Sql xfdb)
  {
    array res = xfdb->query("SELECT system,status,warnings,time_spent "
			    "FROM result WHERE build = "+id);
    int changed;
    foreach(res, mapping x)
    {
      int system = (int)x->system;
      if(results[system]) continue;
      results[system] = x->status;
      changed = 1;

      switch(x->status)
      {
        case "exported": status_summary->export++; // Fall through
	case "verified": status_summary->verify++; // Fall through
	case "built":	 status_summary->build++;  // Fall through
	case "failed":
	default:	 status_summary->results++;
      }

      warnings[system] = (int)x->warnings;
      time_spent[system] = (int)x->time_spent;
    }
    if(changed)
      summary = min( @map( values(results),
			   lambda(string in) { return ratings[in]; } ) );

    string docs = get(xfdb, "build", "documentation", ([ "id":id ]));
    return changed;
  }

  mapping(string:int|string) get_build_entities()
  {
    return ([ "id": id,
	      "time": fmt_time(build_datetime),
	      "summary": color[summary],
	      "source": export_color[export_ok],
	      "documentation": docs_color[docs_status],
    ]) + status_summary;
  }

  array(mapping(string:int|string)) get_result_entities() {
    array ret = ({});
    foreach(sort(indices(machines)), int system)
      ret += ({ ([ "status" : color[ratings[results[system]]],
		   "system" : system, ]) });
    return ret;
  }

  array(int) list_machines() {
    return indices(results);
  }

  mapping(string:int|string) get_details(int client) {
    return ([ "machine" : machines[client],
	      "platform" : platforms[client],
	      "result" : results[client],
	      "warnings" : warnings[client],
	      "time" : fmt_timespan(time_spent[client]),
    ]);
  }
}

static array(Build) builds = ({});
static array build_indices = ({});

static mapping(int:string) platforms = ([]);
static mapping(int:string) machines = ([]);
static array(mapping(string:string)) machine_entities = ({});

static int next_update;

//! Updates the module's internal state with recent activity by the
//! packager daemons and the result parsers, as logged in the
//! Xenofarm database of choice.
//! @returns
//!   The number of seconds left until the next update will happen.
static void update_builds(Sql.Sql xfdb)
{
  // Only update internal state once a minute.
  int now = time(1), latency = query("latency");
  if(next_update < now)
    next_update = time() + latency;
  else
    return next_update - now;

  // Add new builds

  int latest_build;
  if(sizeof(builds))
    latest_build = builds[0]->build_datetime;

  array new = xfdb->query("SELECT id,time FROM build WHERE time > %d"
			  " ORDER BY time DESC LIMIT %d", latest_build,
			  query("results"));

  if(sizeof(new))
  {
    builds = map(new, lambda(mapping in)
		 {
		   int id = (int)in->id, t = (int)in->time;
		   mapping info = get(xfdb, "build",
				      ({ "export", "documentation" }),
				      ([ "id" : id ]));
		   int summary, docs, export = info->export == "yes";
		   docs = ([ "yes":2, "no":1 ])[info->documentation];
		   if(!export) summary = RED;
		   return Build(id, summary, t, export, docs);
		 }) + builds[..sizeof(builds)-sizeof(new)-1];
    build_indices = builds->id;
  }

  if(sizeof(builds)>query("results")) {
    builds = builds[..query("results")-1];
    build_indices = builds->id;
  }

  // Update featured builds

  int changed = `+( @builds->update_results(xfdb) );
  if(!changed)
    return latency;

  // Update list of involved machines

  multiset m = (multiset)Array.uniq( `+( @builds->list_machines() ) );

  foreach(indices(machines), int machine)
    if( !m[machine] ) {
      m_delete(machines, machine);
      m_delete(platforms, machine);
    }
    else
      m[machine] = 0;

  foreach(indices(m), int machine) {
    array data = xfdb->query("SELECT name,platform FROM system WHERE id=%d",
			     machine);
    machines[machine] = data[0]->name;
    platforms[machine] = data[0]->platform;
  }

  array me = ({});
  foreach(sort(indices(machines)), int machine)
    me += ({ ([ "id":machine,
		"name":machines[machine],
		"platform":platforms[machine] ]) });
  machine_entities = me;

  return latency; // [until] next time, gadget...
}

//
// Tags
//

class TagXF_Update {
  inherit RXML.Tag;
  constant name = "xf-update";
  int xflock;

  class Frame {
    inherit RXML.Frame;
    mapping vars = ([]);

    array do_enter()
    {
      Sql.Sql xfdb;
      array error = catch(xfdb = DBManager.get(args->db || default_db,
					       my_configuration(), 1));
      if(!xfdb)
	RXML.run_error("Couldn't connect to SQL server" +
		       (error ? ": " + error[0] : "") + "\n");
      if(!xflock++)
	update_builds(xfdb);
      vars->updated = fmt_time(latest_update);
    }

    array do_return() {
      result = content;
      xflock--;
    }
  }
}

class TagEmitXF_Machine {
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "xf-machine";

  array(mapping) get_dataset(mapping m, RequestID id) {
    return machine_entities;
  }
}

class TagEmitXF_Build {
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "xf-build";

  array(mapping) get_dataset(mapping m, RequestID id) {
    return builds->get_build_entities();
  }
}

class TagEmitXF_Result {
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "xf-result";

  array(mapping) get_dataset(mapping m, RequestID id) {
    if(!m->build) RXML.parse_error("No build attribute.\n");
    return builds[search(build_indices, (int)m->build)]->
      get_result_entities();
  }
}

class TagXF_Details {
  inherit RXML.Tag;
  constant name = "xf-details";

  class Frame {
    inherit RXML.Frame;
    mapping vars;

    array do_enter() {

      int build, client;
      if(args->id) {
	if( sscanf(args->id, "%d_%d", build, client)!=2 )
	  RXML.parse_error("Could not decode id (%O)\n", args->id);
      }
      else if(args->build && args->client) {
	build = args->build;
	client = args->client;
      }
      else
	RXML.parse_error("No build chosen (id or build+client).\n");

      build = search(build_indices, build);
      if(build==-1)
	RXML.run_error("Selected build no longer available.\n");

      vars = builds[build]->get_details(client);
    }
  }
}

//! Convenience method to get the column (or columns) @[field] from
//! the database table @[table], where the conditions @[where] are
//! satisfied. The result is never more than one row (in fact, a
//! @code{" LIMIT 1"@} is always appended to the query), and if no
//! rows match, the value @code{0@} is returned.
string|mapping get(Sql.Sql db, string table,
                   string|array field,
                   array|mapping|string where)
{ 
  if(mappingp(where))
    where = format_idx_is_val(db, where);
  if(arrayp(where))
    where *= " AND ";
  string q = sprintf("SELECT %s FROM %s WHERE %s LIMIT 1",
                     (stringp(field) ? field : field * ","), table, where);
  array(mapping) rows = db->query(q);
  if(sizeof(rows))
    if(arrayp(field))
      return rows[0];
    else
      return rows[0][field];
}

array(string) format_idx_is_val(Sql.Sql db, mapping(string:mixed) what)
{ 
  return Array.map((array)what,
                   lambda(array w)
                   { 
                     return sprintf("%s='%s'", w[0],
                                    db->quote((string)w[1]));
                   });
}
