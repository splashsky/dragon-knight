DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
    id int unsigned NOT NULL auto_increment,
    user_id int unsigned,
    posted datetime,
    content text NOT NULL,
    PRIMARY KEY (id)
);