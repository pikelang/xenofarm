#!/bin/sh

##############################################
# Xenofarm client
#
# Written by Peter Bortas, Copyright 2002
# $Id: client.sh,v 1.5 2002/05/17 10:42:43 zino Exp $
# License: GPL
#
# Requirements:
#  gzip
#  wget
#
# Requirements that are normally fulfilled by the UNIX system:
# `uname -n`        should print the nodename
# `kill -0 <pid>`   should return true if a process with that pid exists.
# `LC_ALL="C" date` should return a space-separated string with where the
#                   first substring containging colons is on the form
#                   <hour>:<minute>.*
##############################################

#FIXME: use logger to put stuff in the syslog if available

parse_args() {
 while [ ! c"$1" = "c" ] ; do
  case "$1" in
  '-h'|'--help')
  	sed -e "s/\\.B/`tput 'bold' 2>/dev/null`/g" -e "s/B\\./`tput 'sgr0' 2>/dev/null`/g" << EOF
.BXenofarm clientB.

Start it with cron or with the "start"-script.

If you encounter problems see the .BREAMEB. for requirements and help.

EOF
    	tput 'rmso' 2>/dev/null
	exit 0
  ;;
  *)
	echo Unsopported argument: $1
	echo try --help
	exit 1
  esac
 done
}

get_time() {
    hour=`LC_ALL="C" date | awk -F: '{ print $1 }' | awk '{ i=NF; print $i }'`
    minute=`LC_ALL="C" date | awk -F: '{ print $2 }' | awk '{ print $1 }'`
}

check_delay() {
    #FIXME: This is a total mess, and unfinished at that. Redo from start.
#     if [ -f "../last_$target" ] && [ $delay -ne 0 ] ; then
#         get_time
#         old_hour=`awk -F: '{ print $1 }' < "../last_$target"`
#         old_minute=`awk -F: '{ print $2 }' < "../last_$target"`
#         delay_hour=`echo $delay | awk -F: '{ print $1 }'"`
#         delay_minute=`echo $delay | awk -F: '{ print $2 }'"`
#         if [ $hour -gt $old_hour ]; then  #Pre midnight
#             if [ `echo $hour - $old_hour | bc` -gt $delay_hour ] ; then
#                 /bin/true
#             else if [ `echo $hour - $old_hour | bc` -eq $delay_hour ] ; then
#                 if [ `echo $minute - $old_minute | bc` -gt $delay_minute ];then
#                     /bin/true
#                 fi
#             else
#                 /bin/false
#             fi
#         else if [ $hour -eq $old_hour ]; then  # Might be other day
#             if [ $minute -gt $old_minute ] &&  # It wasn't
#                [ `echo $minute - $old_minute | bc` -gt $delay_minute ] &&
#                [ $delay_hour -eq 0 ] ; then
#                 /bin/true
#             else if [ $minute -lt $old_minute ]
#                 /bin/false
#             fi
#         fi
#     else
#         echo "'NOTE: ../last_$target' does not exists."
#         /bin/true
#     fi
    #FIXME: Just build always for now...
    /bin/true 
}

sigint() {
    echo "SIGINT recived. Exiting."
    rm -f $pidfile
    exit 0    
}
sighup() {
    echo "SIGHUP recived. Exiting for now."
    rm -f $pidfile
    exit 0
}

#Execcution begins here.

trap sighup 1
trap sigint 2
trap sigint 15

parse_args $@

pidfile="`pwd`/autobuild-`uname -n`.pid"
if [ -r $pidfile ]; then
    pid=`cat $pidfile`
    if `kill -0 $pid`; then
        echo "FATAL: Autobuild client already running. pid: $pid"
        exit 2
    else
        echo "NOTE: Removing stale pid-file."
        rm -f $pidfile
    fi
fi

echo $$ > $pidfile

if [ ! -x put ]; then
    make put
    if [ ! -x put ]; then
        echo "FATAL: No put command found."
        rm $pidfile
        exit 3
    fi
fi

basedir="`pwd`"
grep -v \# projects.conf | ( while 
    read project ; do 
    read dir
    read geturl
    read puturl
    read targets
    read delay
    read endmarker

    if [ x$dir = x ] ; then
        echo "No more projects in projects.conf"
        # This will drop from the subshell to the backend
        exit 0;
    else
        echo "Building $project in $dir from $geturl with targets: $targets"
    fi

    if [ ! -x "$dir" ]; then
        mkdir "$dir"
    fi

    (cd "$dir" &&
     uncompressed=0
     NEWCHECK="`ls -l snapshot.tar.gz`";
     wget --dot-style=binary -N "$geturl" &&
     if [ X"`ls -l snapshot.tar.gz`" == X"$NEWCHECK" ]; then
        echo "NOTE: No newer snapshot for $project available."
     fi
     rm -rf buildtmp && mkdir buildtmp && 
     cd buildtmp &&
     for target in `echo $targets`; do
        #FIXME: Check if the project configurable build delay has passed
        if [ \! -f "../last_$target" ] ||
           [ "../last_$target" -ot ../../snapshot.tar.gz ]; then
        if `check_delay`; then
            if [ x"$uncompressed" = x0 ] ; then
              echo "Uncompressing archive..." &&
              (gzip -cd ../snapshot.tar.gz | tar xf -) &&
              echo "done" &&
              uncompressed=1
              if [ ! x$uncompressed = x1 ] ; then
                echo "FATAL: Unable to decompress snapshot!"
                #Will drop from the the second subshell to the while shell
                exit 4
              fi
            fi
            cd */. 
            resultdir="../../result_$target"
            rm -rf "$resultdir" && mkdir "$resultdir" &&
            cp export.stamp "$resultdir/" &&
            echo "Building $target" &&
            make $target >"$resultdir/RESULT" 2>&1;
            if [ -f autobuild_result.tar.gz ]; then
                mv autobuild_result.tar.gz "$resultdir/"
            else
                (cd "$resultdir" && 
                tar cvf autobuild_result.tar RESULT export.stamp |
                gzip autobuild_result.tar)
            fi
            get_time
            echo $hour:$minute > "../../last_$target";
            $basedir/put "$puturl" < "$resultdir/autobuild_result.tar.gz" &
            cd ..
        else
            echo "NOTE: Build delay for $project not passed. Skipping."
        fi
        else
            echo "NOTE: Already built $project: $target. Skipping."
        fi
     done )
done )

rm $pidfile
