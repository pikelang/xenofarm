#!/bin/sh
working=$1
name=$2
buildid=$3
echo $buildid > $working/buildid.txt
cat << \E1OF > $working/doit.sh
#!/bin/sh
# Xenofarm build script
LOG=mainlog.txt

chmod +x tools/ant-1.6.2/bin/ant
test -n "$JAVA_HOME" || {
    echo JAVA_HOME not set.;
    exit 1;
}
test -d "$JAVA_HOME" || {
    echo $JAVA_HOME is no directory.;
    exit 1;
}
test -x $JAVA_HOME/bin/javac || {
    echo $JAVA_HOME/bin/javac not executable.;
    exit 1;
}

DEPLOYMENT_JAVA_HOME=${DEPLOYMENT_JAVA_HOME-$JAVA_HOME}
export DEPLOYMENT_JAVA_HOME
test -d "$DEPLOYMENT_JAVA_HOME" || {
    echo $DEPLOYMENT_JAVA_HOME is no directory.;
    exit 1;
}
test -x $DEPLOYMENT_JAVA_HOME/bin/javac || {
    echo $DEPLOYMENT_JAVA_HOME/bin/javac not executable.;
    exit 1;
}

$JAVA_HOME/bin/java -version > javaversion.txt 2>&1

# Kanske start av Xvfb
if test -x "$XVFB" -a -x "$XRDB"
then
    DISPLAY=:141
    export DISPLAY
    $XVFB $DISPLAY &
    pid=$!
    trap "kill -15 $pid" 0 1 15

    sleep 10

    if $XRDB < /dev/null > /dev/null 2> /dev/null
    then
        XVFB=cremebrulee
        XRDB=yuk
        export XVFB XRDB
        ./doit.sh "$@"
    fi

    kill -15 $pid
    exit 0
fi


echo FORMAT 2 > $LOG

DOTESTS=${DOTESTS-true}
export DOTESTS

# If you have a working display when running the clients you could set
# DOGUITESTS to true. You should perhaps set DOTESTS to false then to avoid
# running the tests twice.
DOGUITESTS=${DOGUITESTS-false}
export DOGUITESTS

# Independant tasks!
cat <<\EOF |
package	cd src_new && ../tools/ant-1.6.2/bin/ant package
tests	cd src_new && ../tools/ant-1.6.2/bin/ant compile-tests && JAVA_HOME=$DEPLOYMENT_JAVA_HOME ../tools/ant-1.6.2/bin/ant tests
guitests	cd src_new && ../tools/ant-1.6.2/bin/ant compile-tests && JAVA_HOME=$DEPLOYMENT_JAVA_HOME ../tools/ant-1.6.2/bin/ant alltests
php	cd modules/php && ../../tools/ant-1.6.2/bin/ant package
cpp	cd modules/cpp && ../../tools/ant-1.6.2/bin/ant package
classfile	cd modules/classfile && ../../tools/ant-1.6.2/bin/ant package
checkstyle	cd src_new && ../tools/ant-1.6.2/bin/ant delete-generated-for-checkstyle && ../tools/ant-1.6.2/bin/ant checkstyle
EOF
if $DOTESTS; then cat; else egrep -v '^tests'; fi |
if $DOGUITESTS; then cat; else egrep -v '^guitests'; fi |
while read task command
do
    echo BEGIN $task >> $LOG
    date >> $LOG
    logfile=$task.log
    if sh -xc "$command" > $logfile 2>&1
    then
	if egrep " TEST .* FAILED" $logfile > /dev/null
	then
	    echo FAIL >> $LOG
	elif grep warning $logfile > /dev/null
	then
	    echo WARN `grep -i warning $logfile | wc -l` >> $LOG
	else
	    echo PASS >> $LOG
	fi
    else
	echo FAIL >> $LOG
    fi
    date >> $LOG
done

# Collect data
# Mangle the logfiles
for logfile in *.log
do
    sed "s;`pwd`;ROOT;g" $logfile > $logfile.txt
    echo '<PRE>' > $logfile.html
    sed 's/</\&lt;/g' < $logfile.txt |
    sed 's;.*warning.*;<FONT COLOR="#AA4400">&</FONT>;' |
    sed 's;.*TEST.*FAILED.*;<FONT COLOR="#CC0000">&</FONT>;' |
    sed 's;ROOT\([^:]*\.java\):\([0-9]*\):;<a href="http://argouml.tigris.org/source/browse/argouml\1?annotate=HEAD#id\2">&</a>;g' >> $logfile.html
    echo '</PRE>' >> $logfile.html
done

# Collect result from Unit tests.
if test -d build/tests/reports/junit/output/html
then
    ( cd build/tests/reports/junit/output/html && 
      tar cf - * ) > junittesthtml.tar
fi

tar cf xenofarm_result.tar \
    buildid.txt $LOG *.log.txt *.log.html \
    javaversion.txt \
    junittesthtml.tar
gzip --fast xenofarm_result.tar

E1OF

chmod +x $working/doit.sh

find $working/build $working/lib $working/modules $working/src_new $working/tests $working/tools $working/src $working/buildid.txt $working/doit.sh -print |
grep -v /CVS |
cpio -o --format=ustar > $name.tar 2> /dev/null || exit 1
gzip $name.tar || exit 1
rm $working/buildid.txt $working/doit.sh

cd $working
find . -type d -name CVS -print |
while read dirname
do
    (
        REST=`echo $dirname | sed -e "s;\\./;;" -e "s;/CVS;;"`
	cat $dirname/Entries 2>/dev/null |
	awk -F/ '$1 == "" {
	    printf "insert into files values (%d, '"'%s/%s'"', '"'%s'"');\n", \
		build, rest, $2, $3; }' build=$buildid "rest=$REST"
    )
done |
mysql --batch \
    -D argouml_xenofarm \
    -u linus -p`cat /web/projects/xenofarm/argouml/work/progs/.argouml_xenofarm_mysql_password`
