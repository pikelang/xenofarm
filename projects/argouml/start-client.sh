#!/bin/sh

# Set JAVA_HOMEs.
JAVA_HOME_1_2=${JAVA_HOME_1_2-/sw/jdk/jdk1.2}
JAVA_HOME_1_3=${JAVA_HOME_1_3-/sw/jdk/j2sdk1_3_0_02}
export JAVA_HOME_1_2 JAVA_HOME_1_3

ANT_OPTS=${ANT_OPTS--Xmx512M}
export ANT_OPTS

cd ../../client && ./client.sh --nolimit --configdir=../projects/argouml
