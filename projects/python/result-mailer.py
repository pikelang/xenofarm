#!/sw/local/bin/python

import MySQLdb

from time import time, strftime, gmtime

url = "http://www.lysator.liu.se/xenofarm/python"
yesterday = time() - 24 * 60 * 60 * 2

recent_builds = """
  SELECT id, time 
    FROM build 
   WHERE time >= %i AND project = 'python' 
ORDER BY time
""" % yesterday

recent_results = """
   SELECT r.build, s.name, s.platform, r.system, r.status, r.warnings
     FROM (system s LEFT JOIN result r ON s.id = r.system)
          LEFT JOIN build b ON r.build = b.id
    WHERE b.time >= %i AND b.project LIKE 'python'
 ORDER BY s.name, s.platform, r.build
""" % yesterday

db = MySQLdb.connect(host = "mysql.lysator.liu.se",
                     db = "sfarmer",
                     user = "sfarmer_ro",
                     passwd = "qgrXfAvh")
cur = db.cursor()
cur.execute(recent_builds)

### List the builds since yesterday

print "Recent builds:"

while 1:
    try:
        (id, time) = cur.fetchone()
    except TypeError:
        break

    print "%5i - %s" % (id, strftime("%Y-%m-%d %H:%M", gmtime(time)))

### Get the results on these builds

cur.execute(recent_results)

name = ""

current_name = ""
current_platform = ""
count_builds = 0
has_failure = 0
end = 0

print
print "Contributing heroes:"
print

while 1:
    try:
        (build, name, platform, system_id, status, warnings) = \
	    cur.fetchone()
        buildstr = "%5i -" % build
    except TypeError:
        if count_builds == 0:
            print "No new builds to report on"
        end = 1

    if name != current_name or end == 1:
        # Time for a new host
        if count_builds > 0:
            # Does not occur at first visit to "new-host" if
            if not has_failure:
                print "        total %i builds [%i warnings; %+i]" % \
                      (count_builds, prev_warnings,
                       prev_warnings - start_warnings)
            else:
                print "        final build failed"
            print

        if end:
            break
        
        # prepare for processing new host
        current_name = name
	current_platform = platform
        start_warnings = warnings
        count_builds = 0
        has_failure = 0

        # The new host
        print "> %s [%s] <" % (name, platform)

    count_builds += 1
    prev_warnings = warnings

    if status == "failed":
        if not has_failure and count_builds > 1:
            print "%s last successful build [%i warnings]" % \
                  ("%5i -" % prev_build, warnings)
        has_failure = 1
        # fail time!
        print "%s failed %s/files/%i_%i" % (buildstr, url, build, system_id)
    else:
        if has_failure:
            print "%s new successful build [%i warnings]" % \
                  (buildstr, warnings)
            has_failure = 0

    prev_build = build
