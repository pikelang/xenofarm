#
# Database tables for Xenofarm.
# Implemented to work with MySQL
# $Id: tables.sql,v 1.1 2002/05/12 18:10:17 mani Exp $
#

# The generic build table.

CREATE TABLE build (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    time INT UNSIGNED NOT NULL, project VARCHAR(255) NOT NULL);

# Build table for the Pike project.

# CREATE TABLE build (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
#		       time INT UNSIGNED NOT NULL,
#		       project ENUM('pike7.3') NOT NULL,
#		       export ENUM('yes','no') NOT NULL DEFAULT 'yes',
#		       documentation ENUM('yes','no') );
 

# Table with the build systems

CREATE TABLE system (id INT UNSIGNED AUTO INCREMENT NOT NULL PRIMARY KEY,
                     name VARCHAR(255) NOT NULL,
                     platform VARCHAR(255) NOT NULL)


# Table with the result from every build (max size is builds*systems)
# The column build is foreign key to build.id
# The column system is foreign key to system.id

CREATE TABLE result (build INT UNSIGNED NOT NULL,
                     system INT UNSIGNED NOT NULL,
                     status ENUM('failed','built','verified','exported') NOT NULL,
                     warnings INT UNSIGNED NOT NULL,
                     time_spent INT UNSIGNED NOT NULL)
