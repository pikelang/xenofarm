#!/usr/bin/env python

import os
import stat
import time

import MySQLdb

# Configuration: things you must change.

input = "/lysator/www/projects/xenofarm/lyskom-server/files"
output = "/lysator/www/user-pages/ceder/xeno/"
tmp = "/lysator/www/user-pages/ceder/xeno/tmp"

url = "http://www.lysator.liu.se/xenofarm/lyskom-server/files"
buttonurl = "pcl-"
fullbuttonurl = "http://www.lysator.liu.se/~ceder/xeno/" + buttonurl

dbname = "lyskom_server_xenofarm"
dbuser = "ceder"
dbhost = "lenin"
dbpwdfile = "/home/ceder/.xeno-mysql-pwd"

projectname = "lyskom-server"

files_per_task = {
    'cfg': ['configlog.txt', 'iscconfiglog.txt', 'configcache.txt',
            'config-h.txt'],
    'ckprg': ['lyskomd.log.txt', 'l2g.log.txt', 'leaks.log.txt'],
    'install': ['installedfiles.txt'],
    'id_tx': ['makeinfo.txt'],
    }

hidden_files = [
    'index.html',
    'buildid.txt',
    ]
            

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
    <th><img border=0 src="%(buttonurl)sgreen.gif"><br>(OK)</th>
    <th><img border=0 src="%(buttonurl)syellow.gif"><br>(Warning)</th>
    <th><img border=0 src="%(buttonurl)sred.gif"><br>(Failure)</th>
    <th><img border=0 src="%(buttonurl)swhite.gif"><br>(not tested)</th>
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

RESULT_PAGE = """<html>
<head>
  <title>
    %(project)s: Xenofarm build %(buildid)s %(hostname)s %(testname)s
  </title>
</head>
<body>

<a href="index.html">[build overview]</a>
<h1>%(project)s: Xenofarm build %(buildid)s %(hostname)s %(testname)s</h1>

<p>

<table border=0>
  <tr>
    <td>
      <table border=1>
        <tr>
          <td>Host:</td>
          <td>%(hostname)s</td>
        </tr>
        <tr>
          <td>OS &amp; hardware:</td>
          <td>%(os_hw)s %(os_rel)s</td>
        </tr>
        <tr>
          <td>Build ID:</td>
          <td>%(buildid)d</td>
        </tr>
        <tr>
          <td>Test name:</td>
          <td>%(testname)s</td>
        </tr>
      </table>
    </td>
    <td>
      <table border=1>
        <tr>
          <th><img border=0 src="%(buttonurl)sgreen.gif"><br>(OK)</th>
          <th><img border=0 src="%(buttonurl)syellow.gif"><br>(Warning)</th>
          <th><img border=0 src="%(buttonurl)sred.gif"><br>(Failure)</th>
        </tr>
        <tr>
          <td>%(green)s</td>
          <td>%(yellow)s</td>
          <td>%(red)s</td>
        </tr>
      </table>
    </td>
  </tr>
</table>

%(notdone)s
%(tasklist)s

<h1>Other files</h1>
<pre>
%(otherfiles)s
</pre>

<p>Page updated: %(now)s.

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

def get_all_tasks(builds):
    cursor = _DB.cursor()
    cursor.execute("select distinct task_result.task, task.name"
                   " from system, build, task_result, task"
                   " where task_result.system = system.id"
                   " and task_result.build = build.id"
                   " and task_result.task = task.id"
                   " and build.id in (%s)"
                   " order by task.sort_order" % (
                       ", ".join(["%d" % x for x in builds])))
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


def latest_content(systems, tasks):
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
            res.append("<tr><td colspan=%d bgcolor=grey></td></tr>" % (
                3 + len(tasks)))
            lastplat = platform
        row, row_status = latest_content_row(-negbuildid, systemid, systemname,
                                             platform, plat_release, testname,
                                             tasks)
        res.append(row)
        ctr[row_status] += 1
    return '\n'.join(res), ctr

def latest_content_row(buildid, systemid, systemname, platform, plat_release,
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

def update_latest():
    systems = get_all_systems()
    tasks = get_all_tasks([-negbuildid for (negbuildid, platform, plat_release,
                                            testname, systemname, systemid,
                                            buildtime) in systems])

    (tbl, m) = latest_content(systems, tasks)

    m["project"] = projectname
    m["now"] = time.strftime("%Y-%m-%d&nbsp;%H:%M:%S", time.localtime())
    m["buttonurl"] = buttonurl
    m["heading"] = latest_heading_row(tasks)
    m["content"] = tbl

    open(os.path.join(output, "latest.html"), "w").write(LATEST_PAGE % m)

class task_result:
    def __init__(self, name, status, warnings, time_spent):
        self.name = name
        self.status = status
        self.warnings = warnings
        self.time_spent = time_spent

    def color(self):
        if self.status == "PASS":
            return "green"
        if self.status == "WARN":
            return "yellow"
        if self.status == "FAIL":
            return "red"


def get_task_results(buildid, systemid):
    cursor = _DB.cursor()
    cursor.execute("select t.name, r.status, r.warnings, r.time_spent"
                   " from task_result r, task t"
                   " where r.task = t.id and"
                   "    r.build = %d and r.system = %d"
                   " order by t.sort_order" % (
                       buildid, systemid))
    rows = cursor.fetchall()
    cursor.close()
    return [task_result(*i) for i in list(rows)]

def get_all_task_names():
    cursor = _DB.cursor()
    cursor.execute("select distinct name"
                   " from task"
                   " order by sort_order")
    rows = cursor.fetchall()
    cursor.close()
    return rows

class system:
    def __init__(self, os_hw, os_rel, testname, hostname):
        self.os_hw = os_hw
        self.os_rel = os_rel
        self.testname = testname
        self.hostname = hostname
        

def get_system(systemid):
    cursor = _DB.cursor()
    cursor.execute("select"
                   "     concat(system.sysname, ' ', system.machine),"
                   "     system.release,"
                   "     system.testname,"
                   "     system.name"
                   " from system"
                   " where system.id = %d" % systemid)
    rows = cursor.fetchall()
    cursor.close()
    return system(*rows[0])

def add_file(tl, files_left, dirname, fn, maxlen):
    if files_left.has_key(fn):
        tl.append(file_listing(dirname, fn, maxlen))
        del files_left[fn]

def mkindex(buildid, systemid, force = 0):

    dirname = os.path.join(input, "%d_%d" % (buildid, systemid))
    indexname = os.path.join(dirname, "index.html")
    if os.path.isfile(indexname) and not force:
        return 0

    m = {}
    m["project"] = projectname
    m["now"] = time.strftime("%Y-%m-%d&nbsp;%H:%M:%S", time.localtime())
    m["buttonurl"] = fullbuttonurl

    m["buildid"] = buildid
    m["systemid"] = systemid

    # Collect information about the system.
    system = get_system(systemid)
    m["hostname"] = system.hostname
    m["os_hw"] = system.os_hw
    m["os_rel"] = system.os_rel
    m["testname"] = system.testname or "default"

    # Find all files.
    files_left = {}
    for f in os.listdir(dirname):
        files_left[f] = None
    for f in hidden_files:
        if files_left.has_key(f):
            del files_left[f]
    
    maxlen = max([len(f) for f in files_left])

    tasks = get_task_results(buildid, systemid)

    # Count tasks.
    green = 0
    yellow = 0
    red = 0
    for t in tasks:
        if t.status == "PASS":
            green += 1
        if t.status == "WARN":
            yellow += 1
        if t.status == "FAIL":
            red += 1
    m["green"] = green
    m["yellow"] = yellow
    m["red"] = red

    # Emit task info.
    tl = []
    for t in tasks:
        tl.append('<p><img border=0 src="%s%s.gif"> ' % (
            fullbuttonurl, t.color()))
        tl.append(t.name)
        tl.append(" %d seconds" % t.time_spent)
        if t.warnings > 0:
            tl.append(" (%d warnings)" % t.warnings)
        tl.append("<pre>")
        for suffix in ["log.txt", "warn.txt", "fail.txt"]:
            add_file(tl, files_left, dirname, t.name + suffix, maxlen)
        for fn in files_per_task.get(t.name, []):
            add_file(tl, files_left, dirname, fn, maxlen)
        tl.append("</pre>")
            
    m["tasklist"] = ''.join(tl)

    notdone = []
    for (t, ) in get_all_task_names():
        fn = t + "log.txt"
        if files_left.has_key(fn):
            notdone.append('<p><img border=0 src="%swhite.gif"> ' % (
                fullbuttonurl))
            notdone.append(t)
            notdone.append(' not done:<pre>')
            notdone.append(open(os.path.join(dirname, fn), "r").read())
            notdone.append('</pre>')
            del files_left[fn]
    m["notdone"] = '\n'.join(notdone)

    # list all files not already handled.
    files_left = files_left.keys()
    files_left.sort()
    filelist = []
    for f in files_left:
        filelist.append(file_listing(dirname, f, maxlen))

    m["otherfiles"] = ''.join(filelist)
    open(indexname, "w").write(RESULT_PAGE % m)
    return 1

def file_listing(dirname, filename, maxlen):
    st = os.stat(os.path.join(dirname, filename))
    size = st[stat.ST_SIZE]
    tm = time.strftime("%Y-%m-%d&nbsp;%H:%M:%S",
                       time.localtime(st[stat.ST_MTIME]))
    if size != 0:
        abegin = '<a href="%s">' % filename
        aend = '</a>'
    else:
        abegin = aend = ''
    return ('<tt>   %s<img border=0 src="internal-gopher-text" alt="">' 
            ' %s%s %7d bytes   %s</tt><br>' % (
                abegin, filename.ljust(maxlen), aend, size, tm))

def mk_all_index():
    cursor = _DB.cursor()
    cursor.execute("select distinct build, system"
                   " from task_result")
    rows = cursor.fetchall()
    cursor.close()
    for (buildid, systemid) in rows:
        if mkindex(buildid, systemid, 0):
            print "Generated index for", buildid, systemid

init()
update_latest()
mk_all_index()
