#! /usr/bin/env pike

// Xenofarm result parser for the Pike 7.7 project
// By Martin Nilsson

inherit "result_parser.pike";

string pike_version = "7.7";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_7");

constant prog_id = "Xenofarm Pike 7.7 result parser \n";

