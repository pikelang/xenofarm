#! /usr/bin/env pike

// Xenofarm server for the Pike 7.4 project
// By Martin Nilsson
// $Id: server_7.4.pike,v 1.2 2003/07/11 16:00:39 mani Exp $

inherit "server.pike";

string pike_version = "7.4";
constant latest_pike_checkin =
  "http://pike.ida.liu.se/development/cvs/latest-Pike-7.4-commit";

#ifdef NILSSON
Sql.Sql xfdb = Sql.Sql("mysql://localhost/xenofarm");
#else
Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_4");
#endif /* NILSSON */

constant prog_id = "Xenofarm Pike 7.4 server\n"
"$Id: server_7.4.pike,v 1.2 2003/07/11 16:00:39 mani Exp $\n";
