#!/bin/sh
working=$1
name=$2
buildid=$3
echo $buildid > $working/buildid.txt
cat << \E1OF > $working/doit.sh
#!/bin/sh
# Xenofarm build script
LOG=mainlog.txt

case $1 in
--java1.2)
    JAVA_HOME=$JAVA_HOME_1_2
    ;;
--java1.3)
    JAVA_HOME=$JAVA_HOME_1_3
    ;;
*)
    echo Unknown argument.;
    exit 1;
esac
export JAVA_HOME

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

echo FORMAT 2 > $LOG

# Independant tasks!
cat <<EOF |
package	cd src_new && ../tools/ant-1.4.1/bin/ant package
tests	cd src_new && ../tools/ant-1.4.1/bin/ant tests
EOF
while read task command
do
    echo BEGIN $task >> $LOG
    date >> $LOG
    if sh -c "$command" > $task.log 2>&1
    then
	if grep "Tests run:" $task.log | 
	    grep -v "Failures: 0, Errors: 0," > /dev/null
	then
	    echo FAIL >> $LOG
	elif grep -i warning $task.log > /dev/null
	then
	    echo WARN `grep -i warning $task.log | wc -l` >> $LOG
	else
	    echo PASS >> $LOG
	fi
    else
	echo FAIL >> $LOG
    fi
    date >> $LOG
done

mv $LOG ../../result_default
for logfile in *.log
do
    mv $logfile ../../result_default/$logfile.txt
done

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
