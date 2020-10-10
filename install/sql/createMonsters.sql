DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
    id int unsigned NOT NULL auto_increment,
    name varchar(50) NOT NULL default 'Monster',
    hp int unsigned NOT NULL default '1',
    damage int unsigned NOT NULL default '1',
    armor int unsigned NOT NULL default '0',
    level int unsigned NOT NULL default '1',
    exp int unsigned NOT NULL default '0',
    gold int unsigned NOT NULL default '0',
    immune tinyint unsigned NOT NULL default '0',
    PRIMARY KEY (id)
);