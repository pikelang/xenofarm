#!/bin/sh

# Program som startar alla serversaker (Lenin)
# Detta program körs regelbundet från crontab
PATH=/bin:/usr/local/bin:/usr/bin
export PATH

ROOT=/web/projects/xenofarm/argouml
CVS_PASSFILE=$ROOT/work/progs/.cvspass
export CVS_PASSFILE

DBURL=`cat ../../../.argouml_xenofarm_mysqlurl`

LOCKDIR=$ROOT/LOCKS
lockfile="$LOCKDIR/start-server.sh.$$"
lock=$LOCKDIR/start-server.sh
echo $$ > $lockfile
trap "/bin/rm -f $lockfile ; exit 0" 0 1 2 15

if test -f $lock
then
    # Someone else has the lock. Is he live?
    if kill -0 `cat $lock`
    then
        # Yes, he is live.
        exit 0
    else
        # No, Lets take the lock
        rm -f $lock
    fi
fi

ln $lockfile $lock
trap "rm -f $lockfile $lock ; exit 0" 0 1 2 15

# Nu kör vi!
    # Bygg dist
    ../../server.pike \
	--repository=:pserver:guest@cvs.tigris.org:/cvs \
	--update-opts=-d \
	--cvs-module=argouml \
	--db=$DBURL \
	--web-dir=$ROOT/export \
	--work-dir=$ROOT/work \
	--transformer=`pwd`/argouml-server.sh \
	--min-distance=20000 \
	--latency=9000 \
	--once \
	argouml > /dev/null

    # Ta emot och packa upp resultat
    ../../result_parser.pike \
	--db=$DBURL \
	--web-dir=$ROOT/files \
	--result-dir=$ROOT/results \
	--work-dir=$ROOT/work/res \
	--once > /dev/null

    SPARA_DAGAR=8
    export SPARA_DAGAR

    # Bygg hemsidan
    ./gen-result.sh
    ./gen-diffs.sh

    # Rensa bort gamla filer
    ( cd $ROOT && find files -type d -mtime +$SPARA_DAGAR -exec rm -r "{}" ";" )
    ( cd $ROOT && find export -mtime +$SPARA_DAGAR -exec rm "{}" ";" )
    # packa upp tar-arkiv
    find $ROOT/files -type f -name junittesthtml.tar -print |
    while read filename
    do
	dir=`dirname $filename`
	if tar tf $filename | grep '\\.\\.' > /dev/null
        then
            echo vi skall inte packa upp denna
        else
            ( cd $dir && mkdir junit && cd junit && tar xf ../junittesthtml.tar )
        fi
        mv $filename $dir/junittesthtml.tar.done
    done

exit 0
