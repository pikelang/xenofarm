#! /usr/bin/env pike

// Xenofarm result parser for the Pike 7.4 project
// By Martin Nilsson

inherit "result_parser.pike";

string pike_version = "7.4";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_4");

constant prog_id = "Xenofarm Pike 7.4 result parser \n";

