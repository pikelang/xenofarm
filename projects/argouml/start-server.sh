#!/bin/sh

# Program som startar alla serversaker (Lenin)
PATH=/bin:/usr/bin:/sw/local/bin
export PATH

DBURL=`cat /home/linus/.argouml_xenofarm_mysqlurl`
ROOT=/lysator/www/projects/xenofarm/argouml

while true
do
    ../../server.pike \
	--repository=:pserver:guest@cvs.tigris.org:/cvs \
	--update-opts=-d \
	--cvs-module=argouml \
	--db=$DBURL \
	--web-dir=$ROOT/export \
	--work-dir=$ROOT/work \
	--transformer=`pwd`/argouml-server.sh \
	--once \
	argouml

    ../../result_parser.pike \
	--db=$DBURL \
	--web-dir=$ROOT/files \
	--result-dir=$ROOT/results \
	--work-dir=$ROOT/work/res \
	--once

    ./gen-result.sh
    sleep 1000
done
exit 0
