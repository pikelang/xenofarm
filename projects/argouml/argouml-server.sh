#!/bin/sh
working=$1
name=$2
buildid=$3
echo $buildid > $working/buildid.txt
cat << EOF > $working/makefile
xenobuild:
	cd src_new && ../tools/ant-1.4.1/bin/ant package
EOF
tar cf $name.tar $working/build $working/lib $working/modules $working/src_new $working/tests $working/tools $working/buildid.txt $working/makefile || exit 1
gzip $name.tar || exit 1
rm $working/buildid.txt $working/makefile
