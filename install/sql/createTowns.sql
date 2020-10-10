DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
    id int unsigned NOT NULL auto_increment,
    name varchar(191) NOT NULL default 'Town',
    latitude int NOT NULL default '0',
    longitude int NOT NULL default '0',
    inn_price mediumint NOT NULL default '5',
    map_price int NOT NULL default '25',
    tp_cost int unsigned NOT NULL default '1',
    items varchar(191) NOT NULL,
    PRIMARY KEY (id)
);