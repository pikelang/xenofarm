#!/bin/sh

##############################################
# pike xenofarm server starter
#
# Written by Peter Bortas, Copyright 2002
# $Id: start.sh,v 1.2 2002/09/05 16:07:49 zino Exp $
# Licence: <Nilsson will insert Copyright of his choise here>
##############################################
# Error codes:
#  0: Exited without errors
#  1: One or more of the servers was already running

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
    last_job=`ps | grep -v PID | sort | tail -1 | awk '{print $1}'`
    echo $last_job > $pidfile
}

(check_pidfile gc
 pike gc.pike &
 setup_pidfile)
error=$?

(check_pidfile server
 pike server.pike --verbose > log_server &
 setup_pidfile)
last=$?
if [ $error = 0 ] ; then error=$last ; fi

(check_pidfile result_parser
 pike result_parser.pike --verbose > log_result &
 setup_pidfile)
last=$?
if [ $error = 0 ] ; then error=$last ; fi

exit $last
