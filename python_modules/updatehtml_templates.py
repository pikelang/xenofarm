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

<a href="%(overviewurl)slatest.html">[latest builds]</a>
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
