#
# Database tables for Xenofarm.
# Implemented to work with MySQL
# $Id: tables.sql,v 1.7 2002/12/05 14:24:37 mani Exp $
#

# The generic build table.

CREATE TABLE build (
  id      INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  time    INT UNSIGNED NOT NULL,
  export  ENUM('FAIL','WARN','PASS') NOT NULL DEFAULT 'FAIL'
);


# Table with the build systems.

CREATE TABLE system (
  id        INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
  name      VARCHAR(255) BINARY NOT NULL,
  sysname   VARCHAR(255) BINARY NOT NULL,
  release   VARCHAR(255) BINARY NOT NULL,
  version   VARCHAR(255) BINARY NOT NULL,
  machine   VARCHAR(255) BINARY NOT NULL,
  testname  VARCHAR(255) BINARY NOT NULL
);


# Table with the tasks to be completed by the client. Note that the
# sort_order is only defined for tasks with the same parent, ie. there
# might be more than one task with the same sort_order and those tasks
# may be far from each other sorting-wise.

CREATE TABLE task (
  id          INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
  sort_order  INT UNSIGNED NOT NULL,
  parent      INT UNSIGNED NOT NULL,
  name        VARCHAR(255) BINARY NOT NULL
);


# Table with the result from every build (max size is
# builds*systems*tasks).
# The column build is foreign key to build.id.
# The column system is foreign key to system.id.
# The column task is foreigh key to task.id.

CREATE TABLE task_result (
  build       INT UNSIGNED NOT NULL,
  system      INT UNSIGNED NOT NULL,
  task        INT UNSIGNED NOT NULL,
  status      ENUM('FAIL','WARN','PASS') NOT NULL DEFAULT 'FAIL',
  warnings    INT UNSIGNED NOT NULL,
  time_spent  INT UNSIGNED NOT NULL,
  PRIMARY KEY (build, system, task)
);
