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

echo FORMAT 2 > $LOG

# Independant tasks!
cat <<EOF |
package	cd src_new && ../tools/ant-1.4.1/bin/ant package
tests	cd src_new && ../tools/ant-1.4.1/bin/ant tests
prepare-docs	cd src_new && ../tools/ant-1.4.1/bin/ant prepare-docs
EOF
while read task command
do
    echo BEGIN $task >> $LOG
    date >> $LOG
    if sh -c "$command"
    then
	echo PASS >> $LOG
    else
	echo FAIL >> $LOG
    fi
    date >> $LOG
done

mv $LOG ../../result_default

# Include the result.
cat <<EOF |
build/tests/reports/junit/output/html test-result
build/javadocs javadocs
build/argouml.jar argouml.jar
EOF
while read file place
do
    test -r $file && mv $file ../../result_default/$place
done

E1OF

chmod +x $working/doit.sh

cat <<\EOF > $working/EXCLUDED
*/CVS/*
*/CVS/
*/CVS
EOF
tar cf $name.tar -X $working/EXCLUDED $working/build $working/lib $working/modules $working/src_new $working/tests $working/tools $working/buildid.txt $working/doit.sh || exit 1
gzip $name.tar || exit 1
rm $working/buildid.txt $working/doit.sh $working/EXCLUDED
