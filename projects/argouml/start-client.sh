#!/bin/sh

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

while true
do
    ( cd ../../client && ./client.sh --configdir=../projects/argouml )
    sleep 3600
done
