#!/bin/sh

# Shell script to generate a simple result page.

output=/lysator/www/projects/xenofarm/argouml/result.html
url=http://www.lysator.liu.se/xenofarm/argouml/files/

cat <<EOF |
select id,name from task order by id;
select build.id, build.time, # $1, $2
system.id, # $3
system.name, system.sysname, system.release, "sysver", "sysmach",
# $4 - $8
task.name, # $9
task_result.status, task_result.warnings, task_result.time_spent, # $10-$12
system.testname, # $13
task.id # $14
from build, system, task, task_result
where build.id = task_result.build
and task_result.system = system.id
and task.id = task_result.task
order by build.id desc, system.id, task.id;
EOF
mysql --batch \
    -D argouml_xenofarm \
    -u linus -p`cat /home/linus/.argouml_xenofarm_mysql_password` |
sed -e '1d' |
/sw/local/bin/awk -F'	' '
BEGIN {
    print "<TITLE>Xenofarm results for ArgoUML</TITLE>";
    print "<H1>Build results for ArgoUML</H1>";
    print "This result was generated ", strftime("%a %b %d %H:%M:%S %Y");
    print "<TABLE BORDER=3>";
    tasknr = 0;
    seenlong = 0;
    linesintable = 0;
    heading = "<TR><TH>Java</TH>";
    print heading;
}
{ linesintable++; }
NF < 3 {
    tasknr++;
    task[$1] = tasknr;
    print "<TH>" $2 "</TH>";
    heading = heading "<TH>" $2 "</TH>";
}
NF > 3 && !seenlong {
    seenlong = 1;
    print "<TH>Host</TH>";
    print "</TR>";
    heading = heading "<TH>Host</TH></TR>";
    next;
}
NF > 3 {
    if (id != $1 || sys != $3) {
	if (before) {
            print before;
            for (i = 1; i <= tasknr; i++)
                if (value[i])
                {
                    print value[i];
                    value[i] = "";
                }
                else
                    print "<TD><BR></TD>";
            print after;
            before = ""; after = "";
        }
    }
    if (id != $1) {
	if (linesintable > 400)
	{
	    print "</TABLE><TABLE BORDER=3>";
	    print heading;
	    linesintable = 0;
	}
	printf "<TR><TH COLSPAN=%d>Build <A HREF=\"diffs.html#%s\">%s</A> from ", 2+tasknr, $1, $1;
	print strftime("%a %b %d %H:%M:%S %Y", $2), "</TH></TR>";
	id = $1;
    }
    sys = $3;
    before = "<TR><TD><A HREF=\"'$url'" $1 "_" $3 "\">" $13 "</A></TD>";
    args = " ALIGN=CENTER";
    contents = $10;
    if ($10 == "FAIL") args = args " bgcolor=#FF0000";
    if ($10 == "PASS") args = args " bgcolor=#00FF00";
    if ($10 == "WARN") {
        contents = $10 $11;
        args = args " bgcolor=#FFCC00";
    }
    contents = "<A HREF=\"'$url'" $1 "_" $3 "/" $9 ".log.html\" title=\"" sprintf("%02d:%02d:%02d", $12/3600, ($12/60)%60 , $12%60) "\" >" contents "</A>";
    value[task[$14]] = "<TD" args ">" contents "</TD>";
    after = "<TD>" $4 "(" $5 " "  $6 ")</TD></TR>";
}
END {
        if (before) {
            print before;
            for (i = 1; i <= tasknr; i++)
                if (value[i])
                {
                    print value[i];
                    value[i] = "";
                }
                else
                    print "<TD><BR></TD>";
            print after;
            before = ""; after = "";
        }
    print "</TABLE>"; 
    print "For details about ArgoUML visit ";
    print "<a href=\"http://argouml.tigris.org/\">the ArgoUML site</a>."; 
}' |
cat > $output
