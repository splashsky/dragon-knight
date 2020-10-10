DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
    id int unsigned NOT NULL auto_increment,
    name varchar(191) NOT NULL default '',
    level int unsigned NOT NULL default '0',
    type smallint unsigned NOT NULL default '0',
    special_1 varchar(191) NOT NULL default '',
    special_2 varchar(191) NOT NULL default '',
    PRIMARY KEY (id)
);