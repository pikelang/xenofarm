#!/bin/sh

project=$1
result=$2
stamp=$3

exec > source-transform.log 2>&1

#rm -rf workdir dist
#cp -a $project workdir
rm -r dist

mkdir dist

tar cf dist/python.tar $project
gzip dist/python.tar

echo $stamp > dist/buildid.txt

# Compatibility names for client.sh:
echo $stamp > dist/export.stamp
echo $stamp > dist/exportstamp.txt

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
host=`uname -n | sed -e "s/\..*//"`

timeecho () {
    echo `TZ=UTC date|awk '{print $6 "-" $2 "-" $3 " " $4}'\
	|sed -e s/Jan/01/ -e s/Feb/02/ -e s/Mar/03/ -e s/Apr/04/ \
	     -e s/May/05/ -e s/Jun/06/ -e s/Jul/07/ -e s/Aug/08/ \
	     -e s/Sep/09/ -e s/Oct/10/ -e s/Nov/11/ -e s/Dec/12/ `: "$@"
}

log () {
    echo "$@" >> r/mainlog.txt
    date >> r/mainlog.txt
}

dotask() {
    important="$1"
    task="$2"
    cmd="$3"
    if test "$status" = "good"
    then
	log Begin $task
        timeecho Begin $task
        if sh -c "$cmd" > r/${task}log.txt 2>&1
        then
	    touch r/"$task.pass"
        else
	    timeecho FAIL: $task
	    touch r/"$task.fail"
	    if [ $important = 1 ]
	    then
	        status="${task}-failed"
	    fi
        fi
    else
	echo status $status makes it impossible to perform this step \
	    > r/${task}log.txt
    fi
}

status=good

dotask 1 "unzip" "gzip -d $BASE.tar.gz"
dotask 1 "unpack" "tar xf $BASE.tar"

dotask 1 "configure"  "cd $BASE/dist/src  && ./configure"
dotask 1 "make"       "cd $BASE/dist/src  && make"
dotask 1 "test"       "cd $BASE/dist/src  && make test TESTOPTS='-x test_pwd test_nis'"

log Begin response assembly
timeecho Collecting results

cp $BASE/dist/src/pyconfig.h r/
env > r/environ.txt
echo $PATH > r/path.txt

uname -s -r -m > r/machineid.txt
uname -n >> r/machineid.txt

cp buildid.txt r/buildid.txt

cp export.stamp r/export.stamp
cp exportstamp.txt r/exportstamp.txt

if test "$status" = "good"
then
    log Xenofarm OK
fi

exit 0

EOF

chmod +x dist/create-response.sh

tar cf $result.tar dist || exit 1
gzip $result.tar || exit 1
exit 0
