#! /bin/sh

project=$1
result=$2
stamp=$3


exec > source-transform.log 2>&1

set -e

rm -rf workdir dist
cp -a $project workdir
(cd workdir && ./.bootstrap) # autoconf etc
(cd workdir && ./configure -C \
               --with-lib-path=/usr/local/lib \
	       --with-include-path=/usr/local/include ) # Create makefiles
(cd workdir && make dist)      # Create nettle-xx.tar.gz

mkdir dist
mv workdir/lsh-*.tar.gz dist/
echo $stamp > dist/buildid.txt

cp workdir/misc/xenofarm.sh dist/create-response.sh
chmod +x dist/create-response.sh

tar cf ./$result.tar dist
gzip ./$result.tar
exit 0
