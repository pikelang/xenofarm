#!/bin/sh
project=$1
result=$2
stamp=$3

exec > source-transform.log 2>&1

rm -rf workdir dist
cp -a $project workdir
(cd workdir && ./mkmi)         # Run automake, autoconf et c
(cd workdir && ./configure -C) # Create makefiles
(cd workdir && make dist)      # Create lyskom-server-2.0.7.tar.gz
# FIXME: compare the contents of lyskom-server-2.0.7.tar.gz with
# the contents of $project.  Only a few known differences should exist.

# Build the Xenofarm source package in "dist".
mkdir dist
mv workdir/lyskom-server*tar.gz dist/
echo $stamp > dist/buildid.txt

# Compatibility names for client.sh:
echo $stamp > dist/export.stamp
echo $stamp > dist/exportstamp.txt

cat <<EOF > dist/Makefile
xenofarm:
	rm -f xenofarm_result.tar xenofarm_result.tar.gz
	mkdir r
	./create-response.sh > r/shlog.txt 2>&1
	(cd r && tar cf - *) > xenofarm_result.tar
	gzip -9 xenofarm_result.tar
EOF

cat <<'EOF' > dist/create-response.sh
#!/bin/sh

VERS=`echo lyskom-server*tar.gz|sed s/lyskom-server-//|sed s/.tar.gz//`
BASE=lyskom-server-$VERS

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
    if test $status = good
    then
	log Begin $task
        timeecho Begin $task
        if sh -c "$cmd" > r/${task}log.txt 2>&1
        then
	    touch r/$task.pass
        else
	    timeecho FAIL: $task
	    touch r/$task.fail
	    if [ $important = 1 ]
	    then
	        status=bad
	    fi
        fi
    fi
}

pfx=`pwd`/pfx

status=good

case `uname -n` in
  asmodean.lysator.liu.se)
      # We need the new makeinfo from /sw/local/bin, 
      # and want runtest from /sw/dejagnu.
      PATH=/sw/local/bin:$PATH:/sw/dejagnu/bin;;
  moghedien.lysator.liu.se)
      # We need the new makeinfo from /sw/local/bin.
      PATH=/sw/local/bin:$PATH;;
esac

dotask 1 "unzip" "gzip -d $BASE.tar.gz"
dotask 1 "unpack" "tar xf $BASE.tar"
dotask 1 "configure" "cd $BASE && ./configure -C --prefix=$pfx"
dotask 1 "make" "cd $BASE && make"

#
# "make check" requirements
#

checkdocok=true
checkprgok=true

# We need "grep -f"
(echo a;echo b;echo c) > input
(echo a;echo b) > pattern
if grep -v -f pattern input > output && test "`cat output`" = c
then
    :
else
    echo grep lacks -f support >> r/checkdoclog.txt
    checkdocok=false
fi

# We need "tac".
if tac < /dev/null
then
    :
else
    echo tac not found >> r/checkdoclog.txt
    checkdocok=false
fi

# We need "python".
if python -c ""
then
    :
else
    echo python not found >> r/checkdoclog.txt
    echo python not found >> r/checkprglog.txt
    checkdocok=false
    checkprgok=false
fi

# We need "runtest".
if runtest --version
then
    :
else 
    echo runtest not found >> r/checkprglog.txt
    checkprgok=false
fi


if $checkdocok
then
    dotask 0 "checkdoc" "cd $BASE/doc && make check"
fi

if $checkprgok
then
    dotask 0 "checkprg" "cd $BASE/src && make check"
fi

dotask 1 "install" "cd $BASE && make install"

if [ -f r/install.pass ]
then
    log Xenofarm OK
    find pfx -type f -print | sort > r/installedfiles.txt
fi

# FIXME: run distcheck.
# FIXME: compare the contents of the distcheck-generated tar file
# with the one we distributed.

log Begin response assembly
timeecho Collecting results

cp $BASE/config.cache r/configcache.txt
for file in $BASE/src/server/testsuite/*.log
do
  if test -f $file
  then
      cp $file r/`basename $file`.txt
  fi
done
# find $BASE -name core -print
env > r/environ.txt
echo $PATH > r/path.txt
makeinfo --version > r/makeinfo.txt
type makeinfo >> r/makeinfo.txt 2>&1

uname -s -r -m > r/machineid.txt
uname -n >> r/machineid.txt
cp buildid.txt r/buildid.txt

# FIXME: the next two lines are only here because of the current
# confusion regarding the name of the build id file.  Once we have
# settled on a name, and all clients are updated, it can be removed.
cp export.stamp r/export.stamp
cp exportstamp.txt r/exportstamp.txt

exit 0

EOF

chmod +x dist/create-response.sh

tar cf $result.tar dist || exit 1
gzip $result.tar || exit 1
exit 0
