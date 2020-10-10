DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
    id int unsigned NOT NULL auto_increment,
    name varchar(191) NOT NULL default 'Magick',
    mp int unsigned NOT NULL default '0',
    power int unsigned NOT NULL default '0',
    type smallint unsigned NOT NULL default '0',
    PRIMARY KEY (id)
);