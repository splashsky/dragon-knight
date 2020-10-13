DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
    id int unsigned NOT NULL auto_increment,
    user_id int unsigned UNIQUE,
    weapon_id int unsigned NOT NULL default '0',
    armor_id int unsigned NOT NULL default '0',
    shield_id int unsigned NOT NULL default '0',
    ring_id int unsigned NOT NULL default '0',
    amulet_id int unsigned NOT NULL default '0',
    rune_id int unsigned NOT NULL default '0',
    weapon_name varchar(191) default '',
    armor_name varchar(191) default '',
    shield_name varchar(191) default '',
    ring_name varchar(191) default '',
    amulet_name varchar(191) default '',
    rune_name varchar(191) default '',
    PRIMARY KEY (id),
    CONSTRAINT `fk_user_inventory` FOREIGN KEY (user_id) REFERENCES {{ users }} (id) ON DELETE CASCADE
);