#!/bin/sh

input=/lysator/www/projects/xenofarm/python/files
output=/lysator/www/user-pages/sfarmer/xeno/
url=http://www.lysator.liu.se/xenofarm/python/files
tmp=/lysator/www/user-pages/sfarmer/xeno/tmp
buttonurl=pcl-

mysql --batch -D sfarmer -e 'select system, max(build), max(time) from result, build where result.build = build.id group by system' -p`cat /home/sfarmer/.xeno-mysql-pwd`|sed 1d > $tmp/lastest-builds.txt

rm -f $tmp/tsort2.in

while read sys build time 
do
  awk '$1 == "Begin" && NF == 2 { if (prev) { print prev, $2 } prev=$2 }' \
      < $input/${build}_$sys/mainlog.txt >> $tmp/tsort2.in
done < $tmp/lastest-builds.txt

tsort < $tmp/tsort2.in > $tmp/latest-tasks

exec 8> $output/latest.html
exec 7> $tmp/latest.html

cat <<EOF >&8

<html><head><title>Python Xenofarm latest results</title><head>
<body>
<h1>Python Xenofarm latest results</h1>
<p>This page collects the latest result for all machines that have ever
reported a result.  Some of these results may be very old and
obsolete.</p>

<p>This information on this page was collected
`date "+%Y-%m-%d&nbsp;%H:%M:%S"`.
EOF


cat <<EOF >&7
<table border="1">
<tr>
<th>Machine</th>
EOF
# <th>Build</th><th>Days</th>

sed -e 's/^/<th>/' -e 's_$_</th>_' < $tmp/latest-tasks >&7

cat <<EOF >&7
<th>Total</th>
</tr>
EOF

green=0
yellow=0
red=0
white=0
lastbuild=
colspan=`expr \`wc -l < $tmp/latest-tasks\` + 2`

sort -k 2nr $tmp/lastest-builds.txt \
| while read sys build time 
do
    if test "$lastbuild" != "$build"
    then
	pretty=`pike -e 'write(Calendar.Second((int)argv[1])->format_time()+"\n");' $time`
	age=`python -c "import time; print \"%.2f\" % ((time.time() - $time) / (24*3600))`
	echo "<tr><td colspan="$colspan"><a href=\"${build}.html\">Build $build ($age days ago) $pretty</a></td></tr>" >&7
	lastbuild=$build
    fi

    builddir=$input/${build}_$sys
    echo "<tr><td><a href=\"$url/${build}_$sys/\">" >&7
    mysql --batch -D sfarmer -e 'select name, platform from system where id = '$sys -p`cat /home/sfarmer/.xeno-mysql-pwd`|sed 1d|sed 's/	/<br>/' >&7
    echo "</a></td>" >&7
    
    # echo "<td><a href=\"${build}.html\">$build</a></td>" >&7
    # echo "<td>$age</td>" >&7

    status=white
    logtypes=log
    for task in `cat $tmp/latest-tasks`
    do
      if [ -f $builddir/$task.fail ]
      then
          color=red
	  status=red
      elif [ -f $builddir/$task.warn ]
      then
          color=yellow
	  logtypes="warn $logtypes"
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
      astart=
      aend=
      for link in $logtypes
      do
          if [ -f $builddir/${task}${link}.txt ]
          then
          	  astart="<a href=\"$url/${build}_$sys/${task}${link}.txt\">"
          	  aend="</a>"
		  break
          fi
      done
      if [ "$astart" ] || [ $color != white ]
      then
          echo "<th>$astart<img border=0 src=\"$buttonurl${color}.gif\">$aend</th>" >&7
      else
	  echo "<th>&nbsp;</th>" >&7
      fi
    done
    echo "<th><img border=0 src=\"$buttonurl${status}.gif\"></th>" >&7
    echo '</tr>' >&7

    [ $status = red ]    && red=`expr $red + 1`
    [ $status = yellow ] && yellow=`expr $yellow + 1`
    [ $status = green ]  && green=`expr $green + 1`
    [ $status = white ]  && white=`expr $white + 1`

    cat <<EOF > $tmp/latest-sumfrag
<tr>
<td>$green</td>
<td>$yellow</td>
<td>$red</td>
<td>$white</td>
</tr>
EOF

done

cat <<EOF >&7
</table>
EOF

cat <<EOF >&8

<h1>Summary</h1>
This is a quick count on how many machines that passed all steps in the build.
<table border=1>
<tr>
<th><img border=0 src="${buttonurl}green.gif"></th>
<th><img border=0 src="${buttonurl}yellow.gif"></th>
<th><img border=0 src="${buttonurl}red.gif"></th>
<th><img border=0 src="${buttonurl}white.gif"></th>
</tr>
`cat $tmp/latest-sumfrag`
</table>

<h1>Per-machine overview</h1>
<p>Green dots mean that the step went well. Red dots mean that the
step failed somehow (There is a .fail file in the result representing
this step). Yellow dots means that this step passed, but with some
snatch; this has nothing to do with compiler warnings. White dots mean
this script could not parse the result. Maybe the status file is
missing?</p>

`cat $tmp/latest.html`
</body>
</html>
EOF
