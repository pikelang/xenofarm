import MySQLdb
from string import join, strip

pwd = strip(open("/home/sfarmer/.xeno-mysql-pwd").readline())
db = MySQLdb.connect(host="localhost", user="sfarmer",
                     db="python_devel_xenofarm", passwd=pwd)

def create_qualified_name(id, tasks):
    task = tasks[id]
    if task[2] > 0:
        return create_qualified_name(task[2], tasks) + "/" + task[0]
    else:
        return task[0]


# The result of one task for one build on one system
class TaskResult:
    def __init__(self, taskid, task, status):
        self.taskid = taskid
        self.task = task
        self.status = status

    def successful(self):
        return self.status == "PASS"

    def get_full_name(self):
        return self.task[3]


class TaskParser:
    # Get the expected list of tasks
    _get_tasklist = "SELECT id, sort_order, parent, name FROM task ORDER BY sort_order"
    def __init__(self):
        self.tasks = {}

        tasklist = db.cursor()
        tasklist.execute(self._get_tasklist)
        for id, sort_order, parent, name in tasklist.fetchall():
            self.tasks[id] = [name, sort_order, parent, name]

        # create list of qualified task names
        for id, task in filter(lambda task: task[1][2] > 0,
                               self.tasks.items()):
            self.tasks[id][3] = create_qualified_name(id, self.tasks)

    def make_taskresult(self, taskid, status):
        return TaskResult(taskid, self.tasks[taskid], status)

    def get_expected_task_ids(self):
        ids = self.tasks.keys()
        ids.sort(lambda a, b: int(self.tasks[a][1] - self.tasks[b][1]))
        return ids

    def get_task_info(self, id):
        return self.tasks[id]

class ResultSet:
    # Get results on all tasks from one build by one system
    _single_result = "SELECT task, status FROM task_result WHERE system = %i AND build = %i"
    def __init__(self, task_parser, build, system, time):
        self.tasks = {}
        self.success = 1
        self.time = time
        self.build = build
        self.system = system
        self.task_parser = task_parser

        taskcur = db.cursor()
        taskcur.execute(self._single_result % (system, build))

        for taskid, status in taskcur.fetchall():
            self.tasks[taskid] = self.task_parser.make_taskresult(taskid,
                                                                  status)
            # If any one task is unsuccessful, the whole result is
            # considered unsatisfactory
            if status != "PASS":
                self.success = 0

            # FIXME: make sure we have a TaskResult for every task in
            # the build, even if it was skipped

    def successful(self):         return self.success
    def get_time(self):           return self.time
    def get_build_id(self):       return self.build
    def get_system_id(self):      return self.system

    def get_tasks(self):
        return self.tasks.values()

    def get_task_by_id(self, id):
        return self.tasks[id]

    def get_failed_tasks(self):
        return filter(lambda x: not x.successful(), self.tasks.values())


class SystemList:
    # Get info on one system
    _system_info = "SELECT name, sysname, release, version, machine, testname FROM system WHERE id = %i"

    def __init__(self):
        self.dict = {}
        self.infocur = db.cursor()

    def add_system(self, system):
        if not self.dict.has_key(system):
            self.infocur.execute(self._system_info % system)
            # name, sysname, release, version, machine, testname
            self.dict[system] = self.infocur.fetchone()

    def get_list(self):
        return self.dict.values()

    def get_identity(self, system):
        dasys = self.dict[system]
        name = dasys[0]
        test = ""
        if dasys[5] != "":
            test = "-%s" % dasys[5]

        return "%s%s" % (name, test)


class ResultList:
    def __init__(self, query, parser):
        self.results = []
        self.syslist = SystemList()
        self.buildlist = []
        if parser != None:
            self.parser = parser
        else:
            self.parser = TaskParser()

        self.recent = db.cursor()
        self.recent.execute(query)

        for build, system, time in self.recent.fetchall():
            self.syslist.add_system(system)
            if not build in self.buildlist:
                self.buildlist.append(build)
            self.results.append(ResultSet(self.parser, build, system, time))

    def get_system_list(self):
        return self.syslist

    def get_build_list(self):
        return self.buildlist

    def get_results_by_build(self, daid):
        return filter(lambda res, id=daid: res.get_build_id() == id,
                      self.results)

    def get_successful(self):
        return filter(lambda x: x.successful(), self.results)

    def get_failed(self):
        return filter(lambda x: not x.successful(), self.results)


    def get_task_parser(self):
        return self.parser
