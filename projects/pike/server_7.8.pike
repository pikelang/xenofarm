#! /usr/bin/env pike

// Xenofarm server for the Pike 7.7 project
// By Martin Nilsson
// $Id: server_7.8.pike,v 1.1 2010/07/11 14:21:47 zino Exp $

inherit "server.pike";

string pike_version = "7.8";
int min_build_distance = 60*60*1;	// Reduced to one hour.
constant latest_pike_checkin =
  "http://pike.ida.liu.se/development/cvs/latest-Pike-7.8-commit";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_8");

constant prog_id = "Xenofarm Pike 7.8 server\n"
"$Id: server_7.8.pike,v 1.1 2010/07/11 14:21:47 zino Exp $\n";
