SET foreign_key_checks = 0;
DROP TABLE IF EXISTS {{ table }};
SET foreign_key_checks = 1;

CREATE TABLE {{ table }} (
    id int unsigned NOT NULL auto_increment,
    username varchar(191) UNIQUE,
    password varchar(191),
    email varchar(191) UNIQUE,
    verified bool NOT NULL default '0',
    registered datetime NOT NULL default NOW(),
    online_last datetime NOT NULL default NOW(),
    role varchar(50) NOT NULL default 'member',
    latitude int NOT NULL default '0',
    longitude int NOT NULL default '0',
    difficulty varchar(50) NOT NULL default 'normal',
    class varchar(50) NOT NULL default 'warrior',
    action varchar(30) NOT NULL default 'In Town',
    hp int unsigned NOT NULL default '15',
    mp int unsigned NOT NULL default '0',
    tp int unsigned NOT NULL default '10',
    max_hp int unsigned NOT NULL default '15',
    max_mp int unsigned NOT NULL default '0',
    max_tp int unsigned NOT NULL default '10',
    level smallint unsigned NOT NULL default '1',
    gold int unsigned NOT NULL default '100',
    experience int unsigned NOT NULL default '0',
    gold_bonus smallint NOT NULL default '0',
    exp_bonus smallint NOT NULL default '0',
    strength int unsigned NOT NULL default '5',
    dexterity int unsigned NOT NULL default '5',
    attack int unsigned NOT NULL default '5',
    defense int unsigned NOT NULL default '5',
    drop_code int unsigned NOT NULL default '0',
    spells varchar(191) NOT NULL default '0',
    towns varchar(191) NOT NULL default '0',
    token varchar(191) NOT NULL default '',
    PRIMARY KEY (id)
);