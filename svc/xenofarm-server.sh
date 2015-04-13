#!/sbin/sh

. /lib/svc/share/smf_include.sh

getprop() {
    PROPVAL=""
    svcprop -q -p $1 ${SMF_FMRI}
    if [ $? -eq 0 ] ; then
        PROPVAL=`svcprop -p $1 ${SMF_FMRI}`
        if [ "${PROPVAL}" = "\"\"" ] ; then
            PROPVAL=""
        fi
        return
    fi
    return
}

getprop xenofarm/pike
PIKE="$PROPVAL"

getprop xenofarm/server
SERVER="$PROPVAL"

if [ -f $SERVER -a -f $PIKE ] ; then
  echo "Running $SERVER"
   PATH=/usr/gnu/bin:$PATH
   export PATH
   export DBURL
   (while $PIKE $SERVER ;do sleep 5; done ) & 
   exit $SMF_EXIT_OK
fi

echo "The xenofarm server seems to be configured incorrectly."
echo "Indexer: $SERVER"
echo "Pike: $PIKE"
exit $SMF_EXIT_ERR_CONFIG
