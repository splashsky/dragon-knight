-- tests/fixtures/seed_v12.sql :: the default game data of schema version 12 (class, spell, item,
-- status and monster ids only, the rest comes from the content sync), as of commit 34f39b7
-- (release 2.3.1). tests/e2e/migrate.sh loads it into databases built from schema_v12.sql.
-- Do not edit.

-- Default game data, ported 1:1 from the original install.php ("Complete Setup").
-- Differences: control.verifyemail = 0 (PLAN.md) and no difficulty names/modifiers
-- (difficulty levels were removed); news.postdate is unix time (2004-01-01 12:00:00 UTC).
-- The original levels table and class names are content files now (app/content/classes/;
-- experience, TP and the milestone HP are formulas in app/lib/leveling.lua), and so are
-- the spells (app/content/spells/) and the items and drops (app/content/items/).
-- Dragon's -> Dragon''s (SQL quoting).

-- classes: the original classes keep their ids; the content sync (end of dk install)
-- fills in the rest from app/content/classes/*.lua. Loaded by partial setups too.
INSERT INTO classes (id, key, name) VALUES (1, 'mage', 'Mage');
INSERT INTO classes (id, key, name) VALUES (2, 'warrior', 'Warrior');
INSERT INTO classes (id, key, name) VALUES (3, 'paladin', 'Paladin');

-- control
INSERT INTO control (id, gamename, gamesize, gameopen, gameurl, adminemail, forumtype, forumaddress, compression, verifyemail, shownews, showbabble, showonline) VALUES (1, 'Dragon Knight', 250, 1, '', '', 1, '', 1, 0, 1, 1, 1);

-- items: the original items keep ids 1-33, the original drops are 34-65, then the
-- consumables; the content sync (end of dk install) fills in the rest from
-- app/content/items/*.lua. Loaded by partial setups too.
INSERT INTO items (id, key, name) VALUES (1, 'stick', 'Stick');
INSERT INTO items (id, key, name) VALUES (2, 'branch', 'Branch');
INSERT INTO items (id, key, name) VALUES (3, 'club', 'Club');
INSERT INTO items (id, key, name) VALUES (4, 'dagger', 'Dagger');
INSERT INTO items (id, key, name) VALUES (5, 'hatchet', 'Hatchet');
INSERT INTO items (id, key, name) VALUES (6, 'axe', 'Axe');
INSERT INTO items (id, key, name) VALUES (7, 'brand', 'Brand');
INSERT INTO items (id, key, name) VALUES (8, 'poleaxe', 'Poleaxe');
INSERT INTO items (id, key, name) VALUES (9, 'broadsword', 'Broadsword');
INSERT INTO items (id, key, name) VALUES (10, 'battle_axe', 'Battle Axe');
INSERT INTO items (id, key, name) VALUES (11, 'claymore', 'Claymore');
INSERT INTO items (id, key, name) VALUES (12, 'dark_axe', 'Dark Axe');
INSERT INTO items (id, key, name) VALUES (13, 'dark_sword', 'Dark Sword');
INSERT INTO items (id, key, name) VALUES (14, 'bright_sword', 'Bright Sword');
INSERT INTO items (id, key, name) VALUES (15, 'magic_sword', 'Magic Sword');
INSERT INTO items (id, key, name) VALUES (16, 'destiny_blade', 'Destiny Blade');
INSERT INTO items (id, key, name) VALUES (17, 'skivvies', 'Skivvies');
INSERT INTO items (id, key, name) VALUES (18, 'clothes', 'Clothes');
INSERT INTO items (id, key, name) VALUES (19, 'leather_armor', 'Leather Armor');
INSERT INTO items (id, key, name) VALUES (20, 'hard_leather_armor', 'Hard Leather Armor');
INSERT INTO items (id, key, name) VALUES (21, 'chain_mail', 'Chain Mail');
INSERT INTO items (id, key, name) VALUES (22, 'bronze_plate', 'Bronze Plate');
INSERT INTO items (id, key, name) VALUES (23, 'iron_plate', 'Iron Plate');
INSERT INTO items (id, key, name) VALUES (24, 'magic_armor', 'Magic Armor');
INSERT INTO items (id, key, name) VALUES (25, 'dark_armor', 'Dark Armor');
INSERT INTO items (id, key, name) VALUES (26, 'bright_armor', 'Bright Armor');
INSERT INTO items (id, key, name) VALUES (27, 'destiny_raiment', 'Destiny Raiment');
INSERT INTO items (id, key, name) VALUES (28, 'reed_shield', 'Reed Shield');
INSERT INTO items (id, key, name) VALUES (29, 'buckler', 'Buckler');
INSERT INTO items (id, key, name) VALUES (30, 'small_shield', 'Small Shield');
INSERT INTO items (id, key, name) VALUES (31, 'large_shield', 'Large Shield');
INSERT INTO items (id, key, name) VALUES (32, 'silver_shield', 'Silver Shield');
INSERT INTO items (id, key, name) VALUES (33, 'destiny_aegis', 'Destiny Aegis');
INSERT INTO items (id, key, name) VALUES (34, 'life_pebble', 'Life Pebble');
INSERT INTO items (id, key, name) VALUES (35, 'life_stone', 'Life Stone');
INSERT INTO items (id, key, name) VALUES (36, 'life_rock', 'Life Rock');
INSERT INTO items (id, key, name) VALUES (37, 'magic_pebble', 'Magic Pebble');
INSERT INTO items (id, key, name) VALUES (38, 'magic_stone', 'Magic Stone');
INSERT INTO items (id, key, name) VALUES (39, 'magic_rock', 'Magic Rock');
INSERT INTO items (id, key, name) VALUES (40, 'dragons_scale', 'Dragon''s Scale');
INSERT INTO items (id, key, name) VALUES (41, 'dragons_plate', 'Dragon''s Plate');
INSERT INTO items (id, key, name) VALUES (42, 'dragons_claw', 'Dragon''s Claw');
INSERT INTO items (id, key, name) VALUES (43, 'dragons_tooth', 'Dragon''s Tooth');
INSERT INTO items (id, key, name) VALUES (44, 'dragons_tear', 'Dragon''s Tear');
INSERT INTO items (id, key, name) VALUES (45, 'dragons_wing', 'Dragon''s Wing');
INSERT INTO items (id, key, name) VALUES (46, 'demons_sin', 'Demon''s Sin');
INSERT INTO items (id, key, name) VALUES (47, 'demons_fall', 'Demon''s Fall');
INSERT INTO items (id, key, name) VALUES (48, 'demons_lie', 'Demon''s Lie');
INSERT INTO items (id, key, name) VALUES (49, 'demons_hate', 'Demon''s Hate');
INSERT INTO items (id, key, name) VALUES (50, 'angels_joy', 'Angel''s Joy');
INSERT INTO items (id, key, name) VALUES (51, 'angels_rise', 'Angel''s Rise');
INSERT INTO items (id, key, name) VALUES (52, 'angels_truth', 'Angel''s Truth');
INSERT INTO items (id, key, name) VALUES (53, 'angels_love', 'Angel''s Love');
INSERT INTO items (id, key, name) VALUES (54, 'seraphs_joy', 'Seraph''s Joy');
INSERT INTO items (id, key, name) VALUES (55, 'seraphs_rise', 'Seraph''s Rise');
INSERT INTO items (id, key, name) VALUES (56, 'seraphs_truth', 'Seraph''s Truth');
INSERT INTO items (id, key, name) VALUES (57, 'seraphs_love', 'Seraph''s Love');
INSERT INTO items (id, key, name) VALUES (58, 'ruby', 'Ruby');
INSERT INTO items (id, key, name) VALUES (59, 'pearl', 'Pearl');
INSERT INTO items (id, key, name) VALUES (60, 'emerald', 'Emerald');
INSERT INTO items (id, key, name) VALUES (61, 'topaz', 'Topaz');
INSERT INTO items (id, key, name) VALUES (62, 'obsidian', 'Obsidian');
INSERT INTO items (id, key, name) VALUES (63, 'diamond', 'Diamond');
INSERT INTO items (id, key, name) VALUES (64, 'memory_drop', 'Memory Drop');
INSERT INTO items (id, key, name) VALUES (65, 'fortune_drop', 'Fortune Drop');
INSERT INTO items (id, key, name) VALUES (66, 'herb', 'Herb');
INSERT INTO items (id, key, name) VALUES (67, 'potion', 'Potion');
INSERT INTO items (id, key, name) VALUES (68, 'ether', 'Ether');

-- monsters: the original monsters keep ids 1-151; the content sync (end of dk install) fills
-- in the rest from app/content/monsters/*.lua. Loaded by partial setups too.
INSERT INTO monsters (id, key, name) VALUES (1, 'blue_slime', 'Blue Slime');
INSERT INTO monsters (id, key, name) VALUES (2, 'red_slime', 'Red Slime');
INSERT INTO monsters (id, key, name) VALUES (3, 'critter', 'Critter');
INSERT INTO monsters (id, key, name) VALUES (4, 'creature', 'Creature');
INSERT INTO monsters (id, key, name) VALUES (5, 'shadow', 'Shadow');
INSERT INTO monsters (id, key, name) VALUES (6, 'drake', 'Drake');
INSERT INTO monsters (id, key, name) VALUES (7, 'shade', 'Shade');
INSERT INTO monsters (id, key, name) VALUES (8, 'drakelor', 'Drakelor');
INSERT INTO monsters (id, key, name) VALUES (9, 'silver_slime', 'Silver Slime');
INSERT INTO monsters (id, key, name) VALUES (10, 'scamp', 'Scamp');
INSERT INTO monsters (id, key, name) VALUES (11, 'raven', 'Raven');
INSERT INTO monsters (id, key, name) VALUES (12, 'scorpion', 'Scorpion');
INSERT INTO monsters (id, key, name) VALUES (13, 'illusion', 'Illusion');
INSERT INTO monsters (id, key, name) VALUES (14, 'nightshade', 'Nightshade');
INSERT INTO monsters (id, key, name) VALUES (15, 'drakemal', 'Drakemal');
INSERT INTO monsters (id, key, name) VALUES (16, 'shadow_raven', 'Shadow Raven');
INSERT INTO monsters (id, key, name) VALUES (17, 'ghost', 'Ghost');
INSERT INTO monsters (id, key, name) VALUES (18, 'frost_raven', 'Frost Raven');
INSERT INTO monsters (id, key, name) VALUES (19, 'rogue_scorpion', 'Rogue Scorpion');
INSERT INTO monsters (id, key, name) VALUES (20, 'ghoul', 'Ghoul');
INSERT INTO monsters (id, key, name) VALUES (21, 'magician', 'Magician');
INSERT INTO monsters (id, key, name) VALUES (22, 'rogue', 'Rogue');
INSERT INTO monsters (id, key, name) VALUES (23, 'drakefin', 'Drakefin');
INSERT INTO monsters (id, key, name) VALUES (24, 'shimmer', 'Shimmer');
INSERT INTO monsters (id, key, name) VALUES (25, 'fire_raven', 'Fire Raven');
INSERT INTO monsters (id, key, name) VALUES (26, 'dybbuk', 'Dybbuk');
INSERT INTO monsters (id, key, name) VALUES (27, 'knave', 'Knave');
INSERT INTO monsters (id, key, name) VALUES (28, 'goblin', 'Goblin');
INSERT INTO monsters (id, key, name) VALUES (29, 'skeleton', 'Skeleton');
INSERT INTO monsters (id, key, name) VALUES (30, 'dark_slime', 'Dark Slime');
INSERT INTO monsters (id, key, name) VALUES (31, 'silver_scorpion', 'Silver Scorpion');
INSERT INTO monsters (id, key, name) VALUES (32, 'mirage', 'Mirage');
INSERT INTO monsters (id, key, name) VALUES (33, 'sorceror', 'Sorceror');
INSERT INTO monsters (id, key, name) VALUES (34, 'imp', 'Imp');
INSERT INTO monsters (id, key, name) VALUES (35, 'nymph', 'Nymph');
INSERT INTO monsters (id, key, name) VALUES (36, 'scoundrel', 'Scoundrel');
INSERT INTO monsters (id, key, name) VALUES (37, 'megaskeleton', 'Megaskeleton');
INSERT INTO monsters (id, key, name) VALUES (38, 'grey_wolf', 'Grey Wolf');
INSERT INTO monsters (id, key, name) VALUES (39, 'phantom', 'Phantom');
INSERT INTO monsters (id, key, name) VALUES (40, 'specter', 'Specter');
INSERT INTO monsters (id, key, name) VALUES (41, 'dark_scorpion', 'Dark Scorpion');
INSERT INTO monsters (id, key, name) VALUES (42, 'warlock', 'Warlock');
INSERT INTO monsters (id, key, name) VALUES (43, 'orc', 'Orc');
INSERT INTO monsters (id, key, name) VALUES (44, 'sylph', 'Sylph');
INSERT INTO monsters (id, key, name) VALUES (45, 'wraith', 'Wraith');
INSERT INTO monsters (id, key, name) VALUES (46, 'hellion', 'Hellion');
INSERT INTO monsters (id, key, name) VALUES (47, 'bandit', 'Bandit');
INSERT INTO monsters (id, key, name) VALUES (48, 'ultraskeleton', 'Ultraskeleton');
INSERT INTO monsters (id, key, name) VALUES (49, 'dark_wolf', 'Dark Wolf');
INSERT INTO monsters (id, key, name) VALUES (50, 'troll', 'Troll');
INSERT INTO monsters (id, key, name) VALUES (51, 'werewolf', 'Werewolf');
INSERT INTO monsters (id, key, name) VALUES (52, 'hellcat', 'Hellcat');
INSERT INTO monsters (id, key, name) VALUES (53, 'spirit', 'Spirit');
INSERT INTO monsters (id, key, name) VALUES (54, 'nisse', 'Nisse');
INSERT INTO monsters (id, key, name) VALUES (55, 'dawk', 'Dawk');
INSERT INTO monsters (id, key, name) VALUES (56, 'figment', 'Figment');
INSERT INTO monsters (id, key, name) VALUES (57, 'hellhound', 'Hellhound');
INSERT INTO monsters (id, key, name) VALUES (58, 'wizard', 'Wizard');
INSERT INTO monsters (id, key, name) VALUES (59, 'uruk', 'Uruk');
INSERT INTO monsters (id, key, name) VALUES (60, 'siren', 'Siren');
INSERT INTO monsters (id, key, name) VALUES (61, 'megawraith', 'Megawraith');
INSERT INTO monsters (id, key, name) VALUES (62, 'dawkin', 'Dawkin');
INSERT INTO monsters (id, key, name) VALUES (63, 'grey_bear', 'Grey Bear');
INSERT INTO monsters (id, key, name) VALUES (64, 'haunt', 'Haunt');
INSERT INTO monsters (id, key, name) VALUES (65, 'hellbeast', 'Hellbeast');
INSERT INTO monsters (id, key, name) VALUES (66, 'fear', 'Fear');
INSERT INTO monsters (id, key, name) VALUES (67, 'beast', 'Beast');
INSERT INTO monsters (id, key, name) VALUES (68, 'ogre', 'Ogre');
INSERT INTO monsters (id, key, name) VALUES (69, 'dark_bear', 'Dark Bear');
INSERT INTO monsters (id, key, name) VALUES (70, 'fire', 'Fire');
INSERT INTO monsters (id, key, name) VALUES (71, 'polgergeist', 'Polgergeist');
INSERT INTO monsters (id, key, name) VALUES (72, 'fright', 'Fright');
INSERT INTO monsters (id, key, name) VALUES (73, 'lycan', 'Lycan');
INSERT INTO monsters (id, key, name) VALUES (74, 'terra_elemental', 'Terra Elemental');
INSERT INTO monsters (id, key, name) VALUES (75, 'necromancer', 'Necromancer');
INSERT INTO monsters (id, key, name) VALUES (76, 'ultrawraith', 'Ultrawraith');
INSERT INTO monsters (id, key, name) VALUES (77, 'dawkor', 'Dawkor');
INSERT INTO monsters (id, key, name) VALUES (78, 'werebear', 'Werebear');
INSERT INTO monsters (id, key, name) VALUES (79, 'brute', 'Brute');
INSERT INTO monsters (id, key, name) VALUES (80, 'large_beast', 'Large Beast');
INSERT INTO monsters (id, key, name) VALUES (81, 'horror', 'Horror');
INSERT INTO monsters (id, key, name) VALUES (82, 'flame', 'Flame');
INSERT INTO monsters (id, key, name) VALUES (83, 'lycanthor', 'Lycanthor');
INSERT INTO monsters (id, key, name) VALUES (84, 'wyrm', 'Wyrm');
INSERT INTO monsters (id, key, name) VALUES (85, 'aero_elemental', 'Aero Elemental');
INSERT INTO monsters (id, key, name) VALUES (86, 'dawkare', 'Dawkare');
INSERT INTO monsters (id, key, name) VALUES (87, 'large_brute', 'Large Brute');
INSERT INTO monsters (id, key, name) VALUES (88, 'frost_wyrm', 'Frost Wyrm');
INSERT INTO monsters (id, key, name) VALUES (89, 'knight', 'Knight');
INSERT INTO monsters (id, key, name) VALUES (90, 'lycanthra', 'Lycanthra');
INSERT INTO monsters (id, key, name) VALUES (91, 'terror', 'Terror');
INSERT INTO monsters (id, key, name) VALUES (92, 'blaze', 'Blaze');
INSERT INTO monsters (id, key, name) VALUES (93, 'aqua_elemental', 'Aqua Elemental');
INSERT INTO monsters (id, key, name) VALUES (94, 'fire_wyrm', 'Fire Wyrm');
INSERT INTO monsters (id, key, name) VALUES (95, 'lesser_wyvern', 'Lesser Wyvern');
INSERT INTO monsters (id, key, name) VALUES (96, 'doomer', 'Doomer');
INSERT INTO monsters (id, key, name) VALUES (97, 'armor_knight', 'Armor Knight');
INSERT INTO monsters (id, key, name) VALUES (98, 'wyvern', 'Wyvern');
INSERT INTO monsters (id, key, name) VALUES (99, 'nightmare', 'Nightmare');
INSERT INTO monsters (id, key, name) VALUES (100, 'fira_elemental', 'Fira Elemental');
INSERT INTO monsters (id, key, name) VALUES (101, 'megadoomer', 'Megadoomer');
INSERT INTO monsters (id, key, name) VALUES (102, 'greater_wyvern', 'Greater Wyvern');
INSERT INTO monsters (id, key, name) VALUES (103, 'advocate', 'Advocate');
INSERT INTO monsters (id, key, name) VALUES (104, 'strong_knight', 'Strong Knight');
INSERT INTO monsters (id, key, name) VALUES (105, 'liche', 'Liche');
INSERT INTO monsters (id, key, name) VALUES (106, 'ultradoomer', 'Ultradoomer');
INSERT INTO monsters (id, key, name) VALUES (107, 'fanatic', 'Fanatic');
INSERT INTO monsters (id, key, name) VALUES (108, 'green_dragon', 'Green Dragon');
INSERT INTO monsters (id, key, name) VALUES (109, 'fiend', 'Fiend');
INSERT INTO monsters (id, key, name) VALUES (110, 'greatest_wyvern', 'Greatest Wyvern');
INSERT INTO monsters (id, key, name) VALUES (111, 'lesser_devil', 'Lesser Devil');
INSERT INTO monsters (id, key, name) VALUES (112, 'liche_master', 'Liche Master');
INSERT INTO monsters (id, key, name) VALUES (113, 'zealot', 'Zealot');
INSERT INTO monsters (id, key, name) VALUES (114, 'serafiend', 'Serafiend');
INSERT INTO monsters (id, key, name) VALUES (115, 'pale_knight', 'Pale Knight');
INSERT INTO monsters (id, key, name) VALUES (116, 'blue_dragon', 'Blue Dragon');
INSERT INTO monsters (id, key, name) VALUES (117, 'obsessive', 'Obsessive');
INSERT INTO monsters (id, key, name) VALUES (118, 'devil', 'Devil');
INSERT INTO monsters (id, key, name) VALUES (119, 'liche_prince', 'Liche Prince');
INSERT INTO monsters (id, key, name) VALUES (120, 'cherufiend', 'Cherufiend');
INSERT INTO monsters (id, key, name) VALUES (121, 'red_dragon', 'Red Dragon');
INSERT INTO monsters (id, key, name) VALUES (122, 'greater_devil', 'Greater Devil');
INSERT INTO monsters (id, key, name) VALUES (123, 'renegade', 'Renegade');
INSERT INTO monsters (id, key, name) VALUES (124, 'archfiend', 'Archfiend');
INSERT INTO monsters (id, key, name) VALUES (125, 'liche_lord', 'Liche Lord');
INSERT INTO monsters (id, key, name) VALUES (126, 'greatest_devil', 'Greatest Devil');
INSERT INTO monsters (id, key, name) VALUES (127, 'dark_knight', 'Dark Knight');
INSERT INTO monsters (id, key, name) VALUES (128, 'giant', 'Giant');
INSERT INTO monsters (id, key, name) VALUES (129, 'shadow_dragon', 'Shadow Dragon');
INSERT INTO monsters (id, key, name) VALUES (130, 'liche_king', 'Liche King');
INSERT INTO monsters (id, key, name) VALUES (131, 'incubus', 'Incubus');
INSERT INTO monsters (id, key, name) VALUES (132, 'traitor', 'Traitor');
INSERT INTO monsters (id, key, name) VALUES (133, 'demon', 'Demon');
INSERT INTO monsters (id, key, name) VALUES (134, 'dark_dragon', 'Dark Dragon');
INSERT INTO monsters (id, key, name) VALUES (135, 'insurgent', 'Insurgent');
INSERT INTO monsters (id, key, name) VALUES (136, 'leviathan', 'Leviathan');
INSERT INTO monsters (id, key, name) VALUES (137, 'grey_daemon', 'Grey Daemon');
INSERT INTO monsters (id, key, name) VALUES (138, 'succubus', 'Succubus');
INSERT INTO monsters (id, key, name) VALUES (139, 'demon_prince', 'Demon Prince');
INSERT INTO monsters (id, key, name) VALUES (140, 'black_dragon', 'Black Dragon');
INSERT INTO monsters (id, key, name) VALUES (141, 'nihilist', 'Nihilist');
INSERT INTO monsters (id, key, name) VALUES (142, 'behemoth', 'Behemoth');
INSERT INTO monsters (id, key, name) VALUES (143, 'demagogue', 'Demagogue');
INSERT INTO monsters (id, key, name) VALUES (144, 'demon_lord', 'Demon Lord');
INSERT INTO monsters (id, key, name) VALUES (145, 'red_daemon', 'Red Daemon');
INSERT INTO monsters (id, key, name) VALUES (146, 'colossus', 'Colossus');
INSERT INTO monsters (id, key, name) VALUES (147, 'demon_king', 'Demon King');
INSERT INTO monsters (id, key, name) VALUES (148, 'dark_daemon', 'Dark Daemon');
INSERT INTO monsters (id, key, name) VALUES (149, 'titan', 'Titan');
INSERT INTO monsters (id, key, name) VALUES (150, 'black_daemon', 'Black Daemon');
INSERT INTO monsters (id, key, name) VALUES (151, 'lucifuge', 'Lucifuge');

-- news (dk install adds the author, a title and the discussion thread)
INSERT INTO news (id, postdate, content) VALUES (1, 1072958400, 'This is the first news post. Please use the admin control panel to add another one and make this one go away.');

-- forum boards (new; structural, loaded by partial setups too)
INSERT INTO forums (id, name, description, position, admin_threads) VALUES (1, 'General', 'Talk about anything.', 1, 0);
INSERT INTO forums (id, name, description, position, admin_threads) VALUES (2, 'News', 'Game news and announcements. Reply to discuss.', 2, 1);

-- statuses: the original game's sleep and damage/defense buffs keep ids 1-3 (schema
-- version 8 moved fights in progress onto them); the content sync fills in the rest from
-- app/content/statuses/*.lua. Loaded by partial setups too.
INSERT INTO statuses (id, key, name) VALUES (1, 'sleep', 'Asleep');
INSERT INTO statuses (id, key, name) VALUES (2, 'uber_damage', 'Damage Up');
INSERT INTO statuses (id, key, name) VALUES (3, 'uber_defense', 'Defense Up');

-- spells: the original spells keep their ids; the content sync (end of dk install) fills
-- in the rest from app/content/spells/*.lua. Loaded by partial setups too.
INSERT INTO spells (id, key, name) VALUES (1, 'heal', 'Heal');
INSERT INTO spells (id, key, name) VALUES (2, 'revive', 'Revive');
INSERT INTO spells (id, key, name) VALUES (3, 'life', 'Life');
INSERT INTO spells (id, key, name) VALUES (4, 'breath', 'Breath');
INSERT INTO spells (id, key, name) VALUES (5, 'gaia', 'Gaia');
INSERT INTO spells (id, key, name) VALUES (6, 'hurt', 'Hurt');
INSERT INTO spells (id, key, name) VALUES (7, 'pain', 'Pain');
INSERT INTO spells (id, key, name) VALUES (8, 'maim', 'Maim');
INSERT INTO spells (id, key, name) VALUES (9, 'rend', 'Rend');
INSERT INTO spells (id, key, name) VALUES (10, 'chaos', 'Chaos');
INSERT INTO spells (id, key, name) VALUES (11, 'sleep', 'Sleep');
INSERT INTO spells (id, key, name) VALUES (12, 'dream', 'Dream');
INSERT INTO spells (id, key, name) VALUES (13, 'nightmare', 'Nightmare');
INSERT INTO spells (id, key, name) VALUES (14, 'craze', 'Craze');
INSERT INTO spells (id, key, name) VALUES (15, 'rage', 'Rage');
INSERT INTO spells (id, key, name) VALUES (16, 'fury', 'Fury');
INSERT INTO spells (id, key, name) VALUES (17, 'ward', 'Ward');
INSERT INTO spells (id, key, name) VALUES (18, 'fend', 'Fend');
INSERT INTO spells (id, key, name) VALUES (19, 'barrier', 'Barrier');

-- towns (the items their shops sell: town_items)
INSERT INTO towns (id, name, latitude, longitude, innprice, mapprice, travelpoints) VALUES (1, 'Midworld', 0, 0, 5, 0, 0);
INSERT INTO towns (id, name, latitude, longitude, innprice, mapprice, travelpoints) VALUES (2, 'Roma', 30, 30, 10, 25, 5);
INSERT INTO towns (id, name, latitude, longitude, innprice, mapprice, travelpoints) VALUES (3, 'Bris', 70, -70, 25, 50, 15);
INSERT INTO towns (id, name, latitude, longitude, innprice, mapprice, travelpoints) VALUES (4, 'Kalle', -100, 100, 40, 100, 30);
INSERT INTO towns (id, name, latitude, longitude, innprice, mapprice, travelpoints) VALUES (5, 'Narcissa', -130, -130, 60, 500, 50);
INSERT INTO towns (id, name, latitude, longitude, innprice, mapprice, travelpoints) VALUES (6, 'Hambry', 170, 170, 90, 1000, 80);
INSERT INTO towns (id, name, latitude, longitude, innprice, mapprice, travelpoints) VALUES (7, 'Gilead', 200, -200, 100, 3000, 110);
INSERT INTO towns (id, name, latitude, longitude, innprice, mapprice, travelpoints) VALUES (8, 'Endworld', -250, -250, 125, 9000, 160);

-- town_items: the original items lists (Bris: its full list, fixed), plus Herbs everywhere
-- and Potions and Ethers from Roma on (new in 2.1)
INSERT INTO town_items (town_id, item_id) VALUES (1, 1);
INSERT INTO town_items (town_id, item_id) VALUES (1, 2);
INSERT INTO town_items (town_id, item_id) VALUES (1, 3);
INSERT INTO town_items (town_id, item_id) VALUES (1, 17);
INSERT INTO town_items (town_id, item_id) VALUES (1, 18);
INSERT INTO town_items (town_id, item_id) VALUES (1, 19);
INSERT INTO town_items (town_id, item_id) VALUES (1, 28);
INSERT INTO town_items (town_id, item_id) VALUES (1, 29);
INSERT INTO town_items (town_id, item_id) VALUES (1, 66);
INSERT INTO town_items (town_id, item_id) VALUES (2, 2);
INSERT INTO town_items (town_id, item_id) VALUES (2, 3);
INSERT INTO town_items (town_id, item_id) VALUES (2, 4);
INSERT INTO town_items (town_id, item_id) VALUES (2, 18);
INSERT INTO town_items (town_id, item_id) VALUES (2, 19);
INSERT INTO town_items (town_id, item_id) VALUES (2, 29);
INSERT INTO town_items (town_id, item_id) VALUES (2, 66);
INSERT INTO town_items (town_id, item_id) VALUES (2, 67);
INSERT INTO town_items (town_id, item_id) VALUES (2, 68);
INSERT INTO town_items (town_id, item_id) VALUES (3, 2);
INSERT INTO town_items (town_id, item_id) VALUES (3, 3);
INSERT INTO town_items (town_id, item_id) VALUES (3, 4);
INSERT INTO town_items (town_id, item_id) VALUES (3, 5);
INSERT INTO town_items (town_id, item_id) VALUES (3, 18);
INSERT INTO town_items (town_id, item_id) VALUES (3, 19);
INSERT INTO town_items (town_id, item_id) VALUES (3, 20);
INSERT INTO town_items (town_id, item_id) VALUES (3, 29);
INSERT INTO town_items (town_id, item_id) VALUES (3, 30);
INSERT INTO town_items (town_id, item_id) VALUES (3, 66);
INSERT INTO town_items (town_id, item_id) VALUES (3, 67);
INSERT INTO town_items (town_id, item_id) VALUES (3, 68);
INSERT INTO town_items (town_id, item_id) VALUES (4, 5);
INSERT INTO town_items (town_id, item_id) VALUES (4, 6);
INSERT INTO town_items (town_id, item_id) VALUES (4, 8);
INSERT INTO town_items (town_id, item_id) VALUES (4, 10);
INSERT INTO town_items (town_id, item_id) VALUES (4, 12);
INSERT INTO town_items (town_id, item_id) VALUES (4, 21);
INSERT INTO town_items (town_id, item_id) VALUES (4, 22);
INSERT INTO town_items (town_id, item_id) VALUES (4, 23);
INSERT INTO town_items (town_id, item_id) VALUES (4, 29);
INSERT INTO town_items (town_id, item_id) VALUES (4, 30);
INSERT INTO town_items (town_id, item_id) VALUES (4, 66);
INSERT INTO town_items (town_id, item_id) VALUES (4, 67);
INSERT INTO town_items (town_id, item_id) VALUES (4, 68);
INSERT INTO town_items (town_id, item_id) VALUES (5, 4);
INSERT INTO town_items (town_id, item_id) VALUES (5, 7);
INSERT INTO town_items (town_id, item_id) VALUES (5, 9);
INSERT INTO town_items (town_id, item_id) VALUES (5, 11);
INSERT INTO town_items (town_id, item_id) VALUES (5, 13);
INSERT INTO town_items (town_id, item_id) VALUES (5, 21);
INSERT INTO town_items (town_id, item_id) VALUES (5, 22);
INSERT INTO town_items (town_id, item_id) VALUES (5, 23);
INSERT INTO town_items (town_id, item_id) VALUES (5, 29);
INSERT INTO town_items (town_id, item_id) VALUES (5, 30);
INSERT INTO town_items (town_id, item_id) VALUES (5, 31);
INSERT INTO town_items (town_id, item_id) VALUES (5, 66);
INSERT INTO town_items (town_id, item_id) VALUES (5, 67);
INSERT INTO town_items (town_id, item_id) VALUES (5, 68);
INSERT INTO town_items (town_id, item_id) VALUES (6, 10);
INSERT INTO town_items (town_id, item_id) VALUES (6, 11);
INSERT INTO town_items (town_id, item_id) VALUES (6, 12);
INSERT INTO town_items (town_id, item_id) VALUES (6, 13);
INSERT INTO town_items (town_id, item_id) VALUES (6, 14);
INSERT INTO town_items (town_id, item_id) VALUES (6, 23);
INSERT INTO town_items (town_id, item_id) VALUES (6, 24);
INSERT INTO town_items (town_id, item_id) VALUES (6, 30);
INSERT INTO town_items (town_id, item_id) VALUES (6, 31);
INSERT INTO town_items (town_id, item_id) VALUES (6, 66);
INSERT INTO town_items (town_id, item_id) VALUES (6, 67);
INSERT INTO town_items (town_id, item_id) VALUES (6, 68);
INSERT INTO town_items (town_id, item_id) VALUES (7, 12);
INSERT INTO town_items (town_id, item_id) VALUES (7, 13);
INSERT INTO town_items (town_id, item_id) VALUES (7, 14);
INSERT INTO town_items (town_id, item_id) VALUES (7, 15);
INSERT INTO town_items (town_id, item_id) VALUES (7, 24);
INSERT INTO town_items (town_id, item_id) VALUES (7, 25);
INSERT INTO town_items (town_id, item_id) VALUES (7, 26);
INSERT INTO town_items (town_id, item_id) VALUES (7, 32);
INSERT INTO town_items (town_id, item_id) VALUES (7, 66);
INSERT INTO town_items (town_id, item_id) VALUES (7, 67);
INSERT INTO town_items (town_id, item_id) VALUES (7, 68);
INSERT INTO town_items (town_id, item_id) VALUES (8, 16);
INSERT INTO town_items (town_id, item_id) VALUES (8, 27);
INSERT INTO town_items (town_id, item_id) VALUES (8, 33);
INSERT INTO town_items (town_id, item_id) VALUES (8, 66);
INSERT INTO town_items (town_id, item_id) VALUES (8, 67);
INSERT INTO town_items (town_id, item_id) VALUES (8, 68);
