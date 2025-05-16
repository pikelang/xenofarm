#!/bin/sh

VERSION=1.3

##############################################
# Xenofarm client
#
# Written by Peter Bortas, Copyright 2002
# License: GPL
#
# Requirements:
#  gzip
#  curl
#
# Requirements that are normally fulfilled by the UNIX system:
# `ls -t`           should list files sorted by modification time
# `uname -n`        should print the nodename
# `uname -s -r -m`  should print OS and CPU info
# `kill -0 <pid>`   should return true if a process with that pid exists
# `LC_ALL="C" date` should return a space-separated string with where the
#                   first substring containing colons is on the form
#                   <hour>:<minute>.*
# tar 	            must be available in the PATH
# awk               must be available in the PATH
##############################################
# See `client.sh --help` for command line options.
#
# Error codes:
#  0: Exited without errors or was stopped by a signal
#  1: Unsupported argument
#  2: Client already running
#  3: Failed to compile retouch
#  4: Failed to create result package
#  5: dont_run file found
#  7: Remote compilation failure
#
#  9: Admin email not configured
# 11: gzip not found
# 12: Configuration directory not found
# 13: curl not found
#
# 14-30: Reserved for internal usage.

# curl 7.15.5 does not have --keepalive support, so use --speed-time
# and --max-time instead.  Set them to really high values so that they
# don't interfere with normal use.  Also use --connect-timeout to be
# on the safe side.
#
# Use --fail to fail on server errors, so that we can retry
# later.  This is especially important when we put results to the
# server.
CURLOPTS="--fail --speed-time 300 --max-time 3600 --connect-timeout 60"

msg() {
  echo `date '+%b %e %H:%M:%S'` "$@"
}

parse_args() {
 while [ ! c"$1" = "c" ] ; do
  case "$1" in
  '-h'|'--help')
  	sed -e "s/\\.B/`tput 'bold' 2>/dev/null`/g" -e "s/B\\./`tput 'sgr0' 2>/dev/null`/g" << EOF
.BXenofarm clientB.

Start it with cron or with the "start"-script.

If you encounter problems, see the .BREADMEB. for requirements and help.

   .BArguments:B.

      .B--config-dirB.:            Specify an alternate configuration directory.
      .B--helpB.:                  This information.
      .B--no-limitsB.:             Don't apply any ulimits.
      .B--silentB.:                Inhibit progress indicators.
      .B--versionB.:               Displays client version.
      .B--nodenameB.:              Display hosts nodename.
EOF
    	tput 'rmso' 2>/dev/null
	exit 0
  #emacs sh-mode kludge: '
  ;;
  '-v'|'--version')
	echo $VERSION
	exit 0
  ;;
  '-c='*|'--config-dir='*|'--configdir='*)
	config_dir="`echo $1|sed -e 's/.*=//'`"
  ;;
  '-c'|'--config-dir'|'--configdir')
	shift
	config_dir="$1"
  ;;
  '--nolimit'|'--no-limit'|'--nolimits'|'--no-limits')
	# Disable use of ulimit
	# Needed on cc/AIX.
	limits="no"
  ;;
  '--nodename')
        longest_nodename
        exit 0
  ;;
  '-s'|'--silent')
        silent="yes"
        # Redirect stdout to /dev/null, but keep stderr.
        exec >/dev/null
  ;;
  *)
	echo "Unsupported argument: $1" >&2
	echo "try --help" >&2
	exit 1
  esac
  shift
 done
}

get_time() {
    hour=`date | awk -F: '{ print $1 }' | awk '{ i=NF; print $i }'`
    minute=`date | awk -F: '{ print $2 }' | awk '{ print $1 }'`
}

#FIXME: Check if the project configurable build delay has passed
check_delay() {
    #FIXME: Just build always for now...
    :
}

#Make directories recursively.
pmkdir() {
    while [ ! -d $1 ]; do 
	rest=$1
	while [ ! -d $rest ]; do
	    tmp_dir=`basename $rest`
	    rest=`dirname $rest`
	done
	mkdir $rest/$tmp_dir || exit 21
    done
}

clean_exit() {
    rm -f $pidfile
    if [ gotlock="true" ] ; then
        rm -f lock.tmp
    fi
    exit $1
}

sigint() {
    msg "SIGINT received. Cleaning up and exiting." >&2
    clean_exit 0
}
sighup() {
    msg "SIGHUP received. Cleaning up and exiting for now." >&2
    clean_exit 0
}

missing_req() {
    msg "FATAL: $1 not found." >&2
    clean_exit $2
}

fetch_exit() {
    cat "fetch.log" >&2
    exit 23
}

mkdir_exit() {
    msg "FATAL: Unable to create a fresh build directory. Skipping to the next project." >&2
    exit 14
}

is_newer() {
    test "X`\ls -t \"$1\" \"$2\" 2>/dev/null | head -1`" = X"$1"
}

get_email() {
    while [ X$happy != X"yes" ] ; do
        if [ \! -f $config_dir/contact.txt ] ; then
        
            echo "Please type in an email address where the project maintainer can reach you:"
            if read email ; then
                :
	    else
		echo "EOF while reading email address" >&2
		exit 9
	    fi
            if [ X"$email" != X ] ; then
                echo "contact: $email" > $config_dir/contact.txt
                happy="yes"
            fi
        else
            happy="yes"
        fi
    done
}

check_multimachinecompilation() {
    if [ X$REMOTE_METHOD = "Xsprsh" ] ; then
	msg "Testing if remote machine is up..."
        sprsh cmd /c dir 2>/dev/null 1>&2
        res=$?
        case $res in
        '1')
            #Don't send this error to stderr. The remote machines are
            #currently often down for good reasons.
            msg "FATAL: Unable to contact remote system using $REMOTE_METHOD."
            exit 7;
            ;;
        esac
        if [ $res -gt 0 ]; then
            msg "FATAL: sprsh returned unknown error $res." 1>&2
            exit 7
        fi
    fi
}

sizeof() {
    echo $1 | wc -c
}

has_dot() {
    if [ X`echo $1|sed 's/\.//'` = X"$1" ]; then
	false
    else
	true
    fi
}

#Overcomplex function that tries to get a proper fqdn for the host.
longest_nodename() {
    #FIXME: This nasty heap of ifs needs to be replaced with something
    #better. Reverse&forward-lookup is not the answer. That would
    #render bad names for a lot of machines on locked down boring ISP
    #DNS names

    cur_node=`uname -n`
    fqdn=`hostname --fqdn`

    #To dangerous to fiddle with hostname switches if we are root.
    if kill -0 1 2>/dev/null; then
        msg "WARNING: You are running client.sh as root. Don't do that!" >&2
    else if hostname --fqdn >/dev/null 2>&1 && has_dot $fqdn; then
        tmp_node=`hostname --fqdn`
        if [ X$tmp_node != Xlocalhost.localdomain -o X$tmp_node != Xlocalhost ]; then
            cur_node=$tmp_node
        fi
    else
        t_hostname=`hostname`
        if [ `sizeof $cur_node` -lt `sizeof $t_hostname` ]; then
            cur_node=$t_hostname
        fi
        #FIXME: nodename should be normalized to valid chars.

	# If there is a domain entry in resolv.conf use it
        resolv_domain=`grep 'domain ' /etc/resolv.conf | head -1 | awk '{print $2}'`

	# If the search directive in resolv.conf only has one domain,
	# evaluate it for inclusion.
	resolv_search=`grep 'search ' /etc/resolv.conf | awk 'NF==2 {print $NF}'`

	# If "domainname" returns something, use that with top
	# priority, unless it's lacking dots, in that case use it as a
	# fallback.
	domainname=`domainname 2>/dev/null`

        # Still don't have a "." in the nodename, resort to desperate heuristics:
        if ! has_dot "$cur_node"; then
            # Does "domainname" return something with a "." in it?
            if [ X$domainname != X -a \
                 X$domainname != "X(none)" ] && has_dot $domainname; then
                cur_node=$cur_node.`domainname`
            # Does resolv.conf have a domain entry?
            else if [ X$resolv_domain != X ]; then
                     cur_node=$cur_node.$resolv_domain
            # Does "dnsdomainname" return something valid?
            else if [ X`dnsdomainname 2>/dev/null` != X -a \
                      X`dnsdomainname 2>/dev/null` != "X(none)" ]; then
                     cur_node=$cur_node.`dnsdomainname`
	    # Does resolv.conf have a valid search entry with only one domain
            else if has_dot $resolv_search; then
                     cur_node=$cur_node.$resolv_search
            # Does "domainname" return something, nevermind if it's lacking dots?
            else if [ X$domainname != X -a \
                 X$domainname != "X(none)" ]; then
                cur_node=$cur_node.`domainname`
            fi; fi; fi; fi; fi
        fi
    fi; fi

    echo $cur_node
}


setup_pidfile() {
    node=`longest_nodename`
    unames=`uname -s`
    unamer=`uname -r`
    unamem=`uname -m`
    unamev=`uname -v`
    pidfile="`pwd`/xenofarm-$node.pid"
    if [ -r $pidfile ]; then
        pid=`cat $pidfile`
        if `kill -0 $pid > /dev/null 2>&1`; then
            # NB: Message not on stderr, since it is normal when
            #     run from eg cron that the previous job has not
            #     finished yet.
            msg "FATAL: Xenofarm client already running. pid: $pid"
            exit 2
        else
            msg "NOTE: Removing stale pid-file."
            rm -f $pidfile
        fi
    fi

    echo $$ > $pidfile
}

#Make sure we don't compile the retouch command on more than one node at the time
#NOTE: This can deadlock if the client is killed without giving it a
#      chance to clean up during the put compilation.
spinlock() {
    while [ X$gotlock != X"true" ] ; do
        if [ \! -f lock.tmp ] ; then
            echo `uname -n` > lock.tmp
        else 
            holder=`cat lock.tmp`
            if [ X$holder = X`uname -n` ] ; then
                msg "Got compilation lock."
                gotlock="true"
            else
                msg "Waiting for $holder to release compilation lock."
                sleep 60
            fi
        fi
    done
}

releaselock() {
    rm lock.tmp
    gotlock="false"
}

# Return 0 if a new snapshot has been downloaded.
have_newer_snapshot() {
    # No downloaded candidate => no.  This is the most common branch,
    # as curl shouldn't download anything unless what is on the server
    # is newer than the old snapshot.
    [ -f dl/snapshot.tar.gz ] || return 1

    # No old download, but a new candidate => yes.  This happens on
    # the first run of a project.
    [ -f snapshot.tar.gz ] || return 0

    OLD="`ls -l snapshot.tar.gz 2>/dev/null`"
    NEW="`cd dl&&ls -l snapshot.tar.gz 2>/dev/null`"

    # Timestamp and/or size differ => yes.
    [ "$OLD" == "$NEW" ] || return 0

    # Same size, same timestamp (using minute resolution), and
    # same content => no.
    cmp snapshot.tar.gz dl/snapshot.tar.gz >/dev/null || return 1

    # Apparently, the content differs, so we have a new download even
    # though the size and minute-resolution timestamp are the same.
    # This is unlikely, but can happen...
    return 0
}

# Change the modification time of $1 so it becomes one second newer.
make_newer() {
    if $stat_touch
    then
        touch -d @`expr \`stat -c %Y "$1"\` + 1` "$1"
    else
        $basedir/$retouchname "$1"
    fi
}

#Called to prepare the project build environment. Not reapeated for each id.
prepare_project() {
    msg " First test in this project. Preparing build environment."
    fulldir="$fulldir/$node"
    if [ ! -d "$fulldir/dl" ]; then
        pmkdir "$fulldir/dl"
    fi

    cd "$fulldir" || exit 4
    msg " Downloading $project snapshot..."
    curl $CURLOPTS -e "$node" -L -R -z snapshot.tar.gz -o dl/snapshot.tar.gz "$geturl" \
        > "fetch.log" 2>&1 || fetch_exit
    if $curl_broken_z && [ -f dl/snapshot.tar.gz ]
    then
        make_newer dl/snapshot.tar.gz
    fi
    if ! have_newer_snapshot; then
        msg " NOTE: No newer snapshot for $project available."
    else
        # The snapshot will have a time stamp synced to the server. To
        # compensate for drifting clocks (not time zones, that is
        # handled by curl) on the clients we make a local stamp
        # file. As this file is not consulted when downloading new
        # snapshot it doesn't matter if a new snapshot is released while
        # the first one is downloaded. (Yes, this long text is necessary.)
        touch localtime_lastdl

        # Now that we have flagged that we have a new download to
        # compile, move the new file to its destination.  We have to
        # do it in this order to ensure we don't forget to compile
        # this if we are interrupted.
        mv -f dl/snapshot.tar.gz snapshot.tar.gz
    fi

    cd "$basedir"
}

uncompress_exit() {
    msg "Failed to uncompress snapshot. Removing possibly damaged file." >&2
    rm -f $1
    exit 17
}

put_exit() {
    msg "Failed to send result. Resending in the next client run." >&2
    date=`date | sed -e 's/ //g' -e 's/://g'` &&
    (pmkdir "$fulldir/rescue_$test/$date") &&
    mv "$resultdir/xenofarm_result.tar.gz" \
       "$fulldir/rescue_$test/$date/xenofarm_result.tar.gz"
    exit 24
}

put_resume() {
    cd "$fulldir"
    ls rescue_$test/* >/dev/null 2>&1 &&
    for x in rescue_$test/*; do
        tmp=""
        if [ -f $x/xenofarm_result.tar.gz ] ; then
            msg "Resending $x/xenofarm_result.tar.gz."
            curl $CURLOPTS -T "$x/xenofarm_result.tar.gz" "$puturl" \
                || tmp="fail"
            if [ X$tmp != Xfail ] ; then
                rm $x/xenofarm_result.tar.gz
                rmdir $x
            else
                msg "Failed to resend. Resending in the next client run." >&2
            fi
        else
            rmdir $x 
        fi
    done
}

make_machineid() {
       echo "sysname: $unames"  >  machineid.txt &&
       echo "release: $unamer"  >> machineid.txt &&
       echo "version: $unamev"  >> machineid.txt &&
       echo "machine: $unamem"  >> machineid.txt &&
       echo "nodename: $node"   >> machineid.txt &&
       echo "testname: $test"   >> machineid.txt &&
       echo "command: $command" >> machineid.txt &&
       echo "clientversion: `$basedir/client.sh --version`" \
                                >> machineid.txt &&
       if $curl_broken_z && ! $stat_touch
       then
           echo "retouchversion: `$basedir/$retouchname --version`" \
                                >> machineid.txt
       fi &&
       cat "$basedir/$config_dir/contact.txt" >> machineid.txt
}

check_test_environment() {
    if [ X"$configformat" = X ] || [ X"$project" = X ] || 
       [ X"$fulldir" = X ] || [ X"$geturl" = X ] || 
       [ X"$puturl" = X ] ; then
        msg "FATAL: Missing options in $projectconfig." >&2
        exit 18
    fi
}

#Run _one_ test
run_test() {
    if [ -f dont_run ]; then
	msg "FATAL: dont_run file found. Doing that." 1>&2
	exit 5
    fi

    check_test_environment


    msg "Building project \"$project\" from $geturl."
    if [ X"$environment" != X ] ; then
	msg " Environment: \"$environment\"."
    fi    
    if [ X"$first_project_run" = Xtrue ] ; then
        prepare_project
    fi
    msg " Running test \"$test\" in $fulldir."

    #Check for earlier results and try to send them
    put_resume

    (   cd "$fulldir"
        [ -d config_cache/. ] || mkdir config_cache

        if [ \! -f "last_$test" ] ||
               is_newer localtime_lastdl "last_$test" ; then
            get_time
            echo $hour:$minute > "current_$test";

            CONFIG_CACHE_FILE="$fulldir/config_cache/config_$test.cache"
            export CONFIG_CACHE_FILE
            if [ -d buildtmp/. ]; then
                if rm -rf buildtmp 2>/dev/null; then :; else
                    # Possibly locked by .nfs lock files.
                    test -d nfslocks/. || mkdir nfslocks || mkdir_exit
                    find buildtmp -type f -name '.nfs*' \
                         -exec mv -f \{\} nfslocks/ \;
                    # Truncate and cleanup the lock files.
                    for f in nfslocks/.nfs*; do
                        >$f
                        rm -f $f 2>&1
                    done
                    rm -rf buildtmp || mkdir_exit
                fi
            fi
            mkdir buildtmp || mkdir_exit
            cd buildtmp || mkdir_exit
            if `check_delay`; then
                if [ $uncompressed != "true" ] ; then
                    msg " Uncompressing archive..." &&
                    rm -f "$fulldir/snapshot.tar" &&
                    test -f "$fulldir/snapshot.tar.gz" &&
                    #This will not fail on full disk, but the tar should
                    gzip -cd "$fulldir/snapshot.tar.gz" \
                        > "$fulldir/snapshot.tar" || 
                            uncompress_exit "$fulldir/snapshot.tar.gz"
                    uncompressed="true"
                fi
                msg "  Extracting archive..." &&
                test -f ../snapshot.tar &&
                tar xf ../snapshot.tar || exit 22

                cd */.
                msg "  Building and running test \"$test\": \"$command\""
                resultdir="../../result_$test"
                rm -rf "$resultdir" && mkdir "$resultdir" || exit 19

                cp buildid.txt "$resultdir" || exit 20
                if [ X"$environment" != X ] ; then
                    export environment
                    #NOTE: This is unconfortably complex and
                    # unreadable, but it's done in the sh -c environment
                    # to avoid local environment pollution. That might
                    # not be a concern as this is currently run in a
                    # subshell, but the subshell levels are not stable
                    # yet so this prevents nasty surprises for now.
                    sh -c "for a in \$environment; do if [ X\`echo \$a\` != X\`echo \$a|sed s/=//\` ]; then eval \$environment export \`echo \$a | awk -F= '{print \$1}'\`; fi; done && $command" \
                        > "$resultdir/xenofarmclient.txt" 2>&1;
                else
                    sh -c "$command"  > "$resultdir/xenofarmclient.txt" 2>&1;
                fi

                #If the remote node has disappeared we would send a false fail
                check_multimachinecompilation

                if [ -f "$CONFIG_CACHE_FILE" ]; then
                    if grep FAIL xenofarm_result/mainlog.txt \
                            >/dev/null 2>&1; then
                        # Build failure of some kind.
                        # Save the config cache file for later.
                        msg "Saving config.cache file: $CONFIG_CACHE_FILE.save"
                        mv -f "$CONFIG_CACHE_FILE" "$CONFIG_CACHE_FILE.save"
                    fi
                fi

                if [ -d xenofarm_result ] ; then
                    cp buildid.txt xenofarm_result
                    (
                     cd xenofarm_result &&
                     make_machineid &&
                     tar cf xenofarm_result.tar * &&
                     gzip xenofarm_result.tar &&
                     cd .. &&
                     mv xenofarm_result/xenofarm_result.tar.gz "$resultdir"
                    ) || exit 25
                elif [ -f xenofarm_result.tar.gz ] ; then
                    # This branch is for support of the old API
                    # and is deprecated. FIXME: Remove in next major.
                    mv xenofarm_result.tar.gz "$resultdir" || exit 25
                    (
                     cd "$resultdir" &&
                     rm -rf repack &&
                     mkdir repack &&
                     cd repack &&
                     gzip -cd "$resultdir/xenofarm_result.tar.gz" | tar xf - &&
                     make_machineid &&
                     tar cf xenofarm_result.tar * &&
                     gzip xenofarm_result.tar &&
                     mv xenofarm_result.tar.gz "$resultdir"
                    ) || exit 25
                else
                    (
                     cd "$resultdir" &&
                     make_machineid &&
                     tar cf xenofarm_result.tar * &&
                     gzip xenofarm_result.tar
                    ) || exit 25
                fi
                mv "../../current_$test" "../../last_$test";
                msg "  Sending results for \"$project\": \"$test\"."
                curl $CURLOPTS -T "$resultdir/xenofarm_result.tar.gz" \
                    "$puturl" || put_exit
                echo
                cd "$fulldir/buildtmp"
            else
                msg " NOTE: Build delay for \"$project\" not passed. Skipping."
            fi
        else
            msg "  NOTE: Already built \"$project\": \"$test\". Skipping."
        fi
    )
    last=$?
    if [ X"$last" != X0 ] ; then
        msg "Project \"$project\" failed with exit code $last" >&2
        # 14-30: Reserved for internal usage.
        # 14: Unable to create build directory.
        # 15: Unknown config format.
        # 16: Unknown parameter in config file.
        # 17: Unable to decompress project snapshot.
        # 18: Missing option in config file.
        # 19: Unable to create fresh result directory.
        # 20: Failed to find buildid.txt in snapshot.
        # 21: Recursive mkdir failed.
        # 22: Unable to extract project snapshot.
        # 23: Failed to fetch project snapshot.
        # 24: Failed to send result.
        # 25: Failed to create result package.
        # 26: Failed to rename snapshot2.tar.gz to snapshot.tar.gz
        #Be more verbose in some common cases:
        case $last in
        '20')
            msg "FATAL: Failed to find buildid.txt in snapshot!" >&2
            ;;
        '22')
            msg "FATAL: Unable to extract \"$project\" snapshot!" >&2
            ;;
        '23')
            msg "FATAL: Failed to download \"$project\" snapshot!" >&2
            ;;
        '24')
            msg "FATAL: Failed to send result package to $puturl!" >&2
            ;;
        '26')
            msg "FATAL: Failed to rename downloaded \"$project\" snapshot!" >&2
            ;;
        esac
    fi
}

#Remove spaces in the beginning and end of a string.
chomp_ends() {
    # No need to do anything exotic, since the shell does it for us.
    #FIXME: Yes there is. This will remove spaces inside the string.
    echo $1
}

#Read only the node specific configuration file if it exists.
#FIXME: This requires a base config file.
get_nodeconfig() {
    if [ -f "$projectconfig.$node" ] ; then
        projectconfig="$projectconfig.$node";
        msg "NOTE: Found node config file: $projectconfig"
    fi
}

setup_retouch() {
    echo $retouchname
    if [ ! -x $retouchname ] ; then
        spinlock
        rm -f config.cache
        ./configure
        make clean
        make retouch
        if [ ! -x retouch ] ; then
            msg "FATAL: Failed to compile retouch." >&2
            clean_exit 3
        else
            mkdir bin 2>/dev/null
            mv retouch $retouchname
        fi
        releaselock
    fi
}


#########################################################
#Execution begins here.
#########################################################

#Exit if there is a file called "dont_run".
if [ -f dont_run ]; then
    msg "FATAL: dont_run file found. Doing that." 1>&2
    exit 5
fi

#Set up signal handlers
trap sighup 1
trap sigint 2
trap sigint 15

#Add a few directories to the PATH
PATH=$PATH:/usr/local/bin:/sw/local/bin
#cc on UNICOS fails to build with exotic settings like LC_CTYPE=iso_8859_1
LC_ALL=C
export PATH LC_ALL

#Default config dir. Can be changed with the --config-dir parameter.
config_dir="config"

# Use ulimit by default
limits=yes

# Be verbose by default
silent=no

#Get user input
parse_args $@

if [ -d "$config_dir/." ]; then :; else
    msg "FATAL: Configuration directory \"$config_dir\" does not exist." >&2
    exit 12
fi

if [ "x$silent" = "xyes" ]; then
    # NB: The curl progress bar is on stderr, so to disable it,
    #     it is not sufficient to just redirect stdout. Keep
    #     any error messages.
    CURLOPTS="$CURLOPTS -s -S"
else
    # Use a progress bar instead of the default progress meter
    # to avoid lots of junk when output is captured to a file.
    CURLOPTS="$CURLOPTS -#"
fi

if [ "x$limits" = "xno" ]; then :; else
  #Try to limit the damage if something goes out of hand.
  # NOTE: Limitations are per spawned process. You can still get plenty hurt.
  # TODO: Total time watchdog?
  # TODO: Remote compilation limits?
  ulimit -d 2097152 2>/dev/null || # data segment   < 2048 MiB
      msg "NOTE: Failed to limit data segment. Might already be lower."
  ulimit -v 2097152 2>/dev/null || # virtual memory < 2048 MiB
      msg "NOTE: Failed to limit virtual mem. Might already be lower."
  ulimit -t 14400  2>/dev/null || # CPU            < 4h
      msg "NOTE: Failed to limit CPU time. Might already be lower."
fi

get_email

#Check and handle the pidfile for this node
setup_pidfile

#Make sure the remote nodes are up in a multi machine compilation setup
check_multimachinecompilation

#If we are running a sprshd build the retouch command should be on the local node
if [ X$REMOTE_METHOD = "Xsprsh" ] ; then
    #FIXME: See if this uname location is reasonably portable
    #FIXME: Now that the nodename finder otherwhere is so clever this can fail.
    retouchname=bin/retouch-`/bin/uname -n`
else
    retouchname=bin/retouch-$node
fi


#Make sure curl and gzip exists
gzip --help > /dev/null 2>&1 || missing_req gzip 11
# Older versions of curl (7.15.5) exit with exit status 2 when given
# --help or --version, so use this convoluted test instead.
curl --version 2>/dev/null | grep libcurl >/dev/null 2>&1 || missing_req curl 13

# The -z option of curl is broken in version 7.21 and earlier.
# Instead of downloading a file only if it is strictly newer than the
# local timestamp, it will download the file also if the timestamps
# are equal. We have two strategies to work around this issue:
#
# 1. If GNU touch and GNU stat are available, we can use them to
#    increase the timestamp of snapshot.tar.gz one second.
# 2. If we can compile retouch.c, that binary can increase the
#    timestamp of snapshot.tar.gz one second.
curl_version=`curl --version | awk '{print $2;exit}'`
curl_major=`echo $curl_version|awk -F. '{print $1}'`
curl_minor=`echo $curl_version|awk -F. '{print $2}'`
curl_broken_z=false
if [ $curl_major -lt 7 ]
then
    curl_broken_z=true
fi
if [ $curl_major -eq 7 ] && [ $curl_minor -lt 22 ]
then
    curl_broken_z=true
fi
if $curl_broken_z
then
    rm -f old.test new.test
    touch old.test
    sleep 1
    touch new.test
    ts=`stat -c %Y old.test 2>/dev/null`
    if [ "x$ts" != "x" ]
    then
        touch -d @`expr $ts + 3` old.test 2>/dev/null
    fi
    if is_newer old.test new.test
    then
        echo "curl -z is broken; using stat and touch"
        stat_touch=true
    else
        stat_touch=false

        #Make sure there is a retouch command available for this node
        setup_retouch
        echo "curl -z is broken; using retouch"
    fi
    rm -f old.test new.test
fi

#Build Each project and each test in that project sequentially
basedir="`pwd`"
for projectconfig in $config_dir/*.cfg; do 
(
    #TODO: Propagate more errors to the user?
    configformat="" ; testnames="" ; testcmds=""
    first_project_run="true"
    uncompressed="false"
    get_nodeconfig

    #TODO: Remove order dependency on settings.
    (sed -e '/^#/d' <$projectconfig; echo) | while read line; do
        type=`echo "$line" | awk -F: '{ print $1 }'`
        arguments=`echo "$line" | sed -e 's/[^:]*://'`
        arguments=`chomp_ends "$arguments"`
        case $type in
        configformat)
            if [ X"$arguments" != X2 -a X"$arguments" != X3 ] ; then
                msg "Unknown configformat $arguments in $projectconfig" >&2
                exit 15
            fi
            configformat="$arguments"
            ;;
        project)
            project=$arguments  ;;
        projectdir)
            dir=$arguments      
	    case "$dir" in
		/*) fulldir="$dir" ;;
		*) fulldir="$basedir/$dir" ;;
	    esac
	    ;;
        snapshoturl)
            geturl=$arguments   ;;
        resulturl)
            puturl=$arguments   ;;
        mindelay)
            delay=$arguments    ;;
        environment)
            if [ $configformat = 2 ] ; then
                msg "environment: not supported in config format v2." >&2
                exit 16;
            else
                environment="$environment $arguments"
            fi
            ;;
        test-$node)
            if [ X$running_default_tests = X -o \
                 X$running_default_tests = Xfalse ] ; then
                msg "NOTE: Found node specific tests in \"$projectconfig\"." 
                running_default_tests="false"
                test=`echo $arguments | awk '{ print $1 }'`
                command=`echo $arguments | sed -e 's/[^ ]* //'`
                command=`chomp_ends "$command"`
                run_test
                first_project_run="false"                
            else
                msg " FATAL: Node specific tests must be before the standard tests." >&2
                exit 18
            fi
            ;;
        test)
            if [ X$running_default_tests = X -o \
                 X$running_default_tests = Xtrue ] ; then
                running_default_tests="true"
                #NOTE: Code duplication for clarity. Might reconsider.
                test=`echo $arguments | awk '{ print $1 }'`
                command=`echo $arguments | sed -e 's/[^ ]* //'`
                command=`chomp_ends "$command"`
                run_test
                first_project_run="false"
            else
                msg " NOTE: Skipped standard test overridden by node test."
            fi
            ;;
        test-*) #Configurations for some other node. Ignore.
            : ;;
        "")
            : ;;
        *)
            msg "Unknown parameter \"$line\" in $projectfile." >&2
            exit 16
        esac
    done
    #On to the next project
    configformat="" ; project="" ; dir=""   ; fulldir=""
    geturl=""       ; puturl=""  ; delay="" ; environment=""
)
done

msg "All projects built. Exiting."

clean_exit $?
