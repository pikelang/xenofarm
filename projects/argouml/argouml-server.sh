#!/bin/sh
working=$1
name=$2
buildid=$3
echo $buildid > $working/buildid.txt
cat << EOF > $working/makefile
.PHONY: xant
xant:
	chmod +x tools/ant-1.4.1/bin/ant
package: xant
	cd src_new && ../tools/ant-1.4.1/bin/ant package
tests: xant
	cd src_new && ../tools/ant-1.4.1/bin/ant tests
javadoc: xant
	cd src_new && ../tools/ant-1.4.1/bin/ant prepare-docs
printablehtml: xant
	cd documentation && ../tools/ant-1.4.1/bin/ant printablehtml
EOF
cat <<EOF > $working/EXCLUDED
*/CVS/*
*/CVS/
*/CVS
EOF
tar cf $name.tar -X $working/EXCLUDED $working/build $working/documentation $working/lib $working/modules $working/src_new $working/tests $working/tools $working/buildid.txt $working/makefile || exit 1
gzip $name.tar || exit 1
rm $working/buildid.txt $working/makefile $working/EXCLUDED
