-- tests/fixtures/seed_v4.sql :: the default game data of schema version 4 (spells with type
-- and attribute; class ids only, the rest comes from the content sync), as shipped up to
-- commit d47a7bb. tests/e2e/migrate.sh loads it into databases built from schema_v4.sql.
-- Do not edit.

-- Default game data, ported 1:1 from the original install.php ("Complete Setup").
-- Differences: control.verifyemail = 0 (PLAN.md) and no difficulty names/modifiers
-- (difficulty levels were removed); news.postdate is unix time (2004-01-01 12:00:00 UTC).
-- The original levels table and class names are content files now (app/content/classes/;
-- experience, TP and the milestone HP are formulas in app/lib/leveling.lua).
-- Dragon's -> Dragon''s (SQL quoting).

-- classes: the original classes keep their ids; the content sync (end of dk install)
-- fills in the rest from app/content/classes/*.lua. Loaded by partial setups too.
INSERT INTO classes (id, key, name) VALUES (1, 'mage', 'Mage');
INSERT INTO classes (id, key, name) VALUES (2, 'warrior', 'Warrior');
INSERT INTO classes (id, key, name) VALUES (3, 'paladin', 'Paladin');

-- control
INSERT INTO control (id, gamename, gamesize, gameopen, gameurl, adminemail, forumtype, forumaddress, compression, verifyemail, shownews, showbabble, showonline) VALUES (1, 'Dragon Knight', 250, 1, '', '', 1, '', 1, 0, 1, 1, 1);

-- drops
INSERT INTO drops VALUES (1, 'Life Pebble', 1, 1, 'maxhp,10', 'X');
INSERT INTO drops VALUES (2, 'Life Stone', 10, 1, 'maxhp,25', 'X');
INSERT INTO drops VALUES (3, 'Life Rock', 25, 1, 'maxhp,50', 'X');
INSERT INTO drops VALUES (4, 'Magic Pebble', 1, 1, 'maxmp,10', 'X');
INSERT INTO drops VALUES (5, 'Magic Stone', 10, 1, 'maxmp,25', 'X');
INSERT INTO drops VALUES (6, 'Magic Rock', 25, 1, 'maxmp,50', 'X');
INSERT INTO drops VALUES (7, 'Dragon''s Scale', 10, 1, 'defensepower,25', 'X');
INSERT INTO drops VALUES (8, 'Dragon''s Plate', 30, 1, 'defensepower,50', 'X');
INSERT INTO drops VALUES (9, 'Dragon''s Claw', 10, 1, 'attackpower,25', 'X');
INSERT INTO drops VALUES (10, 'Dragon''s Tooth', 30, 1, 'attackpower,50', 'X');
INSERT INTO drops VALUES (11, 'Dragon''s Tear', 35, 1, 'strength,50', 'X');
INSERT INTO drops VALUES (12, 'Dragon''s Wing', 35, 1, 'dexterity,50', 'X');
INSERT INTO drops VALUES (13, 'Demon''s Sin', 35, 1, 'maxhp,-50', 'strength,50');
INSERT INTO drops VALUES (14, 'Demon''s Fall', 35, 1, 'maxmp,-50', 'strength,50');
INSERT INTO drops VALUES (15, 'Demon''s Lie', 45, 1, 'maxhp,-100', 'strength,100');
INSERT INTO drops VALUES (16, 'Demon''s Hate', 45, 1, 'maxmp,-100', 'strength,100');
INSERT INTO drops VALUES (17, 'Angel''s Joy', 25, 1, 'maxhp,25', 'strength,25');
INSERT INTO drops VALUES (18, 'Angel''s Rise', 30, 1, 'maxhp,50', 'strength,50');
INSERT INTO drops VALUES (19, 'Angel''s Truth', 35, 1, 'maxhp,75', 'strength,75');
INSERT INTO drops VALUES (20, 'Angel''s Love', 40, 1, 'maxhp,100', 'strength,100');
INSERT INTO drops VALUES (21, 'Seraph''s Joy', 25, 1, 'maxmp,25', 'dexterity,25');
INSERT INTO drops VALUES (22, 'Seraph''s Rise', 30, 1, 'maxmp,50', 'dexterity,50');
INSERT INTO drops VALUES (23, 'Seraph''s Truth', 35, 1, 'maxmp,75', 'dexterity,75');
INSERT INTO drops VALUES (24, 'Seraph''s Love', 40, 1, 'maxmp,100', 'dexterity,100');
INSERT INTO drops VALUES (25, 'Ruby', 50, 1, 'maxhp,150', 'X');
INSERT INTO drops VALUES (26, 'Pearl', 50, 1, 'maxmp,150', 'X');
INSERT INTO drops VALUES (27, 'Emerald', 50, 1, 'strength,150', 'X');
INSERT INTO drops VALUES (28, 'Topaz', 50, 1, 'dexterity,150', 'X');
INSERT INTO drops VALUES (29, 'Obsidian', 50, 1, 'attackpower,150', 'X');
INSERT INTO drops VALUES (30, 'Diamond', 50, 1, 'defensepower,150', 'X');
INSERT INTO drops VALUES (31, 'Memory Drop', 5, 1, 'expbonus,10', 'X');
INSERT INTO drops VALUES (32, 'Fortune Drop', 5, 1, 'goldbonus,10', 'X');

-- items
INSERT INTO items VALUES (1, 1, 'Stick', 10, 2, 'X');
INSERT INTO items VALUES (2, 1, 'Branch', 30, 4, 'X');
INSERT INTO items VALUES (3, 1, 'Club', 40, 5, 'X');
INSERT INTO items VALUES (4, 1, 'Dagger', 90, 8, 'X');
INSERT INTO items VALUES (5, 1, 'Hatchet', 150, 12, 'X');
INSERT INTO items VALUES (6, 1, 'Axe', 200, 16, 'X');
INSERT INTO items VALUES (7, 1, 'Brand', 300, 25, 'X');
INSERT INTO items VALUES (8, 1, 'Poleaxe', 500, 35, 'X');
INSERT INTO items VALUES (9, 1, 'Broadsword', 800, 45, 'X');
INSERT INTO items VALUES (10, 1, 'Battle Axe', 1200, 50, 'X');
INSERT INTO items VALUES (11, 1, 'Claymore', 2000, 60, 'X');
INSERT INTO items VALUES (12, 1, 'Dark Axe', 3000, 100, 'expbonus,-5');
INSERT INTO items VALUES (13, 1, 'Dark Sword', 4500, 125, 'expbonus,-10');
INSERT INTO items VALUES (14, 1, 'Bright Sword', 6000, 100, 'expbonus,10');
INSERT INTO items VALUES (15, 1, 'Magic Sword', 10000, 150, 'maxmp,50');
INSERT INTO items VALUES (16, 1, 'Destiny Blade', 50000, 250, 'strength,50');
INSERT INTO items VALUES (17, 2, 'Skivvies', 25, 2, 'goldbonus,10');
INSERT INTO items VALUES (18, 2, 'Clothes', 50, 5, 'X');
INSERT INTO items VALUES (19, 2, 'Leather Armor', 75, 10, 'X');
INSERT INTO items VALUES (20, 2, 'Hard Leather Armor', 150, 25, 'X');
INSERT INTO items VALUES (21, 2, 'Chain Mail', 300, 30, 'X');
INSERT INTO items VALUES (22, 2, 'Bronze Plate', 900, 50, 'X');
INSERT INTO items VALUES (23, 2, 'Iron Plate', 2000, 100, 'X');
INSERT INTO items VALUES (24, 2, 'Magic Armor', 4000, 125, 'maxmp,50');
INSERT INTO items VALUES (25, 2, 'Dark Armor', 5000, 150, 'expbonus,-10');
INSERT INTO items VALUES (26, 2, 'Bright Armor', 10000, 175, 'expbonus,10');
INSERT INTO items VALUES (27, 2, 'Destiny Raiment', 50000, 200, 'dexterity,50');
INSERT INTO items VALUES (28, 3, 'Reed Shield', 50, 2, 'X');
INSERT INTO items VALUES (29, 3, 'Buckler', 100, 4, 'X');
INSERT INTO items VALUES (30, 3, 'Small Shield', 500, 10, 'X');
INSERT INTO items VALUES (31, 3, 'Large Shield', 2500, 30, 'X');
INSERT INTO items VALUES (32, 3, 'Silver Shield', 10000, 60, 'X');
INSERT INTO items VALUES (33, 3, 'Destiny Aegis', 25000, 100, 'maxhp,50');

-- monsters
INSERT INTO monsters VALUES (1, 'Blue Slime', 4, 3, 1, 1, 1, 1, 0);
INSERT INTO monsters VALUES (2, 'Red Slime', 6, 5, 1, 1, 2, 1, 0);
INSERT INTO monsters VALUES (3, 'Critter', 6, 5, 2, 1, 4, 2, 0);
INSERT INTO monsters VALUES (4, 'Creature', 10, 8, 2, 2, 4, 2, 0);
INSERT INTO monsters VALUES (5, 'Shadow', 10, 9, 3, 2, 6, 2, 1);
INSERT INTO monsters VALUES (6, 'Drake', 11, 10, 3, 2, 8, 3, 0);
INSERT INTO monsters VALUES (7, 'Shade', 12, 10, 3, 3, 10, 3, 1);
INSERT INTO monsters VALUES (8, 'Drakelor', 14, 12, 4, 3, 10, 3, 0);
INSERT INTO monsters VALUES (9, 'Silver Slime', 15, 100, 200, 30, 15, 1000, 2);
INSERT INTO monsters VALUES (10, 'Scamp', 16, 13, 5, 4, 15, 5, 0);
INSERT INTO monsters VALUES (11, 'Raven', 16, 13, 5, 4, 18, 6, 0);
INSERT INTO monsters VALUES (12, 'Scorpion', 18, 14, 6, 5, 20, 7, 0);
INSERT INTO monsters VALUES (13, 'Illusion', 20, 15, 6, 5, 20, 7, 1);
INSERT INTO monsters VALUES (14, 'Nightshade', 22, 16, 6, 6, 24, 8, 0);
INSERT INTO monsters VALUES (15, 'Drakemal', 22, 18, 7, 6, 24, 8, 0);
INSERT INTO monsters VALUES (16, 'Shadow Raven', 24, 18, 7, 6, 26, 9, 1);
INSERT INTO monsters VALUES (17, 'Ghost', 24, 20, 8, 6, 28, 9, 0);
INSERT INTO monsters VALUES (18, 'Frost Raven', 26, 20, 8, 7, 30, 10, 0);
INSERT INTO monsters VALUES (19, 'Rogue Scorpion', 28, 22, 9, 7, 32, 11, 0);
INSERT INTO monsters VALUES (20, 'Ghoul', 29, 24, 9, 7, 34, 11, 0);
INSERT INTO monsters VALUES (21, 'Magician', 30, 24, 10, 8, 36, 12, 0);
INSERT INTO monsters VALUES (22, 'Rogue', 30, 25, 12, 8, 40, 13, 0);
INSERT INTO monsters VALUES (23, 'Drakefin', 32, 26, 12, 8, 40, 13, 0);
INSERT INTO monsters VALUES (24, 'Shimmer', 32, 26, 14, 8, 45, 15, 1);
INSERT INTO monsters VALUES (25, 'Fire Raven', 34, 28, 14, 9, 45, 15, 0);
INSERT INTO monsters VALUES (26, 'Dybbuk', 34, 28, 14, 9, 50, 17, 0);
INSERT INTO monsters VALUES (27, 'Knave', 36, 30, 15, 9, 52, 17, 0);
INSERT INTO monsters VALUES (28, 'Goblin', 36, 30, 15, 10, 54, 18, 0);
INSERT INTO monsters VALUES (29, 'Skeleton', 38, 30, 18, 10, 58, 19, 0);
INSERT INTO monsters VALUES (30, 'Dark Slime', 38, 32, 18, 10, 62, 21, 0);
INSERT INTO monsters VALUES (31, 'Silver Scorpion', 30, 160, 350, 40, 63, 2000, 2);
INSERT INTO monsters VALUES (32, 'Mirage', 40, 32, 20, 11, 64, 21, 1);
INSERT INTO monsters VALUES (33, 'Sorceror', 41, 33, 22, 11, 68, 23, 0);
INSERT INTO monsters VALUES (34, 'Imp', 42, 34, 22, 12, 70, 23, 0);
INSERT INTO monsters VALUES (35, 'Nymph', 43, 35, 22, 12, 70, 23, 0);
INSERT INTO monsters VALUES (36, 'Scoundrel', 43, 35, 22, 12, 75, 25, 0);
INSERT INTO monsters VALUES (37, 'Megaskeleton', 44, 36, 24, 13, 78, 26, 0);
INSERT INTO monsters VALUES (38, 'Grey Wolf', 44, 36, 24, 13, 82, 27, 0);
INSERT INTO monsters VALUES (39, 'Phantom', 46, 38, 24, 14, 85, 28, 1);
INSERT INTO monsters VALUES (40, 'Specter', 46, 38, 24, 14, 90, 30, 0);
INSERT INTO monsters VALUES (41, 'Dark Scorpion', 48, 40, 26, 15, 95, 32, 1);
INSERT INTO monsters VALUES (42, 'Warlock', 48, 40, 26, 15, 100, 33, 1);
INSERT INTO monsters VALUES (43, 'Orc', 49, 42, 28, 15, 104, 35, 0);
INSERT INTO monsters VALUES (44, 'Sylph', 49, 42, 28, 15, 106, 35, 0);
INSERT INTO monsters VALUES (45, 'Wraith', 50, 45, 30, 16, 108, 36, 0);
INSERT INTO monsters VALUES (46, 'Hellion', 50, 45, 30, 16, 110, 37, 0);
INSERT INTO monsters VALUES (47, 'Bandit', 52, 45, 30, 16, 114, 38, 0);
INSERT INTO monsters VALUES (48, 'Ultraskeleton', 52, 46, 32, 16, 116, 39, 0);
INSERT INTO monsters VALUES (49, 'Dark Wolf', 54, 47, 36, 17, 120, 40, 1);
INSERT INTO monsters VALUES (50, 'Troll', 56, 48, 36, 17, 120, 40, 0);
INSERT INTO monsters VALUES (51, 'Werewolf', 56, 48, 38, 17, 124, 41, 0);
INSERT INTO monsters VALUES (52, 'Hellcat', 58, 50, 38, 18, 128, 43, 0);
INSERT INTO monsters VALUES (53, 'Spirit', 58, 50, 38, 18, 132, 44, 0);
INSERT INTO monsters VALUES (54, 'Nisse', 60, 52, 40, 19, 132, 44, 0);
INSERT INTO monsters VALUES (55, 'Dawk', 60, 54, 40, 19, 136, 45, 0);
INSERT INTO monsters VALUES (56, 'Figment', 64, 55, 42, 19, 140, 47, 1);
INSERT INTO monsters VALUES (57, 'Hellhound', 66, 56, 44, 20, 140, 47, 0);
INSERT INTO monsters VALUES (58, 'Wizard', 66, 56, 44, 20, 144, 48, 0);
INSERT INTO monsters VALUES (59, 'Uruk', 68, 58, 44, 20, 146, 49, 0);
INSERT INTO monsters VALUES (60, 'Siren', 68, 400, 800, 50, 10000, 50, 2);
INSERT INTO monsters VALUES (61, 'Megawraith', 70, 60, 46, 21, 155, 52, 0);
INSERT INTO monsters VALUES (62, 'Dawkin', 70, 60, 46, 21, 155, 52, 0);
INSERT INTO monsters VALUES (63, 'Grey Bear', 70, 62, 48, 21, 160, 53, 0);
INSERT INTO monsters VALUES (64, 'Haunt', 72, 62, 48, 22, 160, 53, 0);
INSERT INTO monsters VALUES (65, 'Hellbeast', 74, 64, 50, 22, 165, 55, 0);
INSERT INTO monsters VALUES (66, 'Fear', 76, 66, 52, 23, 165, 55, 0);
INSERT INTO monsters VALUES (67, 'Beast', 76, 66, 52, 23, 170, 57, 0);
INSERT INTO monsters VALUES (68, 'Ogre', 78, 68, 54, 23, 170, 57, 0);
INSERT INTO monsters VALUES (69, 'Dark Bear', 80, 70, 56, 24, 175, 58, 1);
INSERT INTO monsters VALUES (70, 'Fire', 80, 72, 56, 24, 175, 58, 0);
INSERT INTO monsters VALUES (71, 'Polgergeist', 84, 74, 58, 25, 180, 60, 0);
INSERT INTO monsters VALUES (72, 'Fright', 86, 76, 58, 25, 180, 60, 0);
INSERT INTO monsters VALUES (73, 'Lycan', 88, 78, 60, 25, 185, 62, 0);
INSERT INTO monsters VALUES (74, 'Terra Elemental', 88, 80, 62, 25, 185, 62, 1);
INSERT INTO monsters VALUES (75, 'Necromancer', 90, 80, 62, 26, 190, 63, 0);
INSERT INTO monsters VALUES (76, 'Ultrawraith', 90, 82, 64, 26, 190, 63, 0);
INSERT INTO monsters VALUES (77, 'Dawkor', 92, 82, 64, 26, 195, 65, 0);
INSERT INTO monsters VALUES (78, 'Werebear', 92, 84, 65, 26, 195, 65, 0);
INSERT INTO monsters VALUES (79, 'Brute', 94, 84, 65, 27, 200, 67, 0);
INSERT INTO monsters VALUES (80, 'Large Beast', 96, 88, 66, 27, 200, 67, 0);
INSERT INTO monsters VALUES (81, 'Horror', 96, 88, 68, 27, 210, 70, 0);
INSERT INTO monsters VALUES (82, 'Flame', 100, 90, 70, 28, 210, 70, 0);
INSERT INTO monsters VALUES (83, 'Lycanthor', 100, 90, 70, 28, 210, 70, 0);
INSERT INTO monsters VALUES (84, 'Wyrm', 100, 92, 72, 28, 220, 73, 0);
INSERT INTO monsters VALUES (85, 'Aero Elemental', 104, 94, 74, 29, 220, 73, 1);
INSERT INTO monsters VALUES (86, 'Dawkare', 106, 96, 76, 29, 220, 73, 0);
INSERT INTO monsters VALUES (87, 'Large Brute', 108, 98, 78, 29, 230, 77, 0);
INSERT INTO monsters VALUES (88, 'Frost Wyrm', 110, 100, 80, 30, 230, 77, 0);
INSERT INTO monsters VALUES (89, 'Knight', 110, 102, 80, 30, 240, 80, 0);
INSERT INTO monsters VALUES (90, 'Lycanthra', 112, 104, 82, 30, 240, 80, 0);
INSERT INTO monsters VALUES (91, 'Terror', 115, 108, 84, 31, 250, 83, 0);
INSERT INTO monsters VALUES (92, 'Blaze', 118, 108, 84, 31, 250, 83, 0);
INSERT INTO monsters VALUES (93, 'Aqua Elemental', 120, 110, 90, 31, 260, 87, 1);
INSERT INTO monsters VALUES (94, 'Fire Wyrm', 120, 110, 90, 32, 260, 87, 0);
INSERT INTO monsters VALUES (95, 'Lesser Wyvern', 122, 110, 92, 32, 270, 90, 0);
INSERT INTO monsters VALUES (96, 'Doomer', 124, 112, 92, 32, 270, 90, 0);
INSERT INTO monsters VALUES (97, 'Armor Knight', 130, 115, 95, 33, 280, 93, 0);
INSERT INTO monsters VALUES (98, 'Wyvern', 134, 120, 95, 33, 290, 97, 0);
INSERT INTO monsters VALUES (99, 'Nightmare', 138, 125, 100, 33, 300, 100, 0);
INSERT INTO monsters VALUES (100, 'Fira Elemental', 140, 125, 100, 34, 310, 103, 1);
INSERT INTO monsters VALUES (101, 'Megadoomer', 140, 128, 105, 34, 320, 107, 0);
INSERT INTO monsters VALUES (102, 'Greater Wyvern', 145, 130, 105, 34, 335, 112, 0);
INSERT INTO monsters VALUES (103, 'Advocate', 148, 132, 108, 35, 350, 117, 0);
INSERT INTO monsters VALUES (104, 'Strong Knight', 150, 135, 110, 35, 365, 122, 0);
INSERT INTO monsters VALUES (105, 'Liche', 150, 135, 110, 35, 380, 127, 0);
INSERT INTO monsters VALUES (106, 'Ultradoomer', 155, 140, 115, 36, 395, 132, 0);
INSERT INTO monsters VALUES (107, 'Fanatic', 160, 140, 115, 36, 410, 137, 0);
INSERT INTO monsters VALUES (108, 'Green Dragon', 160, 140, 115, 36, 425, 142, 0);
INSERT INTO monsters VALUES (109, 'Fiend', 160, 145, 120, 37, 445, 148, 0);
INSERT INTO monsters VALUES (110, 'Greatest Wyvern', 162, 150, 120, 37, 465, 155, 0);
INSERT INTO monsters VALUES (111, 'Lesser Devil', 164, 150, 120, 37, 485, 162, 0);
INSERT INTO monsters VALUES (112, 'Liche Master', 168, 155, 125, 38, 505, 168, 0);
INSERT INTO monsters VALUES (113, 'Zealot', 168, 155, 125, 38, 530, 177, 0);
INSERT INTO monsters VALUES (114, 'Serafiend', 170, 155, 125, 38, 555, 185, 0);
INSERT INTO monsters VALUES (115, 'Pale Knight', 175, 160, 130, 39, 580, 193, 0);
INSERT INTO monsters VALUES (116, 'Blue Dragon', 180, 160, 130, 39, 605, 202, 0);
INSERT INTO monsters VALUES (117, 'Obsessive', 180, 160, 135, 40, 630, 210, 0);
INSERT INTO monsters VALUES (118, 'Devil', 184, 164, 135, 40, 666, 222, 0);
INSERT INTO monsters VALUES (119, 'Liche Prince', 190, 168, 138, 40, 660, 220, 0);
INSERT INTO monsters VALUES (120, 'Cherufiend', 195, 170, 140, 41, 690, 230, 0);
INSERT INTO monsters VALUES (121, 'Red Dragon', 200, 180, 145, 41, 720, 240, 0);
INSERT INTO monsters VALUES (122, 'Greater Devil', 200, 180, 145, 41, 750, 250, 0);
INSERT INTO monsters VALUES (123, 'Renegade', 205, 185, 150, 42, 780, 260, 0);
INSERT INTO monsters VALUES (124, 'Archfiend', 210, 190, 150, 42, 810, 270, 0);
INSERT INTO monsters VALUES (125, 'Liche Lord', 210, 190, 155, 42, 850, 283, 0);
INSERT INTO monsters VALUES (126, 'Greatest Devil', 215, 195, 160, 43, 890, 297, 0);
INSERT INTO monsters VALUES (127, 'Dark Knight', 220, 200, 160, 43, 930, 310, 0);
INSERT INTO monsters VALUES (128, 'Giant', 220, 200, 165, 43, 970, 323, 0);
INSERT INTO monsters VALUES (129, 'Shadow Dragon', 225, 200, 170, 44, 1010, 337, 0);
INSERT INTO monsters VALUES (130, 'Liche King', 225, 205, 170, 44, 1050, 350, 0);
INSERT INTO monsters VALUES (131, 'Incubus', 230, 205, 175, 44, 1100, 367, 1);
INSERT INTO monsters VALUES (132, 'Traitor', 230, 205, 175, 45, 1150, 383, 0);
INSERT INTO monsters VALUES (133, 'Demon', 240, 210, 180, 45, 1200, 400, 0);
INSERT INTO monsters VALUES (134, 'Dark Dragon', 245, 215, 180, 45, 1250, 417, 1);
INSERT INTO monsters VALUES (135, 'Insurgent', 250, 220, 190, 46, 1300, 433, 0);
INSERT INTO monsters VALUES (136, 'Leviathan', 255, 225, 190, 46, 1350, 450, 0);
INSERT INTO monsters VALUES (137, 'Grey Daemon', 260, 230, 190, 46, 1400, 467, 0);
INSERT INTO monsters VALUES (138, 'Succubus', 265, 240, 200, 47, 1460, 487, 1);
INSERT INTO monsters VALUES (139, 'Demon Prince', 270, 240, 200, 47, 1520, 507, 0);
INSERT INTO monsters VALUES (140, 'Black Dragon', 275, 250, 205, 47, 1580, 527, 1);
INSERT INTO monsters VALUES (141, 'Nihilist', 280, 250, 205, 47, 1640, 547, 0);
INSERT INTO monsters VALUES (142, 'Behemoth', 285, 260, 210, 48, 1700, 567, 0);
INSERT INTO monsters VALUES (143, 'Demagogue', 290, 260, 210, 48, 1760, 587, 0);
INSERT INTO monsters VALUES (144, 'Demon Lord', 300, 270, 220, 48, 1820, 607, 0);
INSERT INTO monsters VALUES (145, 'Red Daemon', 310, 280, 230, 48, 1880, 627, 0);
INSERT INTO monsters VALUES (146, 'Colossus', 320, 300, 240, 49, 1940, 647, 0);
INSERT INTO monsters VALUES (147, 'Demon King', 330, 300, 250, 49, 2000, 667, 0);
INSERT INTO monsters VALUES (148, 'Dark Daemon', 340, 320, 260, 49, 2200, 733, 1);
INSERT INTO monsters VALUES (149, 'Titan', 360, 340, 270, 50, 2400, 800, 0);
INSERT INTO monsters VALUES (150, 'Black Daemon', 400, 400, 280, 50, 3000, 1000, 1);
INSERT INTO monsters VALUES (151, 'Lucifuge', 600, 600, 400, 50, 10000, 10000, 2);

-- news (dk install adds the author, a title and the discussion thread)
INSERT INTO news (id, postdate, content) VALUES (1, 1072958400, 'This is the first news post. Please use the admin control panel to add another one and make this one go away.');

-- forum boards (new; structural, loaded by partial setups too)
INSERT INTO forums (id, name, description, position, admin_threads) VALUES (1, 'General', 'Talk about anything.', 1, 0);
INSERT INTO forums (id, name, description, position, admin_threads) VALUES (2, 'News', 'Game news and announcements. Reply to discuss.', 2, 1);

-- spells
INSERT INTO spells VALUES (1, 'Heal', 5, 10, 1);
INSERT INTO spells VALUES (2, 'Revive', 10, 25, 1);
INSERT INTO spells VALUES (3, 'Life', 25, 50, 1);
INSERT INTO spells VALUES (4, 'Breath', 50, 100, 1);
INSERT INTO spells VALUES (5, 'Gaia', 75, 150, 1);
INSERT INTO spells VALUES (6, 'Hurt', 5, 15, 2);
INSERT INTO spells VALUES (7, 'Pain', 12, 35, 2);
INSERT INTO spells VALUES (8, 'Maim', 25, 70, 2);
INSERT INTO spells VALUES (9, 'Rend', 40, 100, 2);
INSERT INTO spells VALUES (10, 'Chaos', 50, 130, 2);
INSERT INTO spells VALUES (11, 'Sleep', 10, 5, 3);
INSERT INTO spells VALUES (12, 'Dream', 30, 9, 3);
INSERT INTO spells VALUES (13, 'Nightmare', 60, 13, 3);
INSERT INTO spells VALUES (14, 'Craze', 10, 10, 4);
INSERT INTO spells VALUES (15, 'Rage', 20, 25, 4);
INSERT INTO spells VALUES (16, 'Fury', 30, 50, 4);
INSERT INTO spells VALUES (17, 'Ward', 10, 10, 5);
INSERT INTO spells VALUES (18, 'Fend', 20, 25, 5);
INSERT INTO spells VALUES (19, 'Barrier', 30, 50, 5);

-- towns
INSERT INTO towns VALUES (1, 'Midworld', 0, 0, 5, 0, 0, '1,2,3,17,18,19,28,29');
INSERT INTO towns VALUES (2, 'Roma', 30, 30, 10, 25, 5, '2,3,4,18,19,29');
INSERT INTO towns VALUES (3, 'Bris', 70, -70, 25, 50, 15, '2,3,4,5,18,19,20,29,30');
INSERT INTO towns VALUES (4, 'Kalle', -100, 100, 40, 100, 30, '5,6,8,10,12,21,22,23,29,30');
INSERT INTO towns VALUES (5, 'Narcissa', -130, -130, 60, 500, 50, '4,7,9,11,13,21,22,23,29,30,31');
INSERT INTO towns VALUES (6, 'Hambry', 170, 170, 90, 1000, 80, '10,11,12,13,14,23,24,30,31');
INSERT INTO towns VALUES (7, 'Gilead', 200, -200, 100, 3000, 110, '12,13,14,15,24,25,26,32');
INSERT INTO towns VALUES (8, 'Endworld', -250, -250, 125, 9000, 160, '16,27,33');
