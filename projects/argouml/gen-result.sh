#!/bin/sh

# Shell script to generate a simple result page.

output=/lysator/www/projects/xenofarm/argouml/result.html
url=http://www.lysator.liu.se/xenofarm/argouml/files/

cat <<EOF |
select build.id,build.time,result.system,status,warnings,time_spent,name,platform
from build,result,system
where build.id = result.build
and result.system = system.id
order by build.id desc;
EOF
mysql --batch \
    -D argouml_xenofarm \
    -u linus -p`cat /home/linus/.argouml_xenofarm_mysql_password` |
sed -e '1d' |
awk -F'	' '
BEGIN { print "<H1>Build results for ArgoUML</H1>"; 
    print "This result was generated ", strftime("%a %b %d %H:%M:%S %Y");
    print "<TABLE BORDER=3>";
    print "<TR><TH>System</TH><TH>Result</TH><TH>Warnings</TH>";
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
  print $8, "</A></TD>";
  print "<TD ALIGN=CENTER>", $4, "</TD><TD ALIGN=CENTER>", $5, "</TD>";
  print "<TD>", $7, "</TD>";
  print "</TR>";
}
END { print "</TABLE>"; }' |
cat > $output
