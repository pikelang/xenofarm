alter table build add column project varchar(255) not null default "FIXME" after id;
alter table build add column branch varchar(255) not null default "FIXME" after project;
alter table build alter project drop default,
      	    	  alter branch drop default,
		  add index(project, branch, time);
