# Configuration: things you must change.

# These variables are documented in the top-level README file.

# Formerly: "input".
unpacked_results_dir = "/lysator/www/projects/xenofarm/lyskom-server/files"

# Formerly: "output"
result_overview_dir = "/lysator/www/user-pages/ceder/xeno/"

# Formerly: "filesurl"
unpacked_results_url = "http://www.lysator.liu.se/xenofarm/lyskom-server/files"

# Formerly: "overviewurl"
result_overview_url = "http://www.lysator.liu.se/~ceder/xeno/"
# Formerly: "buttonurl" and "fullbuttonurl"
button_url_prefix = "http://www.lysator.liu.se/~ceder/xeno/pcl-"
button_ext = ".gif"

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

files_per_task_re = {
    'ckprg': ['valgrind-[0-9]+\.log\.txt'],
    }

hidden_files = [
    'index.html',
    'buildid.txt',
    ]
