#! /usr/bin/env pike

// Xenofarm result parser for the Pike 7.5 project
// By Martin Nilsson
// $Id: result_parser_7.5.pike,v 1.1 2002/12/05 16:50:45 mani Exp $

inherit "result_parser.pike";

string pike_version = "7.5";

Sql.Sql xfdb = Sql.Sql("mysql://rw@:/pike/sw/roxen"
		       "/configurations/_mysql/socket/pikefarm_7_5");

constant prog_id = "Xenofarm Pike 7.5 result parser \n"
"$Id: result_parser_7.5.pike,v 1.1 2002/12/05 16:50:45 mani Exp $\n";

