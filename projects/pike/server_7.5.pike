#! /usr/bin/env pike

// Xenofarm server for the Pike 7.5 project
// By Martin Nilsson
// $Id: server_7.5.pike,v 1.1 2002/12/05 16:50:45 mani Exp $

inherit "server.pike";

string pike_version = "7.5";
constant latest_pike_checkin =
  "http://pike.ida.liu.se/development/cvs/latest-Pike-7.5-commit";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_5");

constant prog_id = "Xenofarm Pike 7.5 server\n"
"$Id: server_7.5.pike,v 1.1 2002/12/05 16:50:45 mani Exp $\n";
