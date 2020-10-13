DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
    id int unsigned NOT NULL auto_increment,
    name varchar(191) NOT NULL default 'Item',
    type varchar(50) NOT NULL default 'weapon',
    value int unsigned NOT NULL default '0',
    attribute int unsigned NOT NULL default '0',
    special varchar(191),
    PRIMARY KEY (id)
);