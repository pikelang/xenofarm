alter table build add column project varchar(255) not null default "FIXME" after id;
alter table build add column remote varchar(255) not null default "origin" after project;
alter table build add column branch varchar(255) not null default "FIXME" after remote;
alter table build add column commit_id char(40) null after time;
alter table build alter project drop default,
      	    	  alter remote drop default,
      	    	  alter branch drop default,
		  add index(project, remote, branch, time),
		  add index(project, remote, branch, commit_id),
		  add index(project, remote, branch, id);

CREATE TABLE server_status (
  project     VARCHAR(255) NOT NULL,
  remote      VARCHAR(255) NOT NULL,
  branch      VARCHAR(255) NOT NULL,
  updated     TIMESTAMP NOT NULL,
  message     VARCHAR(255) NOT NULL,
  PRIMARY KEY (project, remote, branch)
);

alter table task add column project varchar(255) not null default "FIXME" after parent;
alter table task alter project drop default;
