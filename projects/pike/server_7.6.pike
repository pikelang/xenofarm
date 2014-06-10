#! /usr/bin/env pike

// Xenofarm server for the Pike 7.6 project
// By Martin Nilsson

inherit "server.pike";

string pike_version = "7.6";
constant latest_pike_checkin =
  "http://pike.ida.liu.se/development/cvs/latest-Pike-7.6-commit";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_6");

constant prog_id = "Xenofarm Pike 7.6 server\n";
