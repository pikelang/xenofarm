import resultparser
from time import time
from string import join

recent_time = time() - 24 * 60 * 60 * 2
recent_builds = """
   SELECT DISTINCT tr.build, tr.system, b.time
     FROM task_result tr LEFT JOIN build b ON tr.build = b.id
    WHERE time >= %i
""" % recent_time

results = resultparser.ResultList(recent_builds, None)
syslist = results.get_system_list()

# List participating builders
print "Participating systems:"
for system in syslist.get_list():
    print "  %s [%s %s] [%s %s]" % (system[0], system[1], system[2],
                                    system[4], system[5])
print

# First, print all unsuccessful builds
print "Failed builds:"

for res in results.get_failed():
    text = join(map(lambda x: x.get_full_name(),
                    res.get_failed_tasks()),
                ",")
    print "  [%i] %s: %s" % (res.get_build_id(),
                             syslist.get_identity(res.get_system_id()),
                             text)
print

# Then, print all successful builds
print "Successful builds:"
for res in results.get_successful():
    print "  [%i] %s: %s" % (res.get_build_id(),
                             syslist.get_identity(res.get_system_id()),
                             "success")
