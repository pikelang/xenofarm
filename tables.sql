#
# Database tables for Xenofarm.
# Implemented to work with MySQL
# $Id: tables.sql,v 1.4 2002/10/07 22:22:49 mani Exp $
#

# The generic build table.

CREATE TABLE build (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    time INT UNSIGNED NOT NULL, project VARCHAR(255) NOT NULL);


# Table with the build systems

CREATE TABLE system (id INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
                     name VARCHAR(255) NOT NULL,
                     platform VARCHAR(255) NOT NULL);


# Table with the result from every build (max size is builds*systems)
# The column build is foreign key to build.id
# The column system is foreign key to system.id

CREATE TABLE result (build INT UNSIGNED NOT NULL,
                     system INT UNSIGNED NOT NULL,
                     status ENUM('failed','built') NOT NULL,
                     warnings INT UNSIGNED NOT NULL,
                     time_spent INT UNSIGNED NOT NULL,
		     PRIMARY KEY (build, system) );
