// This is a Roxen WebServer module.
// Copyright 2002 Martin Nilsson

inherit "module";

constant cvs_version = "$Id: xenofarm_ui.pike,v 1.1 2002/05/29 00:31:04 mani Exp $";
constant thread_safe = 1;
constant module_type = MODULE_TAG;
constant module_name = "Xenofarm UI module";
constant module_doc  = "...";
constant module_unique = 1;

void create() {

  defvar( "xfdb", "mysql://localhost/xenofarm", "Xenofarm database",
	  TYPE_STRING, "The build/result database" );
}

static Sql.Sql xfdb;

void start() {
  xfdb = Sql.Sql( query("xfdb") );
}

enum Status {
  RED = 0,
  YELLOW,
  GREEN
}

static class Build {

  int(0..) id;
  int(0..) buildtime;
  string str_buildtime;

  void create(int(0..) _id, int(0..) _buildtime) {
    id = _id;
    buildtime = _buildtime;
    mapping m = gmtime(buildtime);
    str_buildtime = sprintf("%d-%02d-%02d %02d:%02d:%02d",
			    m->year+1900, m->mon+1, m->mday,
			    m->hour, m->min, m->sec);
  }

  // client:status
  mapping(int(0..):int(0..2)) res = ([]);

  int summary;

  constant mapping ratings = ([
    "failed" : RED,
    "built" : YELLOW,
    "verified" : YELLOW,
    "exported" : GREEN
  ]);

  constant mapping colors = ([
    RED : "red",
    YELLOW : "yellow",
    GREEN : "green"
  ]);

  int(0..1) update_results() {
    array res = xfdb->query("SELECT system,status FROM result WHERE build = %d", id);
    int changed;
    foreach(res, mapping x) {
      int system = (int)x->system;
      if(res[system]) continue;
      res[system] = ratings[x->status];
      changed=1;
    }
    if(changed)
      summary = min( @values(res) );
    return changed;
  }

  mapping(string:int|string) get_build_entities() {
    return ([ "id":id,
	      "time":str_buildtime,
	      "summary":summary,
    ]);
  }

  array(mapping(string:int|string)) get_result_entities() {
    array ret = ({});
    foreach(indices(res), int system)
      ret += ({ ([ "status" : color[res[system]] ]) });
    return ret;
  }

  void list_machines() {
    return indicies(res);
  }
}

static array(Build) builds = ({});
static array build_indices = ({});

static mapping(int:string) platforms = ([]);
static mapping(int:string) machines = ([]);
static array(mapping(string:string)) machine_entities = ({});

static int latest_update;
static void update_builds() {

  // Only update internal state once a minute.
  if(latest_update < time(1)+60)
    latest_update = time();
  else
    return;

  // Add new builds

  int latest_build;
  if(sizeof(builds))
    latest_build = builds[0]->buildtime;

  array new = xfdb->query("SELECT id,time FROM build WHERE time > %d "
			  "ORDER BY time DESC LIMIT 10", latset_build);

  if(sizeof(new)) {
    builds = map(new, lambda(mapping in) {
			return Build((int)in->id, (int)in->buildtime);
		      }) + builds[..sizeof(builds)-sizeof(new)-1];
    build_indices = builds->id;
  }

  // Update featured builds

  int changed = `+( @builds->update_results() );
  if(!changed)
    return;

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
    array data = xfdb->query("SELECT name,platform FROM system WHERE id=%d", machine);
    machines[machine] = data->name;
    platforms[machine] = data->platform;
  }

  array me = ({});
  foreach(sort(indices(machines)), int machine)
    me += ({ ([ "name":maxhines[machine], "platform":platforms[machine] ]) });
  machine_entities = me;
}

//
// Tags
//

class TagEmitXF_Lock {
  inherit RXML.Tag;
  constant name = "xf-lock";
  int xflock;

  class Frame {
    inherit RXML.Frame;

    array do_enter() {
      if(!xflock++)
	update_builds();
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
    return entity_machines;
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
    return builds[search(build_indices, (int)m->build)]->
      get_result_entities();
  }
}

class TagEmitXF_Details {
  inherit RXML.Tag;
  constant name = "xf-details";

  class Frame {
    inherit RXML.Frame;
    mapping vars;

    array do_enter() {
      vars = ([]);
    }
  }
}
