#!/bin/sh

cd ../../client
exec ./client.sh --nolimit > start-client`date +%H`.log

