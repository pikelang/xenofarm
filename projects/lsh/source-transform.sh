#! /bin/sh

project=$1
result=$2
stamp=$3

exec > source-transform.log 2>&1

set -e

rm -rf workdir dist
cp -a $project workdir
(cd workdir && misc/bootstrap) # Run automake, autoconf etc
(cd workdir && ./configure -C) # Create makefiles
(cd workdir && make bootstrap) # Generate source files
(cd workdir && misc/make-dist) # Create lsh-xx.tar.gz

mkdir dist
mv workdir/lsh-*.tar.gz dist/
echo $stamp > dist/buildid.txt

cp workdir/misc/xenofarm.sh dist/create-response.sh
chmod +x dist/create-response.sh

tar cf $result.tar dist
gzip $result.tar
exit 0
