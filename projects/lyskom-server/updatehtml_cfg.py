# Configuration: things you must change.

input = "/lysator/www/projects/xenofarm/lyskom-server/files"
output = "/lysator/www/user-pages/ceder/xeno/"

filesurl = "http://www.lysator.liu.se/xenofarm/lyskom-server/files"
overviewurl = "http://www.lysator.liu.se/~ceder/xeno/"
buttonurl = "pcl-"
fullbuttonurl = overviewurl + buttonurl

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
            

