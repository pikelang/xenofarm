#! /usr/bin/env pike

// Xenofarm result parser for the Pike 7.3 project
// By Martin Nilsson
// $Id: result_parser_7.3.pike,v 1.1 2002/11/30 03:36:06 mani Exp $

inherit "result_parser.pike";

string pike_version = "7.3";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_3");

constant prog_id = "Xenofarm Pike 7.3 result parser \n"
"$Id: result_parser_7.3.pike,v 1.1 2002/11/30 03:36:06 mani Exp $\n";

