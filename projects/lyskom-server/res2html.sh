#!/bin/sh
# Who needs a Roxen?  Who needs a database?
# Well, to get the build time, the database is needed.  Sigh.
build=$1
input=/lysator/www/projects/xenofarm/lyskom-server/files
output=/lysator/www/user-pages/ceder/xeno/
url=http://www.lysator.liu.se/xenofarm/lyskom-server/files
tmp=/lysator/www/user-pages/ceder/xeno/tmp

rm -f $tmp/tsort.in

for builddir in $input/${build}_*
do
  awk '$1 == "Begin" && NF == 2 { if (prev) { print prev, $2 } prev=$2 }' \
      < $builddir/mainlog.txt >> $tmp/tsort.in
done
tsort < $tmp/tsort.in > $tmp/tasks

now=`date "+%Y-%m-%d %H:%M:%S"`
buildtime=`mysql --batch -e 'select time from build where id='$build -D lyskom_server_xenofarm -p\`cat /home/ceder/.xeno-mysql-pwd\`|sed 1d`
pretty=`pike -e 'write(Calendar.Second((int)argv[1])->format_time()+"\n");' $buildtime`


exec 7> $output/$build.html
cat <<EOF >&7
<html><head><title>lyskom-server build $build Xenofarm results</title><head>
<body>

<h1>lyskom-server build $build Xenofarm results</h1>
This build overview was collected $now.  Results from other
machines may come in later.

<p>Build time: $pretty

<table border="1">
<tr>
<th>Machine</th>
EOF
sed -e 's/^/<th>/' -e 's_$_</th>_' < $tmp/tasks >&7
echo '</tr>' >&7

green=0
yellow=0
red=0
white=0
result=0

for buildno in `cd $input && ls -vd ${build}_*`
do
    builddir=$input/$buildno
    echo "<tr><td><a href=\"$url/$buildno/\">" >&7
    sed -e '1s_$_<br>_' < $builddir/machineid.txt >&7
    echo "</a></td>" >&7
    status=white
    for task in `cat $tmp/tasks`
    do
      if [ -f $builddir/$task.fail ]
      then
          color=red
	  status=red
      elif [ -f $builddir/$task.warn ]
      then
          color=yellow
	  if [ $status = green ] ||  [ $status = white ]
	  then
	      status=yellow
	  fi
      elif [ -f $builddir/$task.pass ]
      then
          color=green
	  if [ $status = white ]
	  then
	      status=green
	  fi
      else
	  color=white
      fi
      echo "<th><a href=\"$url/$buildno/${task}log.txt\"><img border=0 src=\"http://130.236.214.222/pikefarm/${color}_button.gif\"></a></th>" >&7
    done
    echo '</tr>' >&7
    [ $status = red ]    && red=`expr $red + 1`
    [ $status = yellow ] && yellow=`expr $yellow + 1`
    [ $status = green ]  && green=`expr $green + 1`
    [ $status = white ]  && white=`expr $white + 1`
    result=`expr $result + 1`
done
echo '</table></body></html>' >&7

echo "<tr><td>$build</td><td><a href=\"$build.html\">$pretty</a></td><td>$result</td><td>$green</td><td>$yellow</td><td>$red</td><td>$white</td>" > $output/$build.frag

exec 8> $output/index.html
cat <<EOF >&8
<html><head><title>lyskom-server Xenofarm result overview</title><head>
<body>
<a href="latest.html">[latest per machine]</a>
<h1>lyskom-server Xenofarm result overview</h1>
This build overview was collected $now.

<table border="1">
<tr>
<th>Build</th><th>Buildtime</th><th align=right>Results</th><th align=right>Green</th><th align=right>Yellow</th><th align=right>Red</th><th align=right>White</th>
EOF

for i in `ls -v -r $output/*.frag`
do
    cat $i >&8
done
cat <<EOF >&8
</table></body></html>
EOF
