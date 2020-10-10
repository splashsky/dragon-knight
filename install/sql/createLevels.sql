DROP TABLE IF EXISTS {{ table }};

CREATE TABLE {{ table }} (
  id smallint(5) unsigned NOT NULL auto_increment,
  1_exp mediumint(8) unsigned NOT NULL default '0',
  1_hp smallint(5) unsigned NOT NULL default '0',
  1_mp smallint(5) unsigned NOT NULL default '0',
  1_tp smallint(5) unsigned NOT NULL default '0',
  1_strength smallint(5) unsigned NOT NULL default '0',
  1_dexterity smallint(5) unsigned NOT NULL default '0',
  1_spells tinyint(3) unsigned NOT NULL default '0',
  2_exp mediumint(8) unsigned NOT NULL default '0',
  2_hp smallint(5) unsigned NOT NULL default '0',
  2_mp smallint(5) unsigned NOT NULL default '0',
  2_tp smallint(5) unsigned NOT NULL default '0',
  2_strength smallint(5) unsigned NOT NULL default '0',
  2_dexterity smallint(5) unsigned NOT NULL default '0',
  2_spells tinyint(3) unsigned NOT NULL default '0',
  3_exp mediumint(8) unsigned NOT NULL default '0',
  3_hp smallint(5) unsigned NOT NULL default '0',
  3_mp smallint(5) unsigned NOT NULL default '0',
  3_tp smallint(5) unsigned NOT NULL default '0',
  3_strength smallint(5) unsigned NOT NULL default '0',
  3_dexterity smallint(5) unsigned NOT NULL default '0',
  3_spells tinyint(3) unsigned NOT NULL default '0',
  PRIMARY KEY  (id)
);