alter table build add column project varchar(255) not null default "FIXME" after id;
alter table build add column branch varchar(255) not null default "FIXME" after project;
alter table build alter project drop default,
      	    	  alter branch drop default,
		  add index(project, branch, time);

CREATE TABLE server_status (
  project     VARCHAR(255) NOT NULL,
  branch      VARCHAR(255) NOT NULL,
  updated     TIMESTAMP NOT NULL,
  message     VARCHAR(255) NOT NULL,
  PRIMARY KEY (project, branch)
);

alter table build add index(project, branch, id);
