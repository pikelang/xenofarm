#!/bin/sh

##############################################
# Xenofarm client
#
# Written by Peter Bortas, Copyright 2002
# $Id: client.sh,v 1.39 2002/09/02 11:39:47 zino Exp $
# License: GPL
#
# Requirements:
#  gzip
#  wget              Must handle -N and set the timestamp correctly.
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
##############################################
# See `client.sh --help` for command line options.
#
# Error codes:
#  0: Exited without errors or was stopped by a signal
#  1: Unsupported argument
#  2: Client already running
#  3: Failed to compile put
#  4: Unable to decompress project snapshot
#  5: Failed to fetch project snapshot
#  6: Recursive mkdir failed
#  7: Remote compilation failure
#  8: Failed to send result  (not propagated)
#  9: Admin email not configured
#
# 10: wget not found
# 11: gzip not found
#
# 13-25: Reserved for internal usage.

#FIXME: Sort out what error codes should be exported from the client.

parse_args() {
 while [ ! c"$1" = "c" ] ; do
  case "$1" in
  '-h'|'--help')
  	sed -e "s/\\.B/`tput 'bold' 2>/dev/null`/g" -e "s/B\\./`tput 'sgr0' 2>/dev/null`/g" << EOF
.BXenofarm clientB.

Start it with cron or with the "start"-script.

If you encounter problems see the .BREADMEB. for requirements and help.

   .BArguments:B.

      .B--helpB.:                  This information.
      .B--versionB.:               Displays client version.
EOF
    	tput 'rmso' 2>/dev/null
	exit 0
  ;;
  '-v'|'--version')
	echo \$Id: client.sh,v 1.39 2002/09/02 11:39:47 zino Exp $
	exit 0
  ;;
  *)
	echo "Unsupported argument: $1" 1>&2
	echo "try --help" 1>&2
	exit 1
  esac
 done
}

get_time() {
    hour=`LC_ALL="C" date | awk -F: '{ print $1 }' | awk '{ i=NF; print $i }'`
    minute=`LC_ALL="C" date | awk -F: '{ print $2 }' | awk '{ print $1 }'`
}

check_delay() {
    #FIXME: Just build always for now...
    true
}

#Make directories recursively.
pmkdir() {
    while [ ! -d $1 ]; do 
	rest=$1
	while [ ! -d $rest ]; do
	    tmp_dir=`basename $rest`
	    rest=`dirname $rest`
	done
	mkdir $rest/$tmp_dir || clean_exit 6
    done
}

#FIXME: Code duplication
nfpmkdir() {
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
    echo "SIGINT received. Cleaning up and exiting." 1>&2
    clean_exit 0
}
sighup() {
    echo "SIGHUP received. Cleaning up and exiting for now." 1>&2
    clean_exit 0
}

missing_req() {
    echo "FATAL: $1 not found." 1>&2
    clean_exit $2
}

wget_exit() {
    cat "wget.log" 1>&2
    clean_exit 5 
}

mkdir_exit() {
    echo "Project FATAL: Uunable to create a fresh build directory. Skipping to the next project." 1>&2
    exit 14
}

is_newer() {
    test "X`\ls -t \"$1\" \"$2\" | head -1`" = X"$1"
}

get_email() {
    while [ X$happy != X"yes" ] ; do
        if [ \! -f config/contact.txt ] ; then
        
            echo "Please type in an email address where the project maintainer can reach you:"
            if read email
	    then :
	    else
		echo EOF while reading email address >&2
		exit 9
	    fi
            if [ X"$email" != X ] ; then
                echo "contact: $email" > config/contact.txt
                happy="yes"
            fi
        else
            happy="yes"
        fi
    done
}

#Execution begins here.

#Set up signal handlers
trap sighup 1
trap sigint 2
trap sigint 15

#Add a few directories to the PATH
PATH=$PATH:/usr/local/bin:/sw/local/bin
#cc on UNICOS fails to build with exotic settings like LC_CTYPE=iso_8859_1
LC_ALL=C
export PATH LC_ALL

#Get user input
parse_args $@

#FIXME: Figure out what to do if we don't have an interactive shell here
get_email

#Make sure the remote nodes are up in a multi machine compilation setup
if [ X$REMOTE_METHOD = "Xsprsh" ] ; then
    if [ X"`uname -m 2>/dev/null`" = X ] ; then
        echo "FATAL: Unable to contact remote system using $REMOTE_METHOD."
        exit 7
    else if [ X"`uname -s`" = X ] ; then
        echo "FATAL: Possible permission problem or unmounted volume on remote system."
        exit 7
    fi ; fi
fi

#Check and handle the pidfile for this node
node=`uname -n`
unames=`uname -s`
unamer=`uname -r`
unamem=`uname -m`
unamev=`uname -v`
pidfile="`pwd`/xenofarm-$node.pid"
if [ -r $pidfile ]; then
    pid=`cat $pidfile`
    if `kill -0 $pid > /dev/null 2>&1`; then
        echo "NOTE: Xenofarm client already running. pid: $pid"
        exit 2
    else
        echo "NOTE: Removing stale pid-file."
        rm -f $pidfile
    fi
fi

echo $$ > $pidfile

#If we are running a sprshd build the put command should be on the local node
if [ X$REMOTE_METHOD = "Xsprsh" ] ; then
    #FIXME: See if this uname location is reasonable portable
    putname=bin/put-`/bin/uname -n`
else
    putname=bin/put-$node
fi

#Make sure we don't compile the put command on more than one node at the time
#NOTE: This can deadlock if the client is killed without giving it a
#      chance to clean up during the put compilation.
spinlock() {
    while [ X$gotlock != X"true" ] ; do
        if [ \! -f lock.tmp ] ; then
            echo `uname -n` > lock.tmp
            holder=`cat lock.tmp`
            if [ X$holder = X`uname -n` ] ; then
                echo "Got compilation lock."
                gotlock="true"
            fi
        else 
            echo "Waiting for `cat lock.tmp` to release compilation lock."
            sleep 60
        fi
    done
}

releaselock() {
    rm lock.tmp
    gotlock="false"
}

#Make sure there is a put command available for this node
if [ ! -x $putname ] ; then
    spinlock
    rm -f config.cache
    ./configure
    make clean
    make put
    if [ ! -x put ] ; then
        echo "FATAL: Failed to compile put." 1>&2
        clean_exit 3
    else
	mkdir bin 2>/dev/null
	mv put $putname
    fi
    rm lock.tmp
fi

#Make sure wget and gzip exists
wget --help > /dev/null 2>&1 || missing_req wget 10
gzip --help > /dev/null 2>&1 || missing_req wget 11

#Called to prepare the project build enviroment. Not reapeated for each id.
prepare_project() {
    echo " First test in this project. Preparing build enviroment."
    dir="$dir/$node/"
    if [ ! -d "$dir" ]; then
        pmkdir "$dir"
    fi  

    cd "$dir" &&
     NEWCHECK="`ls -l snapshot.tar.gz 2>/dev/null`";
     echo " Downloading $project snapshot..."
     #FIXME: Check for old broken wgets.
     wget --dot-style=binary -N "$geturl" > "wget.log" 2>&1 &&
     if [ X"`ls -l snapshot.tar.gz`" = X"$NEWCHECK" ]; then
        echo " NOTE: No newer snapshot for $project available."
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
    echo "Failed to uncompress snapshot. Removing possibly damaged file."
    rm -f $1
    exit 17
}

put_exit() {
    echo "Failed to send result. Will try to resend in the next client run."
    date=`date | sed 's/ //g' | sed 's/://g'` &&
    (nfpmkdir "$basedir/$dir/rescue_$test/$date") &&
    mv "$resultdir/xenofarm_result.tar.gz" \
       "$basedir/$dir/rescue_$test/$date/xenofarm_result.tar.gz"
    exit 8
}

put_resume() {
    cd "$basedir/$dir"
    ls rescue_$test/* >/dev/null 2>&1 &&
    for x in rescue_$test/*; do
        tmp=""
        if [ -f $x/xenofarm_result.tar.gz ] ; then
            echo "Resending $x/xenofarm_result.tar.gz."
            $basedir/$putname "$puturl" \
                < "$x/xenofarm_result.tar.gz" || tmp="fail"
            if [ X$tmp != Xfail ] ; then
                rm $x/xenofarm_result.tar.gz
                rmdir $x
            else
                echo "Failed to resend. Will try to resend in the next client run."
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
       cat "$basedir/config/contact.txt" >> machineid.txt
}

#Run _one_ test
run_test() {
    echo "Building project \"$project\" from $geturl."
    if [ X"$virgin" = Xtrue ] ; then
        prepare_project
    fi
    echo " Running test \"$test\" in $dir."
    
    #Check for earlier results and try to send them
    put_resume

    (   cd "$basedir/$dir"
        rm -rf buildtmp && mkdir buildtmp || mkdir_exit
        cd buildtmp &&
        if [ \! -f "../last_$test" ] ||
           is_newer ../localtime_lastdl "../last_$test" ; then
            get_time
            echo $hour:$minute > "../current_$test";
            #FIXME: Check if the project configurable build delay has passed
            if `check_delay`; then
                if [ $uncompressed != "true" ] ; then
                    echo " Uncompressing archive..." &&
                    rm -f "$basedir/$dir/snapshot.tar" &&
                    test -f "$basedir/$dir/snapshot.tar.gz" &&
                    #This will not fail on full disk, but the tar should
                    gzip -cd "$basedir/$dir/snapshot.tar.gz" \
                        > "$basedir/$dir/snapshot.tar" || 
                            uncompress_exit "$basedir/$dir/snapshot.tar.gz"
                    uncompressed="true"
                fi
                echo "  Extracting archive..." &&
                test -f ../snapshot.tar &&
                tar xf ../snapshot.tar || exit 4

                cd */.
                echo "  Building and running test \"$test\": \"$command\""
                resultdir="../../result_$test"
                rm -rf "$resultdir" && mkdir "$resultdir" || exit 19

                cp buildid.txt "$resultdir" || exit 20
                $command >"$resultdir/xenofarmclient.txt" 2>&1;
                #FIXME: Full disk inside this if will be bad
                if [ -f xenofarm_result.tar.gz ] ; then
                    mv xenofarm_result.tar.gz "$resultdir"
                    (
                     cd "$resultdir" &&
                     make_machineid &&
                     rm -rf repack &&
                     mkdir repack &&
                     cd repack &&
                     gzip -cd $resultdir/xenofarm_result.tar.gz | tar xf - &&
                     cp $resultdir/machineid.txt . &&
                     tar cf - * | gzip -c > $resultdir/xenofarm_result.tar.gz
                    )
                else
                    (
                     cd "$resultdir" &&
                     make_machineid &&
                     tar cvf xenofarm_result.tar xenofarmclient.txt \
                        buildid.txt machineid.txt &&
                     gzip xenofarm_result.tar
                    )
                fi
                mv "../../current_$test" "../../last_$test";
                echo "  Sending results for \"$project\": \"$test\"."
                $basedir/$putname "$puturl" \
                    < "$resultdir/xenofarm_result.tar.gz" || put_exit
                cd "$dir/buildtmp"
            else
                echo " NOTE: Build delay for \"$project\" not passed. Skipping."
            fi
        else
            echo "  NOTE: Already built \"$project\": \"$test\". Skipping."
        fi
    )
    last=$?
    if [ X"$last" != X0 ] ; then
        echo "Project \"$project\" failed with exit code $last" 1>&2
        case $last in
        '4')
            echo "FATAL: Unable to extract \"$project\" snapshot!" 1>&2
            ;;
        '8')
            echo "FATAL: Failed to send result package to $puturl." 1>&2
            ;;
        '20')
            echo "FATAL: Failed to find buildid.txt in snapshot!" 1>&2
            ;;
        esac
    fi
}

#Remove spaces in the beginning and end of a string.
chomp_ends() {
    echo $1 | sed 's/^[ ]*//' | sed 's/[ ]*$//'
}

#Read only the node specific configuration file if it exists.
#FIXME: This requires a base config file.
get_nodeconfig() {
    if [ -f "$projectconfig.$node" ] ; then
        projectconfig="$projectconfig.$node";
        echo "NOTE: Found node config file: $projectconfig.$node"
    fi
}

#Build Each project and each test in that project sequentially
basedir="`pwd`"
for projectconfig in config/*.cfg; do 
(
    #FIXME: Signals needs to be caught in subshells and propagated via 
    #       exit codes
    configformat="" ; testnames="" ; testcmds=""
    virgin="true"
    uncompressed="false"
    get_nodeconfig

    cat $projectconfig | while read line; do
        type=`echo $line | awk -F: '{ print $1 }'`
        arguments=`echo $line | sed 's/[^:]*//' | sed 's/://'`
        arguments=`chomp_ends "$arguments"`
        case $type in
        configformat)
            if [ X"$arguments" != X2 ] ; then
                echo "Unknown configformat $arguments in $projectconfig"
                exit 15
            fi
            configformat="$arguments"
            ;;
        project)
            project=$arguments  ;;
        projectdir)
            dir=$arguments      ;;
        snapshoturl)
            geturl=$arguments   ;;
        resulturl)
            puturl=$arguments   ;;
        mindelay)
            delay=$arguments    ;;
        test)
            if [ X"$configformat" = X ] || [ X"$project" = X ] || 
               [ X"$dir" = X ] || [ X"$geturl" = X ] || 
               [ X"$puturl" = X ] ; then
                echo "FATAL: Missing options in $projectconfig."
                exit 18
            fi

            test=`echo $arguments | awk '{ print $1 }'`
            command=`echo $arguments | sed 's/[^ ]* //'`
            command=`chomp_ends "$command"`
            run_test
            virgin="false"
            ;;
        "")
            :
            ;;
        *)
            echo "Unknown parameter \"$line\" in $projectfile." 1>&2
            exit 16
        esac
    done
    #On to the next project
    configformat="" ; project="" ; dir=""
    geturl=""       ; puturl=""  ; delay=""
)
done

echo "All projects built. Exiting."

clean_exit $?
