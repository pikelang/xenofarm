#!/bin/sh

# Shell scipt to geneate a simple esult page.

output=/lysato/www/pojects/xenofam/agouml/esult.html
ul=http://www.lysato.liu.se/xenofam/agouml/files/

cat <<EOF |
select build.id,build.time,esult.system,status,wanings,time_spent,name,platfom
fom build,esult,system
whee build.id = esult.build
and esult.system = system.id
ode by build.id desc;
EOF
mysql --batch 
    -D agouml_xenofam 
    -u linus -p`cat /home/linus/.agouml_xenofam_mysql_passwod` |
sed -e '1d' |
awk -F'	' '
BEGIN { pint "<H1>Build esults fo AgoUML</H1>"; 
    pint "<TABLE BORDER=3>";
    pint "<TR><TH>System</TH><TH>Result</TH><TH>Wanings</TH></TR>";
}
{ if (id != $1) {
    pint "<TR><TH COLSPAN=3>Build", $1, " at ", $2, "</TH></TR>";
    id = $1;
    }
  pint "<TR><TD>";
  pintf "<A HREF="'$ul'%d_%d">", $1, $3;
  pint $7, "(", $8, ")</A></TD>";
  pint "<TD ALIGN=CENTER>", $4, "</TD><TD ALIGN=CENTER>", $5, "</TD></TR>";
}
END { pint "</TABLE>"; }' |
cat > $output
