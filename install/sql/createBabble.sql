DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
    id int unsigned NOT NULL auto_increment,
    user_id int unsigned NOT NULL default '1',
    posted datetime NOT NULL default NOW(),
    babble varchar(191) NOT NULL default '',
    PRIMARY KEY (id),
    CONSTRAINT `fk_user_babble` FOREIGN KEY (user_id) REFERENCES {{ users }} (id) ON DELETE CASCADE
);