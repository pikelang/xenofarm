#!/sw/local/bin/python

import resultparser
import sys
from time import time, strftime, gmtime

recent_builds = """
   SELECT MAX(tr.build), tr.system, MAX(b.time)
     FROM task_result tr, build b
    WHERE tr.build = b.id
 GROUP BY tr.system
"""

resultparser.init(sys.argv[1])

results = resultparser.ResultList(recent_builds, None)
syslist = results.get_system_list()
parser  = results.get_task_parser()
tasks   = parser.get_expected_task_ids()

print """
<html>

<head>
  <title>Python Xenofarm latest results</title>
  <style>
    th { font-family: sans-serif }
    td.build { font-weight: bold }
  </style>
<head>
<body>
  <h1>Python Xenofarm latest results</h1>
  <p>This page collects the latest result for all machines that have ever
     reported a result.  Some of these results may be very old and
     obsolete.</p>

  <p>This information on this page was collected %s</p>

  <h1>Per-machine overview</h1>
  <p>Green dots mean that the step went well. Red dots mean that the
     step failed somehow . White dots mean this script could not parse
     the result or that the step was not executed because some step
     that it depends on failed.</p>
  <p>To the left are summary steps; to the right are breakdowns of the 
     activities involved in building and testing a particular package.</p>
""" % strftime("%Y-%m-%d %H:%M %Z", gmtime())

print "<table>"
print "  <tr>"
print "    <th>System</th>"

for id in tasks:
    print "    <th>%s</th>" % parser.get_task_info(id)[3]
print "  </tr>"

blist = results.get_build_list()
blist.sort(lambda a, b: int(b[0] - a[0]))

for build, time in blist:
    print "  <tr><td colspan='%i' class='build'>Build %s %s</td></tr>" % \
          (len(tasks) + 1, build, strftime("%Y-%m-%d %H:%M", gmtime(time)))
    for res in results.get_results_by_build(build):
        print "  <tr>"
        print "    <td>%s</td>" % syslist.get_identity(res.get_system_id())

        for id in tasks:
            url = "files/%i_%i/" % (build, res.get_system_id())

            try:
                task = res.get_task_by_id(id)
            except KeyError:
                img = "<img border=0 src='pcl-white.gif'>"
            else:
                if task.successful():
                    img = "<img border=0 src='pcl-green.gif'>"
                else:
                    img = "<img border=0 src='pcl-red.gif'>"

            print "    <td align='center'><a href='%s'>%s</a></td>" % (url,img)
        print "  </tr>"
print "</table>"

print """
</body>

</html>
"""
