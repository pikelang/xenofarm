// This is a Roxen WebServer module.
// Copyright 2002 Martin Nilsson

#include <module.h>
inherit "module";

constant cvs_version = "$Id: xenofarm_ui.pike,v 1.32 2002/12/05 12:42:18 mani Exp $";
constant thread_safe = 1;
constant module_type = MODULE_TAG;
constant module_name = "Xenofarm: UI module";
constant module_doc  = "Module for visualization of Xenofarm build results.";
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
	 "The maximum number of results stored in the internal cache." );

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
  string ret = "";
  if(default_db != " none")
  {
    mixed err = catch
    {
      object o = DBManager.get(default_db, my_configuration());
      if(!o)
	error("The database specified as default database does not exist");
      ret += sprintf("The default database is connected to %s server on %s."
                     "<br />\n",
                     Roxen.html_encode_string(o->server_info()),
                     Roxen.html_encode_string(o->host_info()));
    };
    if(err)
    {
      ret += in_red("The default database is not connected:") + "<br />\n" +
	     replace(Roxen.html_encode_string(describe_error(err)),
		     "\n", "<br />\n") + "<br />\n";
    }
  } else
    ret += in_red("Please set up a default database under the DBs tab.");

  if(sizeof(projects)) {
    ret += "<table border='1'>\n"
      "<tr><th>Database</th><th>Next update</th>"
      "<th>New build</th><th>Last changed</th></tr>\n";
    foreach(indices(projects), string db) {
      Project p = projects[db];
      int t = p->next_update - time();
      ret += "<tr><td>" + db + "</td><td>" +
      (t>0 ? "in " + t + " s" : "next page reload") + "</td><td>" +
	fmt_timespan(time()-p->new_build) + " ago</td><td>" +
	fmt_timespan(time()-p->last_changed) + " ago</td></tr>\n";
    }
    ret += "</table>\n";
  }
  return ret;
}

static string fmt_time(int t)
{
  return Calendar.ISO_UTC.Second(t)->format_time();
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

static string my_min(array in) {
  if(has_value(in, "FAIL")) return "FAIL";
  if(has_value(in, "PASS")) return "PASS";
  return "WARN";
}

static class Build {

  Project project;
  int(0..) id;
  int(0..) build_datetime;

  string summary;
  string export;

  string str_build_datetime;

  void create(int(0..) _id, int(0..) _build_datetime,
	      string _export, Project _project) {

    id = _id;
    build_datetime = _build_datetime;
    export = _export;
    project = _project;

    summary = export;
    str_build_datetime = fmt_time(build_datetime);
  }

  //! client:status
  mapping(int(0..):string) results = ([]);

  //! client:warnings
  mapping(int(0..):int(0..)) warnings = ([]);

  //! client:time
  mapping(int(0..):int(0..)) time_spent = ([]);

  mapping(int(0..):mapping(int(0..):array)) task_results = ([]);

  mapping(string:int(0..)) status_summary = ([]);

  int(0..1) update_results(Sql.Sql xfdb)
  {
    foreach(values(project->tasks), string task)
      if(!status_summary[task]) status_summary[task]=0;

    array res = xfdb->query("SELECT system,task,status,warnings,time_spent "
			    "FROM task_result WHERE build = "+id);
    int changed;
    int build_task = search(project->tasks, "build");
    array(int) new_systems = ({});
    foreach(res, mapping x)
    {
      int system = (int)x->system;
      if(results[system]) continue;
      changed = 1;
      if(!task_results[system]) task_results[system] = ([]);
      int task = (int)x->task;
      task_results[system][task] = 
	({ x->status, (int)x->time_spent, (int)x->warnings });
      new_systems += ({ system });

      if(x->status!="FAIL") status_summary[ project->tasks[task] ]++;
    }

    foreach(new_systems, int system) {
      mapping tasks = task_results[system];
      array status = tasks[build_task];
      array data = values(tasks);
      if(!status)
	results[system] = "FAIL";
      else if(status[0]=="PASS") {
	string status = my_min( column(data,0) );
	if(status=="FAIL") status="WARN";
	results[system] = status;
      }
      else
	results[system] = status[0];

      time_spent[system] = `+( @column(data,1) );
      warnings[system] = `+( @column(data,2) );
    }

    if(changed)
      summary = my_min( values(results) );

    return changed;
  }

  mapping(string:int|string) get_build_entities()
  {
    return ([ "id": id,
	      "time": str_build_datetime,
	      "summary": summary,
	      "source": export,
	      "results": sizeof(results),
    ]) + status_summary;
  }

  array(mapping(string:int|string))|mapping(string:int|string)
    get_result_entities(void|int machine) {

    if(!zero_type(machine))
      return ([ "status" : results[machine]||"NONE",
		"system" : machine,
		"build" : id,
		"warnings" : warnings[machine],
		"time" : str_build_datetime,
		"timespan" : fmt_timespan(time_spent[machine]),
      ]);
    array ret = ({});
    foreach(sort(indices(project->machines)), int system)
      ret += ({ ([ "status" : results[system]||"NONE",
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

  // The build id of the corresponding build in builds.
  array build_indices = ({});

  mapping(int:string) platforms = ([]);
  mapping(int:string) machines = ([]);
  array(mapping(string:string|int)) machine_entities = ({});

  int new_build;
  int last_changed;
  int next_update;

  mapping(int:string) tasks = ([]);

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

    array new = xfdb->query("SELECT id,name,parent FROM task ORDER BY parent");

    if(sizeof(tasks)!=sizeof(new)) 
      foreach(new, mapping res) {
	if((int)res->parent)
	  res->name = tasks[ (int)res->parent ] + "-" + res->name;
	tasks[ (int)res->id ] = res->name;
      }

    new = xfdb->query("SELECT id,time,export FROM build WHERE time > %d"
			    " ORDER BY time DESC LIMIT %d", latest_build,
			    query("results"));

    if(sizeof(new)) {
      new_build = time();
      builds = map(new, lambda(mapping in) {
			  return Build( (int)in->id, (int)in->time,
					in->export, this_object() );
			}) + builds[..sizeof(builds)-sizeof(new)-1];
      build_indices = builds->id;
    }

    if(sizeof(builds)>query("results")) {
      builds = builds[..query("results")-1];
      build_indices = builds->id;
    }

    // Update featured builds

    int changed = `+( 0, @builds->update_results(xfdb) );
    if(!changed)
      return latency;
    last_changed = time();

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
      array data = xfdb->query("SELECT name,sysname,release,version,"
			       "machine,testname "
			       "FROM system WHERE id=%d", machine);
      machines[machine] = data[0]->name;
      string u_sysname = data[0]->sysname;
      string u_release = data[0]->release;
      string u_version = data[0]->version;
      string u_machine = data[0]->machine;

      platforms[machine] = u_sysname + " " + u_release + " " + u_machine;
      if(data[0]->testname!="")
	platforms[machine] += " " + data[0]->testname;
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

  Build get_build(int id) {
    id = search(build_indices, id);
    if(id == -1) return 0;
    return builds[id];
  }
}

// Really static, but we might want to access this variable
// from the Hilfe protocol.
mapping(string:Project) projects = ([]);

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
    if(int maxcols = (int)m_delete(m, "recency"))
    {
      array(mapping) result = ({});
      foreach(sort(indices(p->machines)), int machine)
      {
	array status = p->builds->get_result_entities( machine )->status;
	if(sizeof(status[..maxcols-1] - ({ "NONE" })))
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

    if(m->build) {
      Build b = p->get_build( (int)m->build );
      if(!b) return ({});
      if(m->machine)
	res = ({ b->get_result_entities( (int)m->machine ) });
      else
	res = b->get_result_entities();
    }
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

      Build b = p->get_build(build);
      if(!b) RXML.run_error("Selected build no longer available.\n");
      vars = b->get_details(client);
    }
  }
}

class TagXF_Files {
  inherit RXML.Tag;
  constant name = "xf-files";
  constant flags = RXML.FLAG_EMPTY_ELEMENT;

  class Frame {
    inherit RXML.Frame;

    array(string) make_result(string path, RequestID id) {
      mapping a = id->conf->find_dir_stat(path,id);
      if(!a) return ({});
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

<attr name='db' value='database URL'><p>
 The database that contains the Xenofarm result table. Defaults to the database
 set in as default database in the administration interface. The selected
 database will propagate automatically to all other xf-tags inside the
 xf-update tag, unless the tags has db attribute of their own.
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
</p>

<attr name='db' value='database URL'><p>
 The database that contains the Xenofarm result table. Defaults to the database
 set in the containing xf-update tag or, if such tag is missing, the default
 database in the administration interface.
</p></attr>

<attr name='recency' value='int'><p>
  If set, any machine with no returned result within the given number of builds
  will be removed from the emit result.
</p></attr>
</desc>", ([

  "&_.id;":#"<desc type='entity'><p>
  The numeric id of the client.
</p></desc>",

  "&_.name;":#"<desc type='entity'><p>
  The node name of the client.
</p></desc>",

  "&_.platform;":#"<desc type='entity'><p>
  The system of the client.
</p></desc>",
]) }),

  // ------------------------------------------------------------

  "emit#xf-build":({ #"<desc type='plugin'>
<p>
  Lists all the builds that is in the result table, which size is limited by
  the \"Number of results\" setting in the administration interface.
</p>

<attr name='db' value='database URL'><p>
 The database that contains the Xenofarm result table. Defaults to the database
 set in the containing xf-update tag or, if such tag is missing, the default
 database in the administration interface.
</p></attr>
</desc>", ([

  "&_.id;":#"<desc type='entity'><p>
  The numeric id of the client.
</p></desc>",

  "&_.time;":#"<desc type='entuty'><p>
  The time stamp of the build.
</p></desc>",

  "&_.summary;":#"<desc type='entity'><p>
  The overall assessment of how well the build went, ie. a min() function
  of all the plupps in this build. If one plupp is red the summary is red.
  Can assume one of the values \"white\", \"red\", \"yellow\" and \"green\".
</p></desc>",

  "&_.source;":#"<desc type='entity'><p>
  The result from the source package creation. Can assume one of the values
  \"red\", \"yellow\" and \"green\".
</p></desc>",

  // Project dependent

  "&_.export;":#"<desc type='entity'><p>
  The number of build results that passed the stage exported. Less than or equal
  to \"verify\".
</p></desc>",
 
  "&_.verify;":#"<desc type='entity'><p>
  The number of build results that passed the stage verify. Less than or equal
  to \"build\".
</p></desc>",

  "&_.build;":#"<desc type='entity'><p>
  The number of build results that passed the stage build.
</p></desc>",

  "&_.results;":#"<desc type='entity'><p>
  The number of build results that received.
</p></desc>",

]) }),

  // ------------------------------------------------------------

  "emit#xf-result":({ #"<desc type='plugin'>
<p>
  Lists the results that maches the given search criterions. At least one of
  the attributes build and machine must be given.
</p>

<attr name='db' value='database URL'><p>
 The database that contains the Xenofarm result table. Defaults to the database
 set in the containing xf-update tag or, if such tag is missing, the default
 database in the administration interface.
</p></attr>

<attr name='build' value='int'><p>
  The numerical id of a build.
</p></attr>

<attr name='machine' value='int'><p>
  The numberical id of a machine.
</p></attr>
</desc>", ([

  "&_.build;":#"<desc type='entity'><p>
  The id of the build.
</p></desc>",

  "&_.system;":#"<desc type='entity'><p>
  The id of the system.
</p></desc>",

  "&_.status;":#"<desc type='entity'><p>
  The result status of the build on the current system. Can be any of
  \"white\", \"red\", \"yellow\" and \"green\".
</p></desc>",

  // Only specified when machine is specified

  "&_.time;":#"<desc type='entity'><p>
  The time stamp of the build.
</p></desc>",

  "&_.timespan;":#"<desc type='entity'><p>
  The time it took to complete the build on the client.
</p></desc>",

  "&_.warnings;":#"<desc type='entity'><p>
  The number of warnings counted in the result build log.
</p></desc>",

]) }),

  // ------------------------------------------------------------

  "xf-details":({ #"<desc type='cont'>
<p>
 Displays detailed information about a specific build. Either the
 attribute id or the attribute build and client must be present.
</p>

<attr name='db' value='database URL'><p>
 The database that contains the Xenofarm result table. Defaults to the database
 set in the containing xf-update tag or, if such tag is missing, the default
 database in the administration interface.
</p></attr>

<attr name='id'><p>
  An identification of the build in the form build_client, e.g.
  107_22.
</p></attr>

<attr name='build' value='int'><p>
  Which build to show details for. Must be used together with the
  attribute client.
</p></attr>

<attr name='client' value='int'><p>
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

  // ------------------------------------------------------------

  "xf-files":#"<desc type='tag'>
<p>
  Lists files in subdirectories named as build_client. It does not recurse
  and list files in deeper directories.
</p>

<attr name='id'><p>
  An identification of the build in the form build_client, e.g.
  107_22.
</p></attr>

<attr name='build' value='int'><p>
  Which build to list files for. Must be used together with the
  attribute client.
</p></attr>

<attr name='client' value='int'><p>
  Which client to list files for. Must be used together with the
  attribute build.
</p></attr>

<attr name='dir' value='path' required='1'><p>
  The \"root\" directory where the subdirectories are stored.
</p></attr>
</desc>",

]);
#endif
