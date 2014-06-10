#! /usr/bin/env pike

// Xenofarm result parser for the Pike 7.6 project
// By Martin Nilsson

inherit "result_parser.pike";

string pike_version = "7.6";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_6");

constant prog_id = "Xenofarm Pike 7.6 result parser \n";

