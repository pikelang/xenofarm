// This is a Roxen WebServer module.
// Copyright 2002 Martin Nilsson

#include <module.h>
inherit "module";

constant cvs_version = "$Id: xenofarm_ui.pike,v 1.3 2002/07/16 15:41:00 mani Exp $";
constant thread_safe = 1;
constant module_type = MODULE_TAG;
constant module_name = "Xenofarm UI module";
constant module_doc  = "...";
constant module_unique = 1;

void create() {

  defvar( "xfdb", "mysql://localhost/xenofarm", "Xenofarm database",
	  TYPE_STRING, "The build/result database" );
}

static Sql.sql xfdb;

void start() {
  xfdb = Sql.sql( query("xfdb") );
}

constant WHITE = 0;
constant RED = 1;
constant YELLOW = 2;
constant GREEN = 3;

string fmt_time(int t) {
    mapping m = gmtime(t);
    return sprintf("%d-%02d-%02d %02d:%02d:%02d",
		   m->year+1900, m->mon+1, m->mday,
		   m->hour, m->min, m->sec);
}

static class Build {

  int(0..) id;
  int(0..) buildtime;
  string str_buildtime;

  void create(int(0..) _id, int(0..) _buildtime) {
    id = _id;
    buildtime = _buildtime;
    str_buildtime = fmt_time(buildtime);
  }

  // client:status
  mapping(int(0..):string) results = ([]);

  mapping(string:int(0..)) status_summary = ([
    "results" : 0,
    "build" : 0,
    "verify" : 0,
    "export" : 0,
  ]);

  int(0..3) summary;

  constant ratings = ([
    "failed" : RED,
    "built" : YELLOW,
    "verified" : YELLOW,
    "exported" : GREEN
  ]);

  constant color = ([
    WHITE : "white",
    RED : "red",
    YELLOW : "yellow",
    GREEN : "green"
  ]);

  int(0..1) update_results() {
    array res = xfdb->query("SELECT system,status FROM result WHERE build = "+id);
    int changed;
    foreach(res, mapping x) {
      int system = (int)x->system;
      if(results[system]) continue;
      results[system] = x->status;
      changed=1;

      switch(x->status) {
      case "exported":
	status_summary->export++;
      case "verified":
	status_summary->verify++;
      case "built":
	status_summary->build++;
      case "failed":
      default:
	status_summary->results++;
      }
    }
    if(changed)
      summary = min( @ratings[values(results)[*]] );
    return changed;
  }

  mapping(string:int|string) get_build_entities() {
    return ([ "id":id,
	      "time":str_buildtime,
	      "summary":color[summary],
    ]) + status_summary;
  }

  array(mapping(string:int|string)) get_result_entities() {
    array ret = ({});
    foreach(indices(machines), int system)
      ret += ({ ([ "status" : color[ratings[results[system]]] ]) });
    return ret;
  }

  array(int) list_machines() {
    return indices(results);
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
  if(latest_update < time(1))
    latest_update = time()+60;
  else
    return;

  // Add new builds

  int latest_build;
  if(sizeof(builds))
    latest_build = builds[0]->buildtime;

  array new = xfdb->query("SELECT id,time FROM build WHERE time > "+latest_build+
			  " ORDER BY time DESC LIMIT 10");

  if(sizeof(new)) {
    builds = map(new, lambda(mapping in) {
			return Build((int)in->id, (int)in->time);
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
    array data = xfdb->query("SELECT name,platform FROM system WHERE id="+machine);
    machines[machine] = data[0]->name;
    platforms[machine] = data[0]->platform;
  }

  array me = ({});
  foreach(sort(indices(machines)), int machine)
    me += ({ ([ "name":machines[machine], "platform":platforms[machine] ]) });
  machine_entities = me;
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

    array do_enter() {
      if(!xflock++)
	update_builds();
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
      vars = ([]);
    }
  }
}

/*

<xf-update>

<table border="1" cellspacing="0" cellpadding="2">

<tr><th>Build</th>
<emit source="xf-machine">
<th>&_.name; (&_.platform;)</th>
</emit>
</tr>

<emit source="xf-build">

<tr><td>&_.time;</td>
<emit source="xf-result" build="&_.id;">
<td>&_.status;</td>
</emit>
</tr>

</emit>
</table>

<i>Updated &_.updated;</i>
</xf-update>

*/
