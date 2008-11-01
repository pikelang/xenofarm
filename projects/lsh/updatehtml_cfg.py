# Configuration: things you must change.

# These variables are documented in the top-level README file.

# Formerly: "input".
unpacked_results_dir = "/lysator/lyswww/projects/roxen/xenofarm/lsh/files"

# Formerly: "output"
result_overview_dir = "/lysator/lyswww/users/roxen_only/nisse/xeno-lsh/"

# Formerly: "filesurl"
unpacked_results_url = "http://www.lysator.liu.se/xenofarm/lsh/files"

# Formerly: "overviewurl"
result_overview_url = "http://www.lysator.liu.se/~nisse/xeno-lsh/"
# Formerly: "buttonurl" and "fullbuttonurl"
button_url_prefix = "http://www.lysator.liu.se/~ceder/xeno/pcl-"
button_ext = ".gif"

dbname = "lsh_xenofarm"
dbuser = "nisse"
dbhost = "mysql.lysator.liu.se"
dbpwdfile = "/home/nisse/.xeno-mysql-pwd"

projectname = "lsh"

files_per_task = {
    'cfg': ['configlog.txt', 'nettleconfiglog.txt',
            'argpconfiglog.txt', 'spkiconfiglog.txt', 'sftpconfiglog.txt',
            'configcache.txt',
            'config-h.txt'],
    'ckprg': [],
    'install': ['installedfiles.txt'],
    'id_tx': ['makeinfo.txt'],
    }

files_per_task_re = {
    'ckprg': [],
    }

hidden_files = [
    'index.html',
    'buildid.txt',
    ]

hidden_tasks = [
    'oopunzip',
    'oopunpack',
    'oopinstall',
    'unzip',
    'unpack',
    'ckdist'
]
