#! /usr/bin/env pike

// Xenofarm result parser for the Pike 7.7 project
// By Martin Nilsson
// $Id: result_parser_7.7.pike,v 1.1 2004/04/26 00:40:57 mani Exp $

inherit "result_parser.pike";

string pike_version = "7.7";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_7");

constant prog_id = "Xenofarm Pike 7.7 result parser \n"
"$Id: result_parser_7.7.pike,v 1.1 2004/04/26 00:40:57 mani Exp $\n";

