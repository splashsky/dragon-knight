DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
  id int(11) NOT NULL auto_increment,
  postdate datetime NOT NULL default '0000-00-00 00:00:00',
  newpostdate datetime NOT NULL default '0000-00-00 00:00:00',
  author varchar(30) NOT NULL default '',
  parent int(11) NOT NULL default '0',
  replies int(11) NOT NULL default '0',
  title varchar(100) NOT NULL default '',
  content text NOT NULL,
  PRIMARY KEY  (id)
);