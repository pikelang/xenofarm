#!/bin/sh

##############################################
# pike xenofarm server starter
#
# Written by Peter Bortas, Copyright 2002
# Licence: <Nilsson will insert Copyright of his choise here>
##############################################
# Error codes:
#  0: Exited without errors
#  1: One or more of the servers was already running
#  2: Failed to start one or more of the servers

check_pidfile() {
    node=`uname -n`
    pidfile="`pwd`/xenofarm-$1.pid"
    if [ -r $pidfile ]; then
        pid=`cat $pidfile`
        if `kill -0 $pid > /dev/null 2>&1`; then
            echo "NOTE: Xenofarm $1 already running. pid: $pid"
            exit 1
        else
            echo "NOTE: Removing stale pid-file for $1."
            rm -f $pidfile
        fi
    fi
}

setup_pidfile() {
    #Must compensate for all processes in the pipe, therefore tail -6
    last_job="`ps | grep -v PID | tail -6 | head -1`"
    jobname=`basename $pidfile | sed 's/\.pid//'`
    #Check that it wasn't the last processes PID we got
    if [ X"`echo $last_job | awk '{print $4}'`" != Xpike -o \
         X"`echo $last_job | awk '{print $1}'`" = X$last_pid ] ; then
        echo "Failed to start $jobname."
        exit 2
    else
        last_pid=`echo $last_job | awk '{print $1}'`
        echo "Started $jobname with PID $last_pid."
        echo $last_pid > $pidfile
    fi
}

error=0

(check_pidfile gc
 pike gc.pike &
 sleep 1 #Give it some time to fail
 setup_pidfile)
last=$?
if [ $last -gt $error ] ; then error=$last ; fi

(check_pidfile server
 pike server.pike --verbose > log_server &
 sleep 1 #Give it some time to fail
 setup_pidfile)
last=$?
if [ $last -gt $error ] ; then error=$last ; fi

(check_pidfile result_parser
 pike result_parser.pike --verbose > log_result &
 sleep 1 #Give it some time to fail
 setup_pidfile)
last=$?
if [ $last -gt $error ] ; then error=$last ; fi

exit $error