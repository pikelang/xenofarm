#! /usr/bin/env pike

// Xenofarm result parser for the Pike 7.8 project
// By Martin Nilsson

inherit "result_parser.pike";

string pike_version = "7.8";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_8");

constant prog_id = "Xenofarm Pike 7.8 result parser \n";

