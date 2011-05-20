alter table build add column project varchar(255) not null default "FIXME" after id;
alter table build add column branch varchar(255) not null default "FIXME" after project;
alter table build add column commit_id char(40) null after time;
alter table build alter project drop default,
      	    	  alter branch drop default,
		  add index(project, branch, time),
		  add index(project, branch, commit_id),
		  add index(project, branch, id);

CREATE TABLE server_status (
  project     VARCHAR(255) NOT NULL,
  branch      VARCHAR(255) NOT NULL,
  updated     TIMESTAMP NOT NULL,
  message     VARCHAR(255) NOT NULL,
  PRIMARY KEY (project, branch)
);

alter table task add column project varchar(255) not null default "FIXME" after parent;
alter table task alter project drop default;
