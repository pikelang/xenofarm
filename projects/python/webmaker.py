import resultparser
from time import time, strftime, gmtime

recent_builds = """
   SELECT MAX(tr.build), tr.system, MAX(b.time)
     FROM task_result tr, build b
    WHERE tr.build = b.id
 GROUP BY tr.system
"""

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
""" % strftime("%Y-%m-%d %H:%M %Z", gmtime())

print "<table>"
print "  <tr>"
print "    <th>System</th>"

for id in tasks:
    print "    <th>%s</th>" % parser.get_task_info(id)[3]
print "  </tr>"

for build in results.get_build_list():
    print "  <tr><td colspan='%i' class='build'>Build %s %s</td></tr>" % \
          (len(tasks) + 1, build, 'foo')
    for res in results.get_results_by_build(build):
        print "  <tr>"
        print "    <td>%s</td>" % syslist.get_identity(res.get_system_id())

        for id in tasks:
            try:
                task = res.get_task_by_id(id)
            except KeyError:
                img = "<img border=0 src='pcl-white.gif'>"
            else:
                if task.successful():
                    img = "<img border=0 src='pcl-green.gif'>"
                else:
                    img = "<img border=0 src='pcl-red.gif'>"

            print "    <td align='center'>%s</td>" % img
        print "  </tr>"
print "</table>"

print """
</body>

</html>
"""
