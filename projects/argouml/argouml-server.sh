#!/bin/sh
working=$1
name=$2
buildid=$3
echo $buildid > $working/buildid.txt
cat << \E1OF > $working/doit.sh
#!/bin/sh
# Xenofarm build script
LOG=mainlog.txt

chmod +x tools/ant-1.4.1/bin/ant
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

$JAVA_HOME/bin/java -version > javaversion.txt


echo FORMAT 2 > $LOG

# Independant tasks!
cat <<\EOF |
package	cd src_new && ../tools/ant-1.4.1/bin/ant package
tests	cd src_new && ../tools/ant-1.4.1/bin/ant compile-tests && JAVA_HOME=$DEPLOYMENT_JAVA_HOME ../tools/ant-1.4.1/bin/ant tests
php	cd modules/php && ../../tools/ant-1.4.1/bin/ant package
cpp	cd modules/cpp && ../../tools/ant-1.4.1/bin/ant package
classfile	cd modules/classfile && ../../tools/ant-1.4.1/bin/ant package
junit	cd modules/junit && ../../tools/ant-1.4.1/bin/ant package
EOF
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
	elif grep -i warning $logfile > /dev/null
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
    sed 's;ROOT\([^:]*\.java\):;<a href="http://argouml.tigris.org/source/browse/argouml\1">&</a>;g' >> $logfile.html
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

cat <<\EOF > $working/EXCLUDED
*/CVS/*
*/CVS/
*/CVS
EOF
tar cfX $name.tar $working/EXCLUDED $working/build $working/lib $working/modules $working/src_new $working/tests $working/tools $working/buildid.txt $working/doit.sh || exit 1
gzip $name.tar || exit 1
rm $working/buildid.txt $working/doit.sh $working/EXCLUDED
