#!/bin/sh
exec ../../server.pike \
	--repository=:pserver:guest@cvs.tigris.org:/cvs \
	--update-opts=-d \
	--cvs-module=argouml \
	--db=`cat /home/linus/.argouml_xenofarm_mysqlurl` \
	--web-dir=/lysator/www/projects/xenofarm/argouml/export \
	--work-dir=/lysator/www/projects/xenofarm/argouml/work \
	--source-transform=`pwd`/argouml-server.sh \
	"$@" argouml
