#!/bin/sh
exec ../../result_parser.pike \
	--db=`cat /home/linus/.argouml_xenofarm_mysqlurl` \
	--web-dir=/lysator/www/projects/xenofarm/argouml/files \
	--result-dir=/lysator/www/projects/xenofarm/argouml/results \
	--work-dir=/lysator/www/projects/xenofarm/argouml/work/res \
	"$@" 
