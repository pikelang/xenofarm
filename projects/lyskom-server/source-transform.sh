#!/bin/sh
project=$1
result=$2
stamp=$3

rm -rf workdir dist
cp -a $project workdir
(cd workdir && ./mkmi)         # Run automake, autoconf et c
(cd workdir && ./configure -C) # Create makefiles
(cd workdir && make dist)      # Create lyskom-server-2.0.7.tar.gz
# FIXME: compare the contents of lyskom-server-2.0.7.tar.gz with
# the contents of $project.  Only a few known differences should exist.
mkdir dist
mv workdir/lyskom-server*tar.gz dist/
echo buildtime: $stamp > dist/export.stamp
echo buildtime: $stamp > dist/exportstamp.txt

cat <<EOF > dist/Makefile
xenofarm:
	rm -f xenofarm_result.tar xenofarm_result.tar.gz
	mkdir r
	./create-response.sh > r/xenofarmclient.txt 2>&1
	# Be forward/backward compatible.
	cp r/xenofarmclient.txt r/RESULT
	# FIXME: we might want to include other stuff as well.
	(cd r && tar cf - *.txt RESULT export.stamp) > xenofarm_result.tar
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

pfx=`pwd`/pfx

status=good
if test $status = good
then
    timeecho unzipping source dist
    if gzip -d $BASE.tar.gz
    then :
    else
	timeecho gunzip failed
	status=bad
    fi
fi

if test $status = good
then
    timeecho untaring source dist
    if tar xf $BASE.tar > r/untar.txt 2>&1
    then
	touch r/unpack.pass
    else
	timeecho untar failed
	touch r/unpack.fail
	status=bad
    fi
fi

if test $status = good
then
    timeecho running configure
    if (cd $BASE && ./configure --prefix=$pfx) > r/configure.txt 2>&1
    then
	touch r/cfg.pass
    else
	timeecho configure failed
	touch r/cfg.fail
	status=bad
    fi
fi

if test $status = good
then
    timeecho running make
    if (cd $BASE && make) > r/make.txt 2>&1
    then
	touch r/make.pass 
    else
	timeecho make failed
	touch r/make.fail
	status=false
    fi
fi

if test $status = good
then
    timeecho running make check
    if (cd $BASE && make check) > r/check.txt 2>&1
    then
	timeecho make check ok
	touch r/check.pass
    else
	timeecho make check failed
	touch r/check.fail
    fi
fi

if test $status = good
then
    timeecho running make install
    if (cd $BASE && make install) > r/install.txt 2>&1
    then
	timeecho make install ok
	touch r/install.pass
	find pfx -type f -print | sort > r/installedfiles.txt
    else
	timeecho make install failed
	touch r/install.fail
    fi
fi

# FIXME: run distcheck.
# FIXME: compare the contents of the distcheck-generated tar file
# with the one we distributed.

timeecho Collecting results
cp $BASE/config.cache r/configcache.txt
mkdir r/testsuite
for file in $BASE/src/server/testsuite/*.log
do
  if test -f $file
  then
      cp $file r/`basename $file`.txt
  fi
done
find $BASE -name core -print

uname -s -r -m > r/machineid.txt
uname -n >> r/machineid.txt
if [ -f export.stamp ]
then 
    cp export.stamp r/exportstamp.txt
    cp export.stamp r/export.stamp
fi
if [ -f exportstamp.txt ]
then 
    cp exportstamp.txt r/exportstamp.txt
    cp exportstamp.txt r/export.stamp
fi
exit 0

EOF

chmod +x dist/create-response.sh

tar cf $result.tar dist || exit 1
gzip $result.tar || exit 1
exit 0
