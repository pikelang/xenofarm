#!/bin/sh

# Shell script to generate a simple result page.

output=/lysator/www/projects/xenofarm/argouml/result.html
url=http://www.lysator.liu.se/xenofarm/argouml/files/

cat <<EOF |
select build.id, build.time, # $1, $2
system.id, # $3
system.name, system.sysname, system.release, system.version, system.machine,
# $4 - $8
task.name, # $9
task_result.status, task_result.warnings, task_result.time_spent, # $10-$12
system.testname # $13
from build, system, task, task_result
where build.id = task_result.build
and task_result.system = system.id
and task.id = task_result.task
order by build.id desc, task.id, system.name;
EOF
mysql --batch \
    -D argouml_xenofarm \
    -u linus -p`cat /home/linus/.argouml_xenofarm_mysql_password` |
sed -e '1d' |
/sw/local/bin/awk -F'	' '
BEGIN { print "<H1>Build results for ArgoUML</H1>"; 
    print "This result was generated ", strftime("%a %b %d %H:%M:%S %Y");
    print "<TABLE BORDER=3>";
    print "<TR><TH>Target</TH><TH>Result</TH><TH>Warnings</TH>";
    print "<TH>Host</TH>";
    print "</TR>";
}
{ if (id != $1) {
    print "<TR><TH COLSPAN=4>Build", $1, " from ";
    print strftime("%a %b %d %H:%M:%S %Y", $2), "</TH></TR>";
    id = $1;
    }
  print "<TR><TD>";
  printf "<A HREF=\"'$url'%d_%d\">", $1, $3;
  print $13, $9, "</A></TD>";
  print "<TD ALIGN=CENTER>", $10, "</TD><TD ALIGN=CENTER>", $11, "</TD>";
  print "<TD>", $4, "(", $5, $6, ")", "</TD>";
  print "</TR>";
}
END { print "</TABLE>"; }' |
cat > $output
