#!/sw/local/bin/python
import resultparser
import sys

from time import time
from string import join
from time import strftime, gmtime

recent_time = time() - 24 * 60 * 60 * 2
recent_builds = """
   SELECT DISTINCT tr.build, tr.system, b.time
     FROM task_result tr LEFT JOIN build b ON tr.build = b.id
    WHERE time >= %i
""" % recent_time

resultparser.init(sys.argv[1])

results = resultparser.ResultList(recent_builds, None)
syslist = results.get_system_list()

# List builds that got tried during period
builds = results.get_build_list()
builds.sort(lambda a, b: int(b[0] - a[0]))

print "Tried builds:"
for build, time in builds:
    print "  [%4i] %s" % (build, strftime("%Y-%m-%d %H:%M", gmtime(time)))
print

# List participating builders
def sort_systems(a, b):
    if a[0] > b[0]:
        return 1
    else:
        if a[0] < b[0]:
            return -1
        else:
            return 0

systems = syslist.get_list()
systems.sort(sort_systems)

print "Participating systems:"
for system in systems:
    print "  %-25s [%s %s %s %s]" % (system[0], system[1], system[2],
                                    system[4], system[5])
print

# First, print all unsuccessful builds
failed = results.get_failed()
failed.sort(lambda a, b: int(b.get_build_id() - a.get_build_id()))

print "Failed builds:"
for res in failed:
    text = join(map(lambda x: x.get_full_name(),
                    res.get_failed_tasks()),
                ",")
    print "  [%4i] %-32s %s" % (res.get_build_id(),
                                  syslist.get_identity(res.get_system_id()),
                                  text)
print

# Then, print all successful builds
print "Successful builds:"
for res in results.get_successful():
    print "  [%i] %s: %s" % (res.get_build_id(),
                             syslist.get_identity(res.get_system_id()),
                             "success")
print
print "For the latest builds, see:"
print "  http://www.lysator.liu.se/xenofarm"
