#! /bin/sh

PATH=/i/automake/1.7.2/bin:/i/autoconf/2.57/bin:/usr/local/bin:/usr/bin:/bin:/usr/ccs/bin
export PATH

liboop=/pkg/liboop/src/liboop-1.0.tar.gz

# Don't know why gcc doesn't search /usr/local/lib by default. Using
# LD_LIBRARY_PATH seems easier than passing flags to configure.

# LD_LIBRARY_PATH=/usr/local/lib

project=$1
result=$2
stamp=$3


exec > source-transform.log 2>&1

set -e

rm -rf workdir dist
cp -a $project workdir
(cd workdir && ./.bootstrap) # Run automake, autoconf etc
(cd workdir && ./configure -C \
               --with-lib-path=/usr/local/lib \
	       --with-include-path=/usr/local/include ) # Create makefiles
(cd workdir && make bootstrap) # Generate source files
(cd workdir && make dist)      # Create lsh-xx.tar.gz

mkdir dist
mv workdir/lsh-*.tar.gz dist/
echo $stamp > dist/buildid.txt

cp workdir/misc/xenofarm.sh dist/create-response.sh
chmod +x dist/create-response.sh

cp $liboop dist

tar cf ./$result.tar dist
gzip ./$result.tar
exit 0
