#!/bin/sh

##############################################
# Xenofarm client
#
# Written by Peter Bortas, Copyright 2002
# $Id: client.sh,v 1.83 2008/12/13 23:22:40 mast Exp $
# Distribution version: 1.3
# License: GPL
#
# Requirements:
#  gzip
#  wget              Must handle -N and set the timestamp correctly.
#                    Must handle --header.
#                    Versions 1.6 and prior of wget are know to mangle 
#                    the timestamps and will cause occasional missed 
#                    builds. Versions 1.8.2 and newer are known to work.
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
#  3: Failed to compile put
#  4: Failed to create result package
#  5: dont_run file found
#  7: Remote compilation failure
#
#  9: Admin email not configured
# 10: wget not found
# 11: gzip not found
# 12: Configuration directory not found
#
# 14-30: Reserved for internal usage.

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
      .B--versionB.:               Displays client version.
      .B--nodenameB.:              Display hosts nodename.
EOF
    	tput 'rmso' 2>/dev/null
	exit 0
  #emacs sh-mode kludge: '
  ;;
  '-v'|'--version')
	echo \$Id: client.sh,v 1.83 2008/12/13 23:22:40 mast Exp $
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

wget_exit() {
    cat "wget.log" >&2
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
        echo "Testing if remote machine is up..."
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

#Overcomplex function that tries to get a proper fqdn for the host.
longest_nodename() {
    #FIXME: This nasty heap of ifs needs to be replaced with something
    #better. Reverse&forward-lookup is not the answer. That would
    #render bad names for a lot of machines on locked down boring ISP
    #DNS names

    cur_node=`uname -n`

    #To dangerous to fiddle with hostname switches if we are root.
    if kill -0 1 2>/dev/null; then
        msg "WARNING: You are running client.sh as root. Don't do that!" >&2
    else if hostname --fqdn >/dev/null 2>&1; then
        tmp_node=`hostname --fqdn`
        if [ X$tmp_node != Xlocalhost.localdomain ]; then
            cur_node=$tmp_node
        fi
    else
        t_hostname=`hostname`
        if [ `sizeof $cur_node` -lt `sizeof $t_hostname` ]; then
            cur_node=$t_hostname
        fi
        #FIXME: nodename should be normalized to valid chars.
        resolv_domain=`grep 'domain ' /etc/resolv.conf | head -1 | awk '{print $2}'`
        #This won't help for nodes that already have dots in their !domainnames
        if [ X`echo $cur_node|sed 's/\.//'` = X$cur_node ]; then
            if [ X`domainname 2>/dev/null` != X -a \
                 X`domainname 2>/dev/null` != "X(none)" ]; then
                cur_node=$cur_node.`domainname`
            else if [ X$resolv_domain != X ]; then
                cur_node=$cur_node.$resolv_domain
            else if [ X`dnsdomainname 2>/dev/null` != X -a \
                      X`dnsdomainname 2>/dev/null` != "X(none)" ]; then
                cur_node=$cur_node.`dnsdomainname`
            fi; fi; fi
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
            msg "NOTE: Xenofarm client already running. pid: $pid"
            exit 2
        else
            msg "NOTE: Removing stale pid-file."
            rm -f $pidfile
        fi
    fi

    echo $$ > $pidfile
}

#Make sure we don't compile the put command on more than one node at the time
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

#Called to prepare the project build environment. Not reapeated for each id.
prepare_project() {
    msg " First test in this project. Preparing build environment."
    fulldir="$fulldir/$node"
    if [ ! -d "$fulldir/." ]; then
        pmkdir "$fulldir"
    fi  

    cd "$fulldir" &&
     NEWCHECK="`ls -l snapshot.tar.gz 2>/dev/null`";
     msg " Downloading $project snapshot..."
     #FIXME: Check for old broken wgets.
     wget --header="Referer: $node" --dot-style=binary -N "$geturl" \
        > "wget.log" 2>&1 &&
     if [ X"`ls -l snapshot.tar.gz`" = X"$NEWCHECK" ]; then
        msg " NOTE: No newer snapshot for $project available."
     else
        # The snapshot will have a time stamp synced to the server. To
        # compensate for drifting clocks (not time zones, that is
        # handled by wget) on the clients we make a local stamp
        # file. As this file is not consulted when downloading new
        # snapshot it doesn't matter if a new snapshot is released while 
        # the first one is downloaded. (Yes, this long text is necessary.)
        touch localtime_lastdl
     fi || wget_exit

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
            $basedir/$putname "$puturl" \
                < "$x/xenofarm_result.tar.gz" || tmp="fail"
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
       echo "putversion: `$basedir/$putname --version`" \
                                >> machineid.txt &&
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
        echo " Environment: \"$environment\"."
    fi    
    if [ X"$first_project_run" = Xtrue ] ; then
        prepare_project
    fi
    msg " Running test \"$test\" in $fulldir."

    #Check for earlier results and try to send them
    put_resume

    (   cd "$fulldir"
	if [ -d buildtmp/. ]; then
	  if rm -rf buildtmp 2>/dev/null; then :; else
	    # Possibly locked by .nfs lock files.
	    test -d nfslocks/. || mkdir nfslocks || mkdir_exit
	    find buildtmp -type f -name '.nfs*' -exec mv -f \{\} nfslocks/ \;
	    # Truncate and cleanup the lock files.
	    for f in nfslocks/.nfs*; do
	      >$f
	      rm -f $f 2>&1
	    done
	    rm -rf buildtmp || mkdir_exit
	  fi
	fi
        mkdir buildtmp || mkdir_exit
        cd buildtmp &&
        if [ \! -f "../last_$test" ] ||
           is_newer ../localtime_lastdl "../last_$test" ; then
            get_time
            echo $hour:$minute > "../current_$test";
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
                $basedir/$putname "$puturl" \
                    < "$resultdir/xenofarm_result.tar.gz" || put_exit
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

setup_put() {
    echo $putname
    if [ ! -x $putname ] ; then
        spinlock
        rm -f config.cache
        ./configure
        make clean
        make put
        if [ ! -x put ] ; then
            msg "FATAL: Failed to compile put." >&2
            clean_exit 3
        else
            mkdir bin 2>/dev/null
            mv put $putname
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

#Get user input
parse_args $@

if [ -d "$config_dir/." ]; then :; else
    msg "FATAL: Configuration directory \"$config_dir\" does not exist." >&2
    exit 12
fi

if [ "x$limits" = "xno" ]; then :; else
  #Try to limit the damage if something goes out of hand.
  # NOTE: Limitations are per spawned process. You can still get plenty hurt.
  # TODO: Total time watchdog?
  # TODO: Remote compilation limits?
  ulimit -d 215040 2>/dev/null || # data segment   < 210 MiB
      msg "NOTE: Failed to limit data segment. Might already be lower."
  ulimit -v 215040 2>/dev/null || # virtual memory < 210 MiB
      msg "NOTE: Failed to limit virtual mem. Might already be lower."
  ulimit -t 14400  2>/dev/null || # CPU            < 4h
      msg "NOTE: Failed to limit CPU time. Might already be lower."
fi

get_email

#Make sure the remote nodes are up in a multi machine compilation setup
check_multimachinecompilation

#Check and handle the pidfile for this node
setup_pidfile

#If we are running a sprshd build the put command should be on the local node
if [ X$REMOTE_METHOD = "Xsprsh" ] ; then
    #FIXME: See if this uname location is reasonably portable
    #FIXME: Now that the nodename finder otherwhere is so clever this can fail.
    putname=bin/put-`/bin/uname -n`
else
    putname=bin/put-$node
fi

#Make sure there is a put command available for this node
setup_put

#Make sure wget and gzip exists
wget --help > /dev/null 2>&1 || missing_req wget 10
gzip --help > /dev/null 2>&1 || missing_req wget 11

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
                msg "environment: not supported in config format v2."
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
