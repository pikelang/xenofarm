#! /usr/bin/env pike

// Xenofarm result parser for the Pike 7.6 project
// By Martin Nilsson
// $Id: result_parser_7.6.pike,v 1.1 2004/04/26 00:40:57 mani Exp $

inherit "result_parser.pike";

string pike_version = "7.6";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_6");

constant prog_id = "Xenofarm Pike 7.6 result parser \n"
"$Id: result_parser_7.6.pike,v 1.1 2004/04/26 00:40:57 mani Exp $\n";

