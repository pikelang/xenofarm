#!/bin/sh

# Shell script to generate a page of differences.

output=/lysator/www/projects/xenofarm/argouml/diffs.html
viewcvsurl=http://argouml.tigris.org/source/browse/argouml

cat <<EOF |
select b2.build, b1.filename, b1.revision, b2.revision
from files as b1, files as b2
where b1.build = b2.build - 1
and b1.filename = b2.filename
and b1.revision != b2.revision
order by b2.build desc, b2.filename;
EOF
mysql --batch \
    -D argouml_xenofarm \
    -u linus -p`cat /home/linus/.argouml_xenofarm_mysql_password` |
sed -e '1d' |
/sw/local/bin/awk -F'	' '
BEGIN {
    print "<TITLE>Xenofarm diffs between builds</TITLE>";
    print "<H1>Xenofarm diffs between builds</H1>";
    print "This result was generated ", strftime("%a %b %d %H:%M:%S %Y");
    print "<TABLE BORDER=3>";
    print "<TR><TH>Build</TH><TH>Diffs</TH></TR>";
}
{
    if (seenbuild != $1) {
        if (seenbuild != "") {
	    print "</PRE>";
	    print "</TD></TR>";
	}

	seenbuild = $1;
	printf "<TR><TD VALIGN=TOP><A NAME=\"%s\">%s</A></TD><TD VALIGN=TOP>\n", $1, $1;
	print "Changed files since previous version:";
	print "<PRE>";
    }

    printf "<A HREF=\"%s/%s.diff?r1=%s&r2=%s\">%s</A>\n", url, $2, $3, $4, $2;
}
END {
    print "</PRE>";
    print "</TD></TR>";
    print "</TABLE>";
}' url=$viewcvsurl |
cat > $output.new
mv $output.new $output


