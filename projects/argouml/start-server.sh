#!/bin/sh

# Program som startar alla serversaker (Lenin)
PATH=/bin:/usr/bin:/sw/local/bin
export PATH

DBURL=`cat /home/linus/.argouml_xenofarm_mysqlurl`
ROOT=/lysator/www/projects/xenofarm/argouml

while true
do
    # Bygg dist
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

    # Ta emot och packa upp resultat
    ../../result_parser.pike \
	--db=$DBURL \
	--web-dir=$ROOT/files \
	--result-dir=$ROOT/results \
	--work-dir=$ROOT/work/res \
	--once

    SPARA_DAGAR=25
    export SPARA_DAGAR

    # Bygg hemsidan
    ./gen-result.sh
    ./gen-diffs.sh

    # Rensa bort gamla filer
    ( cd $ROOT && find files -type d -mtime +$SPARA_DAGAR -exec rm -r "{}" ";" )
    ( cd $ROOT && find export -mtime +$SPARA_DAGAR -exec rm "{}" ";" )

    sleep 1000
done
exit 0
