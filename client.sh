#!/bin/sh

##############################################
# Xenofarm client
#
# Written by Peter Bortas, Copyright 2002
#
# REQIREMENTS:
#  gzip
#  wget
##############################################

#FIXME: use logger to put stuff in the syslog if available

pidfile=autobuild-`uname -n`.pid
if [ -r $pidfile ]; then
    pid=`cat $pidfile`
    if `kill -0 $pid`; then
        echo "FATAL: Autobuild client already running. pid: $pid"
        exit 1
    else
        echo "NOTE: Removing stale pid-file."
        rm -f $pidfile
    fi
fi

sigint() {
    echo "SIGINT recived. Exiting."
    rm $pidfile
    exit 0    
}
sighup() {
    echo "SIGHUP recived. Exiting for now."
    rm $pidfile
    exit 0
}

trap 1 sighup
trap 2 sigint
trap 15 sigint

echo $$ > $pidfile

grep -v \# projects.conf | ( while 
    read project ; do 
    read dir
    read url
    read targets

    echo "Building $project in $dir from $url with targets: $targets"

    #Get snapshot if newer than current
    (cd "$dir" &&
     wget -N "$url" &&
     rm -rf buildtmp && mkdir buildtmp && cd buildtmp &&
     gzip -cd snapshot.tar.gz | tar xvf &&
     cd */. &&
     for target in `echo $targets`; do
        rm -rf "../result_$target" && mkdir "../result_$target" &&
        make $target 2>&1> "../result_$target/RESULT";
        if [ -f autobuild_result.tar.gz ]; then
            mv autobuild_result.tar.gz "result_$target/"
        else
            (cd "../result_$target" && tar cvf autobuild_result.tar | 
             gzip autobuild_result.tar)
        fi
        #FIXME: upload result async.
     done
    )

done
     