#!/usr/bin/env python

import os
import time

import MySQLdb

# Configuration: things you must change.

input = "/lysator/www/projects/xenofarm/lyskom-server/files"
output = "/lysator/www/user-pages/ceder/xeno/"
tmp = "/lysator/www/user-pages/ceder/xeno/tmp"

url = "http://www.lysator.liu.se/xenofarm/lyskom-server/files"
buttonurl = "pcl-"

dbname = "lyskom_server_xenofarm"
dbuser = "ceder"
dbhost = "lenin"
dbpwdfile = "/home/ceder/.xeno-mysql-pwd"

projectname = "lyskom-server"

# Configuration: things you may change, but really don't have to.

LATEST_PAGE = """<html>
<head><title>%(project)s: latest Xenofarm results</title></head>
<body>
<a href="index.html">[build overview]</a>
<h1>%(project)s: latest Xenofarm results</h1>
This page collects the latest result for all machines that have ever
reported a result.  Some of these results may be very old and
obsolete.

<p>The information on this page was collected
%(now)s.

<h1>Summary</h1>
<table border=1>
  <tr>
    <th><img border=0 src="%(buttonurl)sgreen.gif"></th>
    <th><img border=0 src="%(buttonurl)syellow.gif"></th>
    <th><img border=0 src="%(buttonurl)sred.gif"></th>
    <th><img border=0 src="%(buttonurl)swhite.gif"></th>
  </tr>
  <tr>
    <td>%(green)s</td>
    <td>%(yellow)s</td>
    <td>%(red)s</td>
    <td>%(white)s</td>
  </tr>
</table>

<h1>Per-machine overview</h1>

<table border=1>
  %(heading)s
  %(content)s
</table>

</body>
</html>
"""

# End of configuration.

_DB = None

def init():
    global _DB
    pwd = open(dbpwdfile, "r").readline()
    if pwd[-1] == "\n":
        pwd = pwd[:-1]
    _DB = MySQLdb.connect(db=dbname, user=dbuser, host=dbhost, passwd=pwd)


def get_all_systems():
    cursor = _DB.cursor()
    cursor.execute("select -max(build.id),"
                   "     concat(system.sysname, ' ', system.machine),"
                   "     system.release,"
                   "     system.testname,"
                   "     system.name,"
                   "     system.id,"
                   "     max(build.time)"
                   " from system, build, task_result"
                   " where task_result.system = system.id"
                   " and task_result.build = build.id"
                   " group by system.id")
    rows = cursor.fetchall()
    cursor.close()
    rows = list(rows)
    rows.sort()
    return rows

def get_all_tasks():
    cursor = _DB.cursor()
    cursor.execute("select distinct task_result.task, task.name"
                   " from system, build, task_result, task"
                   " where task_result.system = system.id"
                   " and task_result.build = build.id"
                   " and task_result.task = task.id"
                   " order by task.sort_order")
    rows = cursor.fetchall()
    cursor.close()
    return rows

def latest_heading_row(tasks):
    res = ["  <tr>",
           "    <th>Machine</th>"]
    for (taskid, taskname) in tasks:
        res.append("    <th>%s</th>" % taskname)
    res.append("    <th>Total</th>")
    res.append("    <th>Hostname</th>")
    res.append("  </tr>")
    return "\n".join(res)


def content(systems, tasks):
    ctr = {
        'green': 0,
        'yellow': 0,
        'red': 0,
        'white': 0,
        }
    lastbuild = None
    lastplat = None
    res = []
    for (negbuildid, platform, plat_release, testname, systemname, systemid,
         buildtime) in systems:
        if lastbuild != negbuildid:
            pretty = time.strftime("%Y-%m-%d&nbsp;%H:%M:%S",
                                   time.localtime(buildtime))
            age = "%.2f" % ((time.time() - buildtime) / (24*3600))
            res.append('  <tr><td colspan="%d"><a href="%s.html">'
                       '<br>Build %s (%s days ago)'
                       ' %s<br></a>&nbsp;</td></tr>' % (
                           3 + len(tasks), -negbuildid, -negbuildid,
                           age, pretty))
            lastbuild = negbuildid
            lastplat = platform
        if lastplat != platform:
            res.append("<tr><td colspan=%d bgcolor=black></td></tr>" % (
                3 + len(tasks)))
            lastplat = platform
        row, row_status = content_row(-negbuildid, systemid, systemname,
                                      platform, plat_release, testname, tasks)
        res.append(row)
        ctr[row_status] += 1
    return '\n'.join(res), ctr

def content_row(buildid, systemid, systemname, platform, plat_release,
                testname, tasks):
    res = []
    res.append("  <tr>")
    res.append('    <td><a href="%s/%s_%s/">%s</a></td>' % (
        url, buildid, systemid,
        platform + " " + plat_release + " " + testname))

    row_status = "white"

    cursor = _DB.cursor()
    cursor.execute("select task, status, warnings"
                   " from task_result"
                   " where build = %s and system = %s and task in (%s)" % ( 
                       buildid, systemid, ', '.join(
                           ["%s" % task for (task, name) in tasks])))
    m = {}
    for (task, status, warnings) in cursor.fetchall():
        m[task] = (status, warnings)
    cursor.close()

    for (task, taskname) in tasks:
        logtypes = ["log"]
        if not m.has_key(task):
            color = "white"
        else:
            (status, warnings) = m[task]
            if status == "FAIL":
                color = "red"
                logtypes.insert(0, "warn")
                logtypes.insert(0, "fail")
                row_status = "red"
            elif status == "WARN":
                color = "yellow"
                logtypes.insert(0, "warn")
                if row_status == "green" or row_status == "white":
                    row_status = "yellow"
            elif status == "PASS":
                color = "green"
                if row_status == "white":
                    row_status = "green"

        astart = ""
        aend = ""
        for link in logtypes:
            if os.path.exists(os.path.join(input,
                                           "%s_%s" % (buildid, systemid),
                                           taskname + link + ".txt")):
                astart = '<a href="%s/%s_%s/%s%s.txt">' % (
                    url, buildid, systemid, taskname, link)
                aend = '</a>'
                break
        if astart != "" or color != "white":
            res.append('    <th>%s<img border=0 src="%s%s.gif">%s</th>' % (
                astart, buttonurl, color, aend))
        else:
            res.append('    <th>&nbsp;</th>')

    res.append('    <th><img border=0 src="%s%s.gif"></th>' % (
        buttonurl, row_status))
    
    res.append('    <td><a href="%s/%s_%s/">%s</a></td>' % (
        url, buildid, systemid, systemname))
    res.append("  </tr>")
    return '\n'.join(res), row_status

init()

systems = get_all_systems()
tasks = get_all_tasks()

(tbl, m) = content(systems, tasks)

m["project"] = projectname
m["now"] = time.strftime("%Y-%m-%d&nbsp;%H:%M:%S", time.localtime())
m["buttonurl"] = buttonurl
m["heading"] = latest_heading_row(tasks)
m["content"] = tbl

open(os.path.join(output, "latest.html"), "w").write(LATEST_PAGE % m)
