# updatehtml configuration file.
# These variables are documented in the top-level README file.

unpacked_results_dir = "/lysator/www/projects/xenofarm/lyskom-server/files"
unpacked_results_url = "http://www.lysator.liu.se/xenofarm/lyskom-server/files"

result_overview_dir = "/lysator/www/projects/xenofarm/lyskom-server"
result_overview_url = "http://www.lysator.liu.se/xenofarm/lyskom-server/"

button_url_prefix = "http://www.lysator.liu.se/~ceder/xeno/pcl-"
button_ext = ".gif"

dbname = "lyskom_server_xenofarm"
dbuser = "ceder"
dbhost = "sherman"
dbpwdfile = "/home/ceder/.xeno-mysql-pwd"

projectname = "lyskom-server"

files_per_task = {
    'cfg': ['configlog.txt', 'iscconfiglog.txt', 'configcache.txt',
            'config-h.txt', 'oopconfiglog.txt'],
    'ckprg': ['lyskomd.log.txt', 'l2g.log.txt', 'leaks.log.txt'],
    'install': ['installedfiles.txt'],
    'id_tx': ['makeinfo.txt'],
    }

files_per_task_re = {
    'ckprg': ['valgrind-[0-9]+\.log\.txt',
              'memory-usage-[0-9]+\.log\.txt'],
    }

hidden_files = [
    'index.html',
    'buildid.txt',
    ]

hidden_tasks = []

hostname_maxlen = 20
