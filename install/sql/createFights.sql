DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
    id int unsigned NOT NULL auto_increment,
    user_id int unsigned UNIQUE,
    monster_id int unsigned NOT NULL default '0',
    monster_name varchar(50) NOT NULL default 'Monster',
    monster_hp int unsigned NOT NULL default '1',
    monster_damage int unsigned NOT NULL default '1',
    monster_armor int unsigned NOT NULL default '1',
    monster_sleep smallint unsigned NOT NULL default '0',
    monster_immune tinyint unsigned NOT NULL default '0',
    uber_damage int unsigned NOT NULL default '0',
    uber_defense int unsigned NOT NULL default '0',
    PRIMARY KEY (id),
    CONSTRAINT `fk_user_fight` FOREIGN KEY (user_id) REFERENCES {{ users }} (id) ON DELETE CASCADE
);