// This is a Roxen WebServer module.
// Copyright 2002 Martin Nilsson

#include <module.h>
inherit "module";

constant cvs_version = "$Id: xenofarm_ui.pike,v 1.22 2002/11/18 01:31:55 mani Exp $";
constant thread_safe = 1;
constant module_type = MODULE_TAG;
constant module_name = "Xenofarm: UI module";
constant module_doc  = "...";
constant module_unique = 1;

static class DatabaseVar
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
  defvar("db", DatabaseVar(" none", ({}), 0, "Default project database",
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

static string default_db;

void start()
{
  default_db = query("db");
}

static string in_red(string msg)
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

static string fmt_time(int t)
{
  return Calendar.ISO.Second(t)->format_time();
}

static string fmt_timespan(int t) {
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

static constant WHITE = 0, RED = 1, YELLOW = 2, GREEN = 3;

static class Build {

  int(0..) id;
  int(0..3) summary;
  int(0..) build_datetime;
  int(0..1) export_ok;
  int(0..2) docs_status;
  Project project;

  string str_build_datetime;

  void create(int(0..) _id, int(0..) _build_datetime,
	      int(0..1) _export_ok, int(0..2) _docs_status, Project _project) {

    id = _id;
    build_datetime = _build_datetime;
    export_ok = _export_ok;
    docs_status = _docs_status;
    project = _project;

    if(!export_ok) summary = RED;
    str_build_datetime = fmt_time(build_datetime);
  }

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

    if(!docs_status) {
      string docs = get(xfdb, "build", "documentation", ([ "id":id ]));
      docs_status = ([ 0:0, "no":1, "yes":2 ])[docs];
      if(docs_status) changed=1;
    }

    return changed;
  }

  mapping(string:int|string) get_build_entities()
  {
    return ([ "id": id,
	      "time": str_build_datetime,
	      "summary": color[summary],
	      "source": export_color[export_ok],
	      "documentation": docs_color[docs_status],
    ]) + status_summary;
  }

  array(mapping(string:int|string))|mapping(string:int|string)
    get_result_entities(void|int machine) {

    if(!zero_type(machine))
      return ([ "status" : color[ratings[results[machine]]],
		"system" : machine,
		"build" : id,
		"warnings" : warnings[machine],
		"time" : str_build_datetime,
		"timespan" : fmt_timespan(time_spent[machine]),
      ]);
    array ret = ({});
    foreach(sort(indices(project->machines)), int system)
      ret += ({ ([ "status" : color[ratings[results[system]]],
		   "system" : system,
		   "build" : id,
      ]) });
    return ret;
  }

  array(int) list_machines() {
    return indices(results);
  }

  mapping(string:int|string) get_details(int client) {
    return ([ "machine" : project->machines[client],
	      "platform" : project->platforms[client],
	      "result" : results[client],
	      "warnings" : warnings[client],
	      "time" : fmt_timespan(time_spent[client]),
	      "build_id" : (string)id,
	      "machine_id" : (string)client,
   ]);
  }
}

static class Project {

  array(Build) builds = ({});
  array build_indices = ({});

  mapping(int:string) platforms = ([]);
  mapping(int:string) machines = ([]);
  array(mapping(string:string|int)) machine_entities = ({});

  int next_update;

  //! Updates the module's internal state with recent activity by the
  //! packager daemons and the result parsers, as logged in the
  //! Xenofarm database of choice.
  //! @returns
  //!   The number of seconds left until the next update will happen.
  int update_builds(Sql.Sql xfdb) {
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

    if(sizeof(new)) {
      builds = map(new, lambda(mapping in) {
			  int id = (int)in->id, t = (int)in->time;
			  mapping info = get(xfdb, "build",
					     ({ "export", "documentation" }),
					     ([ "id" : id ]));
			  int summary, docs, export = info->export == "yes";
			  docs = ([ "yes":2, "no":1 ])[info->documentation];
			  return Build(id, t, export, docs, this_object());
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
      me += ({ get_machine_entities_for( machine ) });
    machine_entities = me;

    return latency; // [until] next time, gadget...
  }

  mapping get_machine_entities_for(int machine) {
    return ([ "id"   : machine,
	      "name" : machines[machine],
	      "platform" : platforms[machine] ]);
  }
}

static mapping(string:Project) projects = ([]);

static Project get_project(string db) {
  return projects[db] || ( projects[db]=Project() );
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

    array do_enter(RequestID id)
    {
      string db = args->db || default_db;
      id->misc->xenofarm_db = db;
      Project p = get_project(db);

      Sql.Sql xfdb;
      array error = catch(xfdb = DBManager.get(db, my_configuration(), 1));
      if(!xfdb)
	RXML.run_error("Couldn't connect to SQL server" +
		       (error ? ": " + error[0] : "") + "\n");
      if(!xflock++)
	CACHE(p->update_builds(xfdb));
      vars->updated = fmt_time(p->next_update);
    }

    array do_return(RequestID id) {
      result = content;
      id->misc->xenofarm_db = 0;
      xflock--;
    }
  }
}

class TagEmitXF_Machine {
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "xf-machine";

  array(mapping) get_dataset(mapping m, RequestID id)
  {
    NOCACHE();
    Project p = get_project(m->db || id->misc->xenofarm_db || default_db);

    // Remove machines whose last max-columns builds were all white
    if(int maxcols = (int)m_delete(m, "max-columns"))
    {
      array(mapping) result = ({});
      foreach(sort(indices(p->machines)), int machine)
      {
	array status = p->builds->get_result_entities( machine )->status;
	if(sizeof(status[..maxcols-1] - ({ "white" })))
	  result += ({ p->get_machine_entities_for(machine) });
      }
      return result;
    }

    return p->machine_entities;
  }
}

class TagEmitXF_Build {
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "xf-build";

  array(mapping) get_dataset(mapping m, RequestID id)
  {
    NOCACHE();
    string db = m->db || id->misc->xenofarm_db || default_db;
    array res = get_project(db)->builds->get_build_entities();

    // Optimize sorting
    if(string order=m->sort)
      switch (order) {
      case "-id":
      case "-time":
	res = reverse(res);
	// fallthrough
      case "id":
      case "":
      case "time":
	m_delete(m, "sort");
	break;
      }

    return res;
  }
}

class TagEmitXF_Result {
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "xf-result";

  array(mapping) get_dataset(mapping m, RequestID id)
  {
    NOCACHE();
    Project p = get_project(m->db || id->misc->xenofarm_db || default_db);
    array res;

    if(m->build && m->machine)
      res = ({ p->builds[search(p->build_indices, (int)m->build)]->
	       get_result_entities() });
    else if(m->build)
      res = p->builds[search(p->build_indices, (int)m->build)]->
	get_result_entities();
    else if(m->machine)
      res = p->builds->get_result_entities( (int)m->machine );

    if(!res)
      RXML.parse_error("No build or machine attribute.\n");

    // Optimize sorting
    string needs_reordering = m->sort;
    if(needs_reordering)
      switch (needs_reordering) {
      case "-id":
      case "-time":
	res = reverse(res); // fallthrough
      case "":
      case "id":
      case "time":
	m_delete(m, "sort");
	needs_reordering = 0;
	break;
      }

    return res;
  }
}

class TagXF_Details {
  inherit RXML.Tag;
  constant name = "xf-details";

  class Frame {
    inherit RXML.Frame;
    mapping vars;

    array do_enter(RequestID id)
    {
      NOCACHE();
      Project p = get_project(args->db || id->misc->xenofarm_db || default_db);

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

      build = search(p->build_indices, build);
      if(build==-1)
	RXML.run_error("Selected build no longer available.\n");

      vars = p->builds[build]->get_details(client);
    }
  }
}

class TagXF_Files {
  inherit RXML.Tag;
  constant name = "xf-files";

  class Frame {
    inherit RXML.Frame;

    array(string) make_result(string path, RequestID id) {
      mapping a = id->conf->find_dir_stat(path,id);
      array res = ({});
      foreach(sort(indices(a)), string fn) {
	if(a[fn]->isreg) {
	  fn = sprintf("<a href='%s%s'>%s</a>", path, fn, fn);
	  res += ({ fn });
	  continue;
	}
	if(a[fn]->isdir) {
	  res += map(make_result(path+fn+"/", id),
		     lambda(string in) {
		       return fn+"/" + in;
		     });
	}
      }
      return res;
    }

    array do_enter(RequestID id) {
      // No CACHE call. Cache forever.

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

      if(!args->dir)
	RXML.parse_error("No directory chosen.\n");
      args->dir = Roxen.fix_relative(args->dir, id);
      if(args->dir[-1]!='/')
	args->dir += "/";

      result = make_result(args->dir+build+"_"+client+"/", id)*"<br />";
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


TAGDOCUMENTATION;
#ifdef manual
constant tagdoc = ([
  "xf-update": ({ #"<desc type='both'>
<p>
 Updates the cached result table from the database. The tag works as a mutex
 if used as a container tag. Then the contents of the tag will not change during
 output.
</p>

<attr name='db'><p>
 The database that contains the Xenofarm result table.
</p></attr>

</desc>", ([
  "&_.updated;":#"<desc type='entity'><p>
 Returns the time when the table was updated.
</p>
<ex type='box'>2002-08-30 11:26:01</ex>
</desc>"
]) }),

  // ------------------------------------------------------------

  "emit#xf-machine":({ #"<desc type='plugin'>
<p>
  Lists all the clients that are visible on the result table.
</p></desc>", ([

  "&_.id;":#"<desc type='entity'><p>
  The numeric id of the client.
</p></desc>",

  "&_.name;":#"<desc type='entity'><p>
  The node name of the client.
</p></desc>",

  "&_.platform;":#"<desc type='entity'><p>
  The system of the client.
</p></desc>",

  // ------------------------------------------------------------

  "emit#xf-build":"<desc type='plugin'></desc>",

  // ------------------------------------------------------------

  "emit#xf-result":"<desc type='plugin'></desc>",

  // ------------------------------------------------------------

  "xf-details":({ #"<desc type='cont'>
<p>
 Displays detailed information about a specific build. Either the
 attribute id or the attribute build and client must be present.
</p>

<attr name='id'><p>
  An identification of the build in the form build_client, e.g.
  107_22.
</p></attr>

<attr name='build'><p>
  Which build to show details for. Must be used together with the
  attribute client.
</p></attr>

<attr name='client'><p>
  Which client to show details for. Must be used together with the
  attribute build.
</p></attr>

</desc>", ([
  "&_.machine;" : #"<desc attr='entity'><p>
  The node name of the client machine.
</p></desc>",

  "&_.platform" : #"<desc attr='entity'><p>
  The system on the client machine. Resembles 'uname -s -r -m'.
</p></desc>",

  "&_.result" : #"<desc attr='entity'><p>
  The status of the build, e.g. 'failed'.
</p></desc>",

  "&_.warnings" : #"<desc attr='entity'><p>
  The number of warnings detected during build.
</p></desc>",

  "&_.time" : #"<desc attr='entity'><p>
  The time spent during build.
</p></desc>",
]) }),

]);
#endif
