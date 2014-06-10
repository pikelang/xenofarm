#! /usr/bin/env pike

// Xenofarm server for the Pike 7.7 project
// By Martin Nilsson

inherit "server.pike";

string pike_version = "7.7";
int min_build_distance = 60*60*1;      // Reduced to one hour.
constant latest_pike_checkin =
  "http://pike.ida.liu.se/development/cvs/latest-Pike-7.7-commit";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_7");

constant prog_id = "Xenofarm Pike 7.7 server\n";
