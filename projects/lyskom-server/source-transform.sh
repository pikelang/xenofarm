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

cp workdir/scripts/xenofarm.sh dist/create-response.sh
chmod +x dist/create-response.sh

tar cf $result.tar dist || exit 1
gzip $result.tar || exit 1
exit 0
