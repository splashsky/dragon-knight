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
    weapon_name varchar(191),
    armor_name varchar(191),
    shield_name varchar(191),
    ring_name varchar(191),
    amulet_name varchar(191),
    rune_name varchar(191),
    PRIMARY KEY (id),
    CONSTRAINT `fk_user_inventory` FOREIGN KEY (user_id) REFERENCES {{ users }} (id) ON DELETE CASCADE
);