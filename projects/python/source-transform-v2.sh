#!/bin/sh

project=$1
result=$2
stamp=$3

exec > source-transform.log 2>&1

rm -r dist
mkdir dist

tar cf dist/python.tar python crypto Twisted
gzip dist/python.tar

echo $stamp > dist/buildid.txt

cat <<'EOF' > dist/Makefile
xenofarm:
	rm -f xenofarm_result.tar xenofarm_result.tar.gz
	mkdir r
	./create-response.sh > r/shlog.txt 2>&1
	(cd r && tar cf - *) > xenofarm_result.tar
	gzip -9 xenofarm_result.tar
EOF

cat <<'EOF' > dist/create-response.sh
#!/bin/sh

BASE=python

log () {
    echo "$@" >> r/mainlog.txt
    date >> r/mainlog.txt
}

dogroup() {
    important="$1"
    group="$2"
    cmd="$3"

    log BEGIN $group
    if $cmd
    then
        log PASS
    else
        log FAIL
        if [ $important = 1 ]
	    then
            status="${group}-failed"
        fi
    fi
}

dotask() {
    important="$1"
    task="$2"
    cmd="$3"

    # Return value for this task
    task_result=1

    if test "x$group" = "x"
    then
        taskfile=$task
    else
        taskfile=$group-$task
    fi

    if test "$status" = "good"
    then
	    log BEGIN $task
        if sh -c "$cmd" > r/${taskfile}log.txt 2>&1
        then
            log PASS
            task_result=0
        else
	        log FAIL
	        if [ $important = 1 ]
	        then
	            status="${task}-failed"
	        fi
        fi
    else
	    echo status $status makes it impossible to perform this step > \
	        r/${taskfile}log.txt
    fi

    return $task_result
}

status=good

echo "FORMAT 2" >> r/mainlog.txt

dotask 1 "unzip" "gzip -d python.tar.gz"
dotask 1 "unpack" "tar xf python.tar"

pydir=`pwd`/python/dist/src
pybin=$pydir/python

do_python() {
    dotask  1 "configure"  "cd $pydir  && ./configure $CONFIGOPTS"
    dotask  1 "make"       "cd $pydir  && make $MAKEOPTS"
    dotask  0 "test"       "cd $pydir  && make test TESTOPTS='-x test_pwd test_nis -x test_tempfile'"
}

do_crypto() {
    dotask  1 "build"      "cd crypto  && $pybin setup.py build"
    cryptolib=`pwd`/`ls -d1 crypto/build/lib.*`
    dotask  0 "test"       "cd crypto  && $pybin test.py"
}

do_twisted() {
    dotask  1 "build"      "cd Twisted && $pybin setup.py build"
    dotask  0 "test"       "cd Twisted/build/lib.* && PYTHONPATH=../..:$cryptolib $pybin ../../admin/runtests -tv"
    # external modules shouldn't block each other, we need to reset status
    status="good"
}

dogroup 1 "python"    "do_python"
dogroup 0 "crypto"    "do_crypto"
dogroup 0 "twisted"   "do_twisted"

log BEGIN makeresp

cp $BASE/dist/src/pyconfig.h r/
env > r/environ.txt

cp buildid.txt r/buildid.txt

log PASS
echo END >> r/mainlog.txt

exit 0
EOF

chmod +x dist/create-response.sh

tar cf $result.tar dist || exit 1
gzip $result.tar || exit 1
exit 0
