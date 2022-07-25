// This is a Roxen WebServer module.
// Copyright 2002 Martin Nilsson

#include <module.h>
inherit "module";

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

  defvar("default_project", "", "Default project", TYPE_STRING,
	 "The default project to retrieve information for.");

  defvar("results", 10, "Number of results", TYPE_INT,
	 "The maximum number of results stored in the internal cache." );

  defvar("latency", 60, "Overview update latency", TYPE_INT,
	 "The number of seconds between successive updates of the "
	 "module's internal state from the Xenofarm database. The "
	 "lower the value, the higher the load on your poor dbm.");
}

static string default_db;
int latency;

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
      "<tr><th>Database</th><th>Project</th><th>Next update</th>"
      "<th>New build</th><th>Last changed</th><th>info</th></tr>\n";
    foreach(indices(projects), string db) {
      array(Project) projs = projects[db];
      foreach(projs, Project p) {
	int t = p->next_update - time();
	ret += "<tr><td>" + db + "</td><td>" + p->project;
	if (p->branch != "HEAD") {
	  ret += " " + p->branch;
	}
	if (p->remote != "origin") {
	  ret += " (" + p->remote + ")";
	}
	ret += "</td><td>" +
	  (t>0 ? "in " + t + " s" : "next page reload") + "</td><td>" +
	  fmt_timespan(time()-p->new_build) + " ago</td><td>" +
	  fmt_timespan(time()-p->last_changed) + " ago</td>" +
	  sprintf("<td>%O</td>", p) + "</tr>\n";
      }
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

static string my_min(array in, string ... more) {
  if(more) in = in + more;
  if(!sizeof(in)) return "NONE";
  if(has_value(in, "FAIL")) return "FAIL";
  if(has_value(in, "WARN")) return "WARN";
  return "PASS";
}

static class Build
{
  Project project;
  int(0..) id;
  int(0..) build_datetime;
  string export; // One of { "FAIL" "WARN" "PASS" }

  // The summary of the build, min( results )
  string summary;

  // Textual representation of build_datetime.
  string str_build_datetime;

  void create(int(0..) _id, int(0..) _build_datetime,
	      string _export, Project _project) {

    id = _id;
    build_datetime = _build_datetime;
    export = _export;
    project = _project;

    summary = export;
    if(summary=="PASS") summary="NONE";
    str_build_datetime = fmt_time(build_datetime);
  }

  static string _sprintf(int t) {
    switch(t) {
    case 'O': return sprintf("Build(%d, %d /* %s */,\n%s      %s, %O)",
		      id, build_datetime, str_build_datetime,
                             export, project, project);
    case 't': return "Build";
    }
  }

  //! client:status
  mapping(int(0..):string) results = ([]);

  //! client:warnings
  mapping(int(0..):int(0..)) warnings = ([]);

  //! client:time
  mapping(int(0..):int(0..)) time_spent = ([]);

  //! client: task: { status, time, warnings }
  mapping(int(0..):mapping(int(0..):array)) task_results = ([]);

  mapping(string:int(0..)) status_summary = ([]);

  int(0..1) update_results(Sql.Sql xfdb)
  {
    foreach(values(project->tasks), Task task) {
      string path = task->path;
      if(!status_summary[path]) status_summary[path]=0;
    }

    array res = xfdb->query("SELECT system,task,status,warnings,time_spent "
			    "FROM task_result WHERE build = %d", id);
    int changed;
    int build_task = project->build_task;
    int cov_build_task = project->cov_build_task;
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

      if(x->status!="FAIL") status_summary[ project->tasks[task]->name ]++;
    }

    foreach(new_systems, int system) {
      mapping tasks = task_results[system];
      array status = tasks[build_task];
      array data = values(tasks);

      if(build_task) {
	if (zero_type(status)) {
	  status = tasks[cov_build_task];
	}
	if(!status)
	  results[system] = "FAIL";
	else if(status[0]=="PASS") {
	  string status = my_min( column(data,0) );
	  if(status=="FAIL") status="WARN";
	  results[system] = status;
	}
	else
	  results[system] = status[0];
      }
      else
	results[system] = my_min( column(data,0) );

      time_spent[system] = 0;
      foreach((array)project->tasks, [int no, Task task])
	if(!task->has_parent()) // count recursive time spans once only
	  time_spent[system] += tasks[no] && tasks[no][1];

      warnings[system] = `+( @column(data,2) );
    }

    if(changed)
      summary = my_min( values(results), export );

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

  array(mapping(string:int|string))
      | mapping(string:int|string) get_result_entities(void|int client_no)
  {
    if(!zero_type(client_no))
      return ([ "status" : results[client_no]||"NONE",
		"system" : client_no,
		"build" : id,
		"warnings" : warnings[client_no],
		"time" : str_build_datetime,
		"timespan" : fmt_timespan(time_spent[client_no]),
      ]);
    array ret = ({});
    foreach(sort(indices(project->clients)), client_no)
      ret += ({ ([ "status" : results[client_no]||"NONE",
		   "system" : client_no,
		   "build" : id,
		   "warnings" : warnings[client_no],
		   "time" : str_build_datetime,
		   "timespan" : fmt_timespan(time_spent[client_no]),
      ]) });
    return ret;
  }

  mapping(string:int|string) get_task_entities(int client, int task) {
    Task tobj = project->tasks[task];
    string name = (string)task;
    string pname = "Task #" + name;
    array(string) path = ({});
    if (tobj && tobj->name != "") {
      name = tobj->name;
      pname = String.capitalize(replace(tobj->name, "_", " "));
      path = tobj->path/"-";
    }
    mapping(string:int|string) ret = ([ "task_id": task,
					"name": name,
					"pname": pname,
					"path": path,
					"status" : "NONE",
					"time_spent" : 0,
					"pretty_time_spent" : fmt_timespan(0),
					"warnings" : 0 ]);
    array|mapping t = task_results[client];
    if(!t) return ret;
    t = t[task];
    if(!t) return ret;
    return ([ "task_id": task,
	      "name": name,
	      "pname": pname,
	      "path": path,
	      "status" : t[0],
	      "time_spent": t[1],
	      "pretty_time_spent": fmt_timespan(t[1]),
	      "warnings": t[2],
    ]);
  }

  array(int) list_machines() {
    return indices(results);
  }

  mapping(string:int|string) get_details(int client) {
    return ([ "result" : results[client],
	      "warnings" : warnings[client],
	      "time" : fmt_timespan(time_spent[client]),
	      "build_id" : (string)id,
	      "machine_id" : (string)client,
   ]) | project->clients[client]->entities();
  }
}

//!
static class ClientConfig
{
  //! the various info related to a particular client configuration
  string name, sysname, release, version, machine, test;
  int id;

  void create(mapping info)
  {
    id = (int)info->id;
    name = info->name;
    test = info->testname;
    sysname = info->sysname;
    release = info->release;
    version = info->version;
    machine = info->machine;
  }

  //! render info entities for this client
  mapping entities()
  {
    string platform = sysname + " " + release + " " + machine;
    return ([ "name":name,
	      "sysname":sysname,
	      "release":release,
	      "id":id,
	      "version" : version,
	      "machine" : machine,
	      "test" : test,
	      "platform" : platform + (test=="" ? "" : " " + test),
    ]);
  }

  string _sprintf(int type)
  {
    switch(type) {
    case 't': return "ClientConfig";
    case 'O': sprintf("ClientConfig(/* %s */)", name);
    }
  }
}

class Task (string name, int id, int sort_order) {
  int(0..1) is_leaf = 1;
  string path;
  array children = ({});

  void add_child(Task child) {
    children += ({ child });
    is_leaf = 0;
  }

  int(0..1) has_parent() { return !!sizeof(children); }

  void init(void|string ppath) {
    if(ppath)
      path = ppath+"-"+name;
    else
      path = name;
    children->init(path);
  }

  int order(int i) {
    sort_order = i++;
    sort(children->sort_order, children);
    foreach(children, Task t)
      i = t->order(i);
    return i;
  }
}

static class Project(string db, string project, string remote, string branch)
{
  //! latest build first, length limited by module variable "results"
  array(Build) builds = ({});

  //! the id of the corresponding build in @[builds]
  array build_indices = ({});

  //! client:client configuration info
  mapping(int(0..):ClientConfig) clients = ([]);

  //! task no:Task
  mapping(int:Task) tasks = ([]);
  int build_task;
  int cov_build_task;
  array(int) ordered_leaf_tasks = ({});

  int new_build; // the last time we found a new build in the database
  int last_changed; // ditto when we noticed a change in the matrix
  int next_update; // we won't update our state until we reach this time

#ifdef THREADS
  Thread.Mutex update_mux = Thread.Mutex();
#endif

  string _sprintf(int t) {
    switch(t) {
      case 'O': return sprintf("Project(/* %d builds */)", sizeof(builds));
      case 't': return "Project";
    }
  }

  //! Updates the module's internal state with recent activity by the
  //! packager daemons and the result parsers, as logged in the
  //! Xenofarm database of choice.
  //! @returns
  //!   The number of seconds left until the next update will happen.
  int update_builds(Sql.Sql xfdb)
  {
#ifdef THREADS
    mixed update_lock = update_mux->lock();
#endif
    // Only update internal state once a minute
    int now = time(1);
    latency = query("latency");
    if(next_update < now)
      next_update = time() + latency;
    else
      return next_update - now;

    int latest_build_id;
    if(sizeof(builds))
      latest_build_id = builds[0]->id;

    // Get all tasks
    array new = xfdb->query("SELECT id,name,parent,sort_order FROM task "
			    "ORDER BY parent");
    // Note that we assume that the list of tasks never shrinks. If it
    // does, the module has to be reloaded.
    if(sizeof(tasks)!=sizeof(new)) {
      array top = ({});
      foreach(new, mapping res) {
	string name = res->name;
	Task t = Task(name, (int)res->id, (int)res->sort_order);
	int parent = (int)res->parent;
	if(!parent)
	  top += ({ t });
	else
	  tasks[ parent ]->add_child( t );
	tasks[ t->id ] = t;
	if(name=="build") build_task = (int)res->id;
	if(name=="cov-build") cov_build_task = (int)res->id;
      }
      // Initialize paths
      top->init();

      // Set sort order
      sort(top->sort_order, top);
      int i = 1;
      foreach(top, Task t)
	i = t->order(i);

      // Get the leaf tasks in order.
      array temp = values(tasks);
      temp = filter(temp, lambda(Task t) { return t->is_leaf; });
      sort(temp->sort_order, temp);
      ordered_leaf_tasks = temp->id;
    }

    // Add new builds
    new = xfdb->query("SELECT id,time,export"
		      " FROM build WHERE id > %d"
		      " AND project = %s AND branch = %s AND remote = %s"
		      " ORDER BY time DESC LIMIT %d",
		      latest_build_id,
		      project, branch, remote,
		      query("results"));

    if(sizeof(new)) {
      new_build = time();
      builds = map(new, lambda(mapping in) {
			  return Build( (int)in->id, (int)in->time,
					in->export, this_object() );
			}) + builds;
      build_indices = builds->id;
    }

    // Trim the number of builds
    if(sizeof(builds)>query("results")) {
      builds = builds[..query("results")-1];
      build_indices = builds->id;
    }

    // Update featured builds
    int changed = `+( 0, @builds->update_results(xfdb) );
    if(!changed)
      return latency;
    last_changed = time();

    // Update client info about all recently involved clients
    multiset m = (multiset)Array.uniq( `+( @builds->list_machines() ) );
    foreach(indices(clients), int client_no)
      if( m[client_no] )
	;//m[client_no] = 0; // we already have info about this client
      else
	m_delete(clients, client_no); // don't keep the info any more

    foreach(xfdb->query("SELECT id,name,sysname,`release`,version,"
			"machine,testname FROM system"/*
			"WHERE id IN (%s)", (array(string))m * ","*/),
	    mapping info)
      clients[(int)info->id] = ClientConfig(info);

    return latency; // [until] next time, gadget...
  }

  Build get_build(int id) {
    id = search(build_indices, id);
    if(id == -1) return 0;
    return builds[id];
  }
}

// Really static, but we might want to access this variable
// from the Hilfe protocol.
mapping(string:array(Project)) projects = ([]);

static Project low_get_project(string db,
			       string project, string remote, string branch)
{
  array(Project) projs = projects[db];
  if (projs) {
    foreach(projs, Project p) {
      if ((p->project == project) && (p->branch == branch) &&
	  (p->remote == remote)) {
	// Found.
	return p;
      }
    }
    projs += ({ Project(db, project, remote, branch) });
  } else {
    projs = ({ Project(db, project, remote, branch) });
  }
  projects[db] = projs;
  return projs[-1];
}

static Project get_project(RequestID id, mapping(string:string)|void args)
{
  Project p = id->misc->xenofarm_project;
  if (p) {
    foreach(({ "db", "project", "remote", "branch" }), string field) {
      if (args[field] && (args[field] != p[field])) {
	p = UNDEFINED;
	break;
      }
    }
    if (p) return p;
  }
  return low_get_project(args->db || id->misc->xenofarm_db || default_db,
			 args->project || query("default_project"),
			 args->remote || "origin",
			 args->branch || "HEAD");
}

//
// Tags
//

class TagXF_Update {
  inherit RXML.Tag;
  constant name = "xf-update";

  class Frame {
    inherit RXML.Frame;
    mapping vars = ([]);

    array do_enter(RequestID id)
    {
      Project p = get_project(id, args);
      string db = p->db;
      id->misc->xenofarm_db = db;
      id->misc->xenofarm_project = p;

      Sql.Sql xfdb;
      array error = catch(xfdb = DBManager.get(db, my_configuration(), 1));
      if(!xfdb)
	RXML.run_error("Couldn't connect to SQL server" +
		       (error ? ": " + error[0] : "") + "\n");
      CACHE(p->update_builds(xfdb));
      vars->updated = fmt_time(p->next_update-latency);
    }

    array do_return(RequestID id) {
      result = content;
      id->misc->xenofarm_db = 0;
      id->misc->xenofarm_project = 0;
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
    Project p = get_project(id, m);

    if(int id = (int)m_delete(m, "id")) {
      ClientConfig c = p->clients[id];
      if(c) return ({ c->entities() });
      return ({});
    }

    // Remove clients whose last max-columns builds were all white
    if(int maxcols = (int)m_delete(m, "recency"))
    {
      array(mapping) result = ({});
      foreach(sort(indices(p->clients)), int client_no)
      {
	ClientConfig c = p->clients[client_no];
	array status = p->builds->get_result_entities( client_no )->status;
	if(sizeof(status[..maxcols-1] - ({ "NONE" })))
	  result += ({ c->entities() });
      }
      return result;
    }

    array entities = values(p->clients)->entities();
#if 1 // A "select distinct" to, e g, list all clients with unique hostnames
    if(string order = m_delete(m, "sort"))
    {
      foreach(reverse(array_sscanf(order+",", "%{%[-]%s,%}")[0]),
	      [string direction, string variable])
      {
	sort(entities[variable], entities);
	if(direction == "-")
	  entities = reverse(entities);
      }
    }
    else
      sort(entities->platform, entities);
    if(m->distinct)
    {
      mapping(string:int) seen = ([]);
      array(mapping) distinct = ({ });
      foreach(entities, mapping e)
	if(!seen[e[m->distinct]]++)
	  distinct += ({ e });
      entities = distinct;
    }
#endif
    return entities;
  }
}


class TagEmitXF_Build {
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "xf-build";

  array(mapping) get_dataset(mapping m, RequestID id)
  {
    NOCACHE();
    Project p = get_project(id, m);
    array res = p->builds->get_build_entities();
    for(int i=1; i<sizeof(res); i++)
      res[i-1]["last-time"] = res[i]->time;

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
    Project p = get_project(id, m);
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

    if(m->results) {
      multiset ok = (multiset)(m->results/",");
      res = filter(res, lambda(mapping x) { return ok[x->status]; });
      m_delete(m, "results");
    }

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
      Project p = get_project(id, args);

      int build, client;
      if(args->id) {
	if( sscanf(args->id, "%d_%d", build, client)!=2 )
	  RXML.parse_error("Could not decode id (%O)\n", args->id);
      }
      else if(args->build && args->client) {
	build = (int)args->build;
	client = (int)args->client;
      }
      else
	RXML.parse_error("No build chosen (id or build+client).\n");

      Build b = p->get_build(build);
      if(!b) RXML.run_error("Selected build no longer available.\n");
      vars = b->get_details(client);
    }
  }
}

class TagEmitXF_Task {
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "xf-task";

  array(mapping) get_dataset(mapping m, RequestID id)
  {
    NOCACHE();
    Project p = get_project(id, m);

    int build, client;

    if(m->id) {
      if( sscanf(m->id, "%d_%d", build, client)!=2 )
	RXML.parse_error("Could not decode id (%O)\n", m->id);
    }
    if(m->build && m->client) {
      build = (int)m->build;
      client = (int)m->client;
    }
    if(build && client) {
      array(int|Task) list;
      if(m->tasks=="leafs")
	list = p->ordered_leaf_tasks;
      else if(m->tasks)
	list = (array(int))(m->tasks/"\n");
      else {
	list = values(p->tasks);
	sort(list->sort_order, list);
	list = list->id;
      }
      Build b = p->get_build(build);
      array ret = ({});
      foreach( list, int task) {
	ret += ({ b->get_task_entities(client, task) });
      }
      return ret;
    }

    array res = ({});
    foreach(indices(p->tasks), int id) {
      Task task = p->tasks[id];
      res += ({ ([ "id" : id,
		   "name" : task->name,
		   "pname" : String.capitalize(replace(task->name, "_", "&nbsp;")),
		   "path" : task->path,
		   "order" : task->sort_order,
		   "leaf" : task->is_leaf ? "yes" : "no"
      ]) });
    }
    if(!m->sort) {
      sort(res->order, res);
    }
    return res;
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
 Returns the time when the cahed table was updated.
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

<attr name='id' value='int'><p>
  If set, the emit will only return information about the machine with
  this id. Any recency attribute will be ignored.
</p></attr>

<attr name='distinct' value='string'><p>
  Filters away multiple occurrences of rows sharing the named column. This can
  be used to list all clients with unique hostnames for instance (stating the
  value \"machine\"). The other entities are picked from the first (according
  to the given sort order) column that had duplicates later on.
</p></attr>

</desc>", ([

  "&_.id;":#"<desc type='entity'><p>
  The numeric id of the client.
</p></desc>",

  "&_.name;":#"<desc type='entity'><p>
  The node name of the client. Typically what uname -n would return.
</p></desc>",

  "&_.sysname;":#"<desc type='entity'><p>
  The system name of the client. Typically what uname -s would return.
</p></desc>",

  "&_.release;":#"<desc type='entity'><p>
  The release of the client OS. Typically what uname -r would return.
</p></desc>",

  "&_.version;":#"<desc type='entity'><p>
  The version of the client OS. Typically what uname -v would return.
</p></desc>",

  "&_.machine;":#"<desc type='entity'><p>
  The machine name of the client. Typically what uname -m would return.
</p></desc>",

  "&_.test;":#"<desc type='entity'><p>
  The name of the test performed by the client.
</p></desc>",

  "&_.platform;":#"<desc type='entity'><p>
  The client system string. Essentially what uname -a would return. If
  the test is other than the default test, its name is appended to this
  string.
</p></desc>",
]) }),

  // ------------------------------------------------------------

  "emit#xf-build":({ #"<desc type='plugin'>
<p>
  Lists all the builds that is in the result table, which size is limited by
  the \"Number of results\" setting in the administration interface. A sum
  of the number of non-failing results for each task is available in an
  entity with the task name. E.g. the number of returned, non-failing results
  for build/compile is available in &amp;_.build-compile;.
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
  Can assume one of the values \"NONE\", \"FAIL\", \"WARN\" and \"PASS\".
</p></desc>",

  "&_.source;":#"<desc type='entity'><p>
  The result from the source package creation. Can assume one of the values
  \"FAIL\", \"WARN\" and \"PASS\".
</p></desc>",

  "&_.last-time;":#"<desc type='entity'><p>
  The timestamp of the previous build.
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
  \"NONE\", \"FAIL\", \"WARN\" and \"PASS\".
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

  "&_.build_id" : #"<desc attr='entity'><p>
  The numerical build id.
</p></desc>",

  "&_.machine_id" : #"<desc attr='entity'><p>
  The numerical machine id.
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
