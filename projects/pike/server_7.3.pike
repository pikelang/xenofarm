#! /usr/bin/env pike

// Xenofarm server for the Pike 7.3 project
// By Martin Nilsson
// $Id: server_7.3.pike,v 1.2 2002/12/01 14:39:15 mani Exp $

inherit "server.pike";

string pike_version = "7.3";
constant latest_pike_checkin =
  "http://pike.ida.liu.se/development/cvs/latest-Pike-7.3-commit";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_3");

constant prog_id = "Xenofarm Pike 7.3 server\n"
"$Id: server_7.3.pike,v 1.2 2002/12/01 14:39:15 mani Exp $\n";
