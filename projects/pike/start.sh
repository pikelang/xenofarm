#!/bin/sh

##############################################
# pike xenofarm server starter
#
# Written by Peter Bortas, Copyright 2002
# $Id: start.sh,v 1.1 2002/09/05 15:55:44 zino Exp $
# Licence: <Nilsson will insert Copyright of his choise here>
##############################################
# Error codes:
#  0: Exited without errors

check_pidfile() {
    node=`uname -n`
    pidfile="`pwd`/xenofarm-$1.pid"
    if [ -r $pidfile ]; then
        pid=`cat $pidfile`
        if `kill -0 $pid > /dev/null 2>&1`; then
            echo "NOTE: Xenofarm $1 already running. pid: $pid"
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

check_pidfile gc
pike gc.pike &
setup_pidfile 

check_pidfile server
pike server.pike --verbose > log_server &
setup_pidfile

check_pidfile result_parser
pike result_parser.pike --verbose > log_result &
setup_pidfile

clean_exit $?
