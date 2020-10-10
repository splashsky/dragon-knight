DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
    id int unsigned NOT NULL auto_increment,
    type tinyint unsigned NOT NULL default '0',
    name varchar(191) NOT NULL default 'Item',
    value int unsigned NOT NULL default '0',
    attribute int unsigned NOT NULL default '0',
    special varchar(191) NOT NULL default '',
    PRIMARY KEY (id)
);