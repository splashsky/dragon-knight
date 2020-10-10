DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
    id tinyint unsigned NOT NULL auto_increment,
    game_name varchar(191) NOT NULL default 'Dragon Knight',
    game_size int unsigned NOT NULL default '250',
    game_open bool NOT NULL default '1',
    game_url varchar(191) NOT NULL default '',
    admin_email varchar(191) NOT NULL default '',
    forum_type tinyint unsigned NOT NULL default '0',
    forum_address varchar(191) NOT NULL default '',
    verify_email bool NOT NULL default '0',
    show_news bool NOT NULL default '1',
    show_babble bool NOT NULL default '1',
    show_online bool NOT NULL default '1',
    PRIMARY KEY (id)
);