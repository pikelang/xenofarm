#!/bin/sh
working=$1
name=$2
tar cf $name.tar $working || exit 1
gzip $name.tar || exit 1
echo lyskom-server/source-transform.sh OK >&2
exit 0
