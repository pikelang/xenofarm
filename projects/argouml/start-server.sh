#!/bin/sh

# Program som startar alla serversaker (Lenin)

DBURL=`cat /home/linus/.argouml_xenofarm_mysqlurl`
ROOT=/lysator/www/projects/xenofarm/argouml
../../server.pike \
	--repository=:pserver:guest@cvs.tigris.org:/cvs \
	--update-opts=-d \
	--cvs-module=argouml \
	--db=$DBURL \
	--web-dir=$ROOT/export \
	--work-dir=$ROOT/work \
	--transformer=`pwd`/argouml-server.sh \
	argouml &
SERVERPID=$!
../../result_parser.pike \
	--db=$DBURL \
	--web-dir=$ROOT/files \
	--result-dir=$ROOT/results \
	--work-dir=$ROOT/work/res \
	&
RESULTPARSERPID=$!1

trap "kill $RESULTPARSERPID $SERVERPID; exit 0" 0 1 2 15

while true
do
    ./gen-result.sh
    sleep 1800
done
exit 0
