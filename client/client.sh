#!/bin/sh

##############################################
# Xenofarm client
#
# Written by Peter Bortas, Copyright 2002
# $Id: client.sh,v 1.28 2002/08/28 22:52:26 zino Exp $
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
# `uname -n`        should print the nodename
# `uname -s -r -m`  should print OS and CPU info
# `kill -0 <pid>`   should return true if a process with that pid exists
# `LC_ALL="C" date` should return a space-separated string with where the
#                   first substring containing colons is on the form
#                   <hour>:<minute>.*
# tar 	            must be available in the PATH
##############################################
# NOTE: The following changes will be committed when Pikefarm officially
# moves to pike.ida.liu.se.
#  - The export stamp will be renamed from export.stamp to buildid.txt
#  - The xenofarm client log, which will be submitted in case of complete
#    failure of a build, will be renamed from RESULT to xenofarmclient.txt
# NOTE: This is now in effect
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
#
# 10: wget not found
# 11: gzip not found
#
# 13-25: Reserved for internal usage.

#FIXME: Error codes are often caught in subshells
#FIXME: use logger to put stuff in the syslog if available

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
	echo \$Id: client.sh,v 1.28 2002/08/28 22:52:26 zino Exp $
	exit 0
  ;;
  *)
	echo Unsupported argument: $1 1>&2
	echo try --help 1>&2
	exit 1
  esac
 done
}

get_time() {
    hour=`LC_ALL="C" date | awk -F: '{ print $1 }' | awk '{ i=NF; print $i }'`
    minute=`LC_ALL="C" date | awk -F: '{ print $2 }' | awk '{ print $1 }'`
}

check_delay() {
    #FIXME: This is a total mess, and unfinished at that. Redo from start.
#     if [ -f "../last_$target" ] && [ $delay -ne 0 ] ; then
#         get_time
#         old_hour=`awk -F: '{ print $1 }' < "../last_$target"`
#         old_minute=`awk -F: '{ print $2 }' < "../last_$target"`
#         delay_hour=`echo $delay | awk -F: '{ print $1 }'"`
#         delay_minute=`echo $delay | awk -F: '{ print $2 }'"`
#         if [ $hour -gt $old_hour ]; then  #Pre midnight
#             if [ `echo $hour - $old_hour | bc` -gt $delay_hour ] ; then
#                 true
#             else if [ `echo $hour - $old_hour | bc` -eq $delay_hour ] ; then
#                 if [ `echo $minute - $old_minute | bc` -gt $delay_minute ];then
#                     true
#                 fi
#             else
#                 false
#             fi
#         else if [ $hour -eq $old_hour ]; then  # Might be other day
#             if [ $minute -gt $old_minute ] &&  # It wasn't
#                [ `echo $minute - $old_minute | bc` -gt $delay_minute ] &&
#                [ $delay_hour -eq 0 ] ; then
#                 true
#             else if [ $minute -lt $old_minute ]
#                 false
#             fi
#         fi
#     else
#         echo "'NOTE: ../last_$target' does not exists."
#         true
#     fi
    #FIXME: Just build always for now...
    true
}

#Make directories recursively
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

clean_exit() {
    rm -f $pidfile
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
    cat "wget_$target.log" 1>&2
    clean_exit 5 
}

mkdir_exit() {
    echo "Project FATAL: Uunable to create a fresh build directory. Skipping to the next project." 1>&2
    exit 14
}

is_newer() {
    test "X`\ls -t \"$1\" \"$2\" | head -1`" = X"$1"
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
machineid=`uname -s -r -m`
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

#Make sure there is a put command available for this node
if [ ! -x $putname ] ; then
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
fi

#Make sure wget and gzip exists
wget --help > /dev/null 2>&1 || missing_req wget 10
gzip --help > /dev/null 2>&1 || missing_req wget 11

#Read only the node specific configuration file if it exists.
#FIXME: Functionalize and use below
if [ -f "projects.conf.$node" ] ; then
    configfile="projects.conf.$node";
    echo "NOTE: found node specific config file: $configfile"
else
    configfile="projects.conf";
    if [ ! -f $configfile ] ; then
	missing_req $configfile 13
    fi
fi

#Called to prepare the project build enviroment. Not reapeated for each id.
prepare_project() {
    echo "First test in this project. Preparing build enviroment."
    dir="$dir/$node/"
    if [ ! -d "$dir" ]; then
        pmkdir "$dir"
    fi  

    cd "$dir" &&
     NEWCHECK="`ls -l snapshot.tar.gz 2>/dev/null`";
     #FIXME: get a tee >1 in here for better manual runs
     wget --dot-style=binary -N "$geturl" > "wget.log" 2>&1 &&
     if [ X"`ls -l snapshot.tar.gz`" = X"$NEWCHECK" ]; then
        echo "NOTE: No newer snapshot for $project available."
     else
        # The snapshot will have a time stamp synced to the server. To
        # compensate for drifting clocks (not time zones, that is
        # handled by wget) on the clients we make a local stamp
        # file. As this file is not consulted when downloading new
        # snapshot it doesn't matter if a new snapshot is released while 
        # the first one is downloaded. (Yes, this long text is necessary.)
        touch localtime_lastdl
     fi || wget_exit

     echo "Uncompressing archive..." &&
     rm -f snapshot.tar &&
     test -f snapshot.tar.gz &&
     #FIXME: Well, we could avoid doing this every time the client is started. Normally doesn't matter though.
     #FIXME: This will not fail on full disk
     gzip -cd snapshot.tar.gz > snapshot.tar &&
     echo "done" || exit 17
    cd ../..
}

#Run _one_ test
run_test() {
    echo "Building project $project from $geturl."
    if [ X"$virgin" = Xtrue ] ; then
        prepare_project
    fi
    echo "Running test $id in $dir with test command: $command"    

    (   cd "$dir"
        pwd
        rm -rf buildtmp && mkdir buildtmp || mkdir_exit
        cd buildtmp &&
        if [ \! -f "../last_$id" ] ||
           is_newer ../localtime_lastdl "../last_$id" ; then
        get_time
        echo $hour:$minute > "../current_$id";
        #FIXME: Check if the project configurable build delay has passed
        if `check_delay`; then
            echo "Extracting archive..." &&
	    test -f ../snapshot.tar &&
            tar xf ../snapshot.tar &&
            echo "done" || exit 4

            cd */.
            resultdir="../../result_$id"
            rm -rf "$resultdir" && mkdir "$resultdir" &&
            #FIXME: export.stamp -> buildid.txt
            cp export.stamp "$resultdir" &&
            echo "Building and running test $id: $command" &&
            echo "id: $id" > "$resultdir/xenofarmclient.txt" &&
            echo "command: $command" >> "$resultdir/xenofarmclient.txt" &&
            echo "version: `$basedir/client.sh --version`" >> "$resultdir/xenofarmclient.txt" &&
            echo "putversion: `$basedir/$putname --version`" >> "$resultdir/xenofarmclient.txt" &&
            echo "test output follows:" >>  "$resultdir/xenofarmclient.txt" &&
            $command >"$resultdir/xenofarmclient.txt" 2>&1;
            if [ -f xenofarm_result.tar.gz ] ; then
                mv xenofarm_result.tar.gz "$resultdir"
                (cd "$resultdir" &&
                 rm -rf repack &&
                 mkdir repack &&
                 cd repack &&
                 gzip -cd $resultdir/xenofarm_result.tar.gz | tar xf - &&
                 cp $resultdir/xenofarmclient.txt . &&
                 tar cf - * | gzip -c > $resultdir/xenofarm_result.tar.gz)
            else
                (cd "$resultdir" &&
                echo $machineid > machineid.txt &&
                echo $node >> machineid.txt &&
                tar cvf xenofarm_result.tar xenofarmclient.txt buildid.txt machineid.txt &&
                gzip xenofarm_result.tar)
            fi
	    mv "../../current_$id" "../../last_$id";
	    echo "Sending results for $project: $id."
            #FIXME: Store failed result sendings and restry every client run.
            #       possible date string: date | sed 's/ //g' | sed 's/://g'
            $basedir/$putname "$puturl" < "$resultdir/xenofarm_result.tar.gz" ||
            echo "OBSERVE: Failed to send result package to $puturl. Result will be lost. Skipping to the next project." 1>&2 && exit 8
            cd ..
        else
            echo "NOTE: Build delay for $project not passed. Skipping."
        fi
        else
            echo "NOTE: Already built $project: $id. Skipping."
        fi
    )
    last=$?
    if [ X"$last" != X0 ] ; then
        echo "Project $project failed with exit code $last" 1>&2
    fi
}

#Remove spaces in the beginning and end of a string.
chomp_ends() {
    echo $1 | sed 's/^[ ]*//' | sed 's/[ ]*$//'
}

#Build Each project and each target in that project sequentially
basedir="`pwd`"
for projectconfig in config/*.cfg; do (

    configformat=""
    testnames=""
    testcmds=""
    virgin="true"
    cat $projectconfig | while read line; do
        type=`echo $line | awk -F: '{ print $1 }'`
        arguments=`echo $line | sed 's/[^:]*//' | sed 's/://'`
#        echo $arguments
        arguments=`chomp_ends "$arguments"`
        case $type in
        configformat)
            if [ X"$arguments" != X2 ] ; then
                echo "Unknown configformat $arguments in $projectconfig"
                exit 15
            fi
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
            #FIXME: Check that necessary variables are set
            id=`echo $arguments | awk '{ print $1 }'`
            command=`echo $arguments | sed 's/[^ ]* //'`
            command=`chomp_ends "$command"`
            echo Running id: $id, Command: $command
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
) done

clean_exit $?


#              if [ ! x$uncompressed = x1 ] ; then
#                echo "FATAL: Unable to decompress $project snapshot!" 1>&2
#                #Will drop from the the second subshell to the while shell
#                exit 4
#              fi
