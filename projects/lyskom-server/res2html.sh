#!/bin/sh
# Who needs a Roxen?  Who needs a database?
build=$1
input=/lysator/www/projects/xenofarm/lyskom-server/files
output=/lysator/www/user-pages/ceder/xeno/
url=http://www.lysator.liu.se/xenofarm/lyskom-server/files/
tmp=/lysator/www/user-pages/ceder/xeno/tmp
rm -rf $tmp
mkdir $tmp
for builddir in $input/${build}_*
do
  awk '$1 == "Begin" && NF == 2 { if (prev) { print prev, $2 } prev=$2 }' \
      < $builddir/mainlog.txt >> $tmp/tsort.in
done
tsort < $tmp/tsort.in > $tmp/tasks

exec 7> $output/$build.html
cat <<EOF >&7
<html><head><title>lyskom-server build $build Xenofarm results</title><head>
<body>
<h1>lyskom-server build $build Xenofarm results</h1>
This build overview was collected `date`.  Results from other
machines may come in later.

<table border="1">
<tr>
<th>Machine</th>
EOF
sed -e 's/^/<th>/' -e 's_$_</th>_' < $tmp/tasks >&7
echo '</tr>' >&7

for buildno in `cd $input && ls -vd ${build}_*`
do
    builddir=$input/$buildno
    echo "<tr><th><a href=\"$url/$buildno/\">" >&7
    sed -e '1s_$_<br>_' < $builddir/machineid.txt >&7
    echo "</a></th>" >&7
    for task in `cat $tmp/tasks`
    do
      color=white
      [ -f $builddir/$task.pass ] && color=green
      [ -f $builddir/$task.fail ] && color=red
      echo "<td><a href=\"$url/$buildno/${task}log.txt\"><img border=0 src=\"http://130.236.214.222/pikefarm/${color}_button.gif\"></a></td>" >&7
    done
    echo '</tr>' >&7
done
echo '</table></body></html>' >&7
