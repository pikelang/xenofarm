#!/bin/sh

MAILADDR="sfarmer@lysator.liu.se"
XENOUSER="sfarmer"

check_alive () {
	if ps -fu $XENOUSER | grep $1 | grep -v grep > /dev/null
        then
		echo > /dev/null
	else
		(   echo "Subject: Restarted $1";
            echo "From: $MAILADDR";
            echo; tail -30 $3   ) | mail $MAILADDR
		echo "[`date '+%Y-%m-%d %H:%M:%S'`] keepalive.sh restarted $1" >> $3
		pike $1 $2 >> $3 2>&1 &
	fi
}

# Go to correct directory
cd $HOME/xenofarm/projects/python || exit 1

# Do the server script live?
check_alive devel/server.pike "--verbose" "$HOME/xlogs/server-devel.log"
check_alive stable/server.pike "--verbose" "$HOME/xlogs/server-stable.log"

# Do the result parser live?
check_alive devel/result_parser.pike "--verbose" "$HOME/xlogs/result-devel.log"
check_alive stable/result_parser.pike "--verbose" "$HOME/xlogs/result-stable.log"