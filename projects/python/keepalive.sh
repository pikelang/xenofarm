#!/bin/sh

MAILADDR="sfarmer@lysator.liu.se"
XENOUSER="quest"
#XENOUSER="sfarmer"

function check_alive {
	if ! ps -fu $XENOUSER | grep $1 | grep -v grep > /dev/null; then
		tail -30 $3 | mail $MAILADDR
		echo "[`date '+%Y-%m-%d %H:%M:%S'`] keepalive.sh restarted $1" > $3
		pike $1 $2 > $3 2>&1 &
	fi
}

# Go to correct directory
cd $HOME/xenofarm/projects/python || exit 1

# Do the server script live?
check_alive server.pike "--verbose" "$HOME/xlogs/server.log"

# Do the result parser live?
check_alive result_parser.pike "--verbose" "$HOME/xlogs/result.log"