-- migrations.lua :: database schema versions.
--
-- app/sql/schema.sql is always the latest schema, and `dk install` stamps new databases
-- with VERSION (PRAGMA user_version). Databases from before versioning are version 0.
-- `dk migrate` (app/cli/migrate.lua) runs the missing STEPS in order, all in the CLI's
-- one transaction, and stamps each version. main.lua answers 503 while the database's
-- version differs from VERSION.
--
-- To change the schema: edit schema.sql, append a step below that does the same to an
-- existing database (plus any data backfill), and extend tests/e2e/migrate.sh. A step
-- runs against the schema of its own time: use SQL here, not app modules that query
-- tables (those follow the latest schema). Pure helpers are fine. A step may also have an
-- `after_sync` function: `dk migrate` runs it after the content sync that ends the
-- migration (in the same transaction), with the latest schema and content in place.
local migrations = {}

-- 1: forum boards (forums table, forum.board/author_id; the table is rebuilt because
-- SQLite can't ADD a REFERENCES column with a non-NULL default while foreign keys are
-- on), news title/author_id/thread_id, and a News-board thread for every post.
local function v1_boards_and_news_threads()
	local db = dk.db
	local seq = db:value("SELECT seq FROM sqlite_sequence WHERE name = 'forum'")
	db:exec_script([[
CREATE TABLE forums (
	id             INTEGER PRIMARY KEY,
	name           TEXT    NOT NULL,
	description    TEXT    NOT NULL DEFAULT '',
	position       INTEGER NOT NULL DEFAULT 0,
	admin_threads  INTEGER NOT NULL DEFAULT 0
);
INSERT INTO forums (id, name, description, position, admin_threads) VALUES (1, 'General', 'Talk about anything.', 1, 0);
INSERT INTO forums (id, name, description, position, admin_threads) VALUES (2, 'News', 'Game news and announcements. Reply to discuss.', 2, 1);

CREATE TABLE forum_new (
	id           INTEGER PRIMARY KEY AUTOINCREMENT,
	postdate     INTEGER NOT NULL DEFAULT 0,
	newpostdate  INTEGER NOT NULL DEFAULT 0,
	author       TEXT    NOT NULL DEFAULT '',
	parent       INTEGER NOT NULL DEFAULT 0,
	replies      INTEGER NOT NULL DEFAULT 0,
	title        TEXT    NOT NULL DEFAULT '',
	content      TEXT    NOT NULL DEFAULT '',
	board        INTEGER NOT NULL DEFAULT 1 REFERENCES forums (id),
	author_id    INTEGER REFERENCES users (id) ON DELETE SET NULL
);
INSERT INTO forum_new (id, postdate, newpostdate, author, parent, replies, title, content, board, author_id)
	SELECT id, postdate, newpostdate, author, parent, replies, title, content, 1,
		(SELECT min(u.id) FROM users u WHERE u.charname = forum.author)
	FROM forum;
DROP TABLE forum;
ALTER TABLE forum_new RENAME TO forum;
CREATE INDEX forum_parent ON forum (parent, newpostdate);
CREATE INDEX forum_board ON forum (board, parent, newpostdate);

ALTER TABLE news ADD COLUMN title TEXT NOT NULL DEFAULT '';
ALTER TABLE news ADD COLUMN author_id INTEGER REFERENCES users (id) ON DELETE SET NULL;
ALTER TABLE news ADD COLUMN thread_id INTEGER REFERENCES forum (id) ON DELETE SET NULL;
]])
	-- keep AUTOINCREMENT's high-water mark (ids of deleted posts are never reused)
	if seq then
		local now_seq = db:value("SELECT seq FROM sqlite_sequence WHERE name = 'forum'") or 0
		db:exec("DELETE FROM sqlite_sequence WHERE name = 'forum'")
		db:exec("INSERT INTO sqlite_sequence (name, seq) VALUES ('forum', ?)", math.max(seq, now_seq))
	end

	local default_title = require("lib.news").default_title
	local admin = db:first("SELECT id, charname FROM users WHERE authlevel = 1 ORDER BY id LIMIT 1")
	for _, p in ipairs(db:query("SELECT id, postdate, content FROM news ORDER BY id")) do
		local title = default_title(p.content)
		local _, thread = db:exec(
			"INSERT INTO forum (board, postdate, newpostdate, author, author_id, parent, replies, " ..
			"title, content) VALUES (2, ?, ?, ?, ?, 0, 0, ?, ?)",
			p.postdate, p.postdate, admin and admin.charname or "Unknown", admin and admin.id,
			title, p.content)
		db:exec("UPDATE news SET title = ?, author_id = ?, thread_id = ? WHERE id = ?",
						title, admin and admin.id, thread, p.id)
	end
end

-- 2: no more difficulty levels (everyone plays at the original Easy, which never scaled
-- anything). No index, constraint or foreign key uses these columns, so DROP COLUMN works.
local function v2_drop_difficulty()
	dk.db:exec_script([[
ALTER TABLE control DROP COLUMN diff1name;
ALTER TABLE control DROP COLUMN diff1mod;
ALTER TABLE control DROP COLUMN diff2name;
ALTER TABLE control DROP COLUMN diff2mod;
ALTER TABLE control DROP COLUMN diff3name;
ALTER TABLE control DROP COLUMN diff3mod;
ALTER TABLE users DROP COLUMN difficulty;
]])
end

-- 3: experience and TP per level and the HP bonus at milestone levels became formulas
-- (lib/leveling.lua): drop the levels table's exp and tp columns (values an admin edited
-- are discarded) and take the milestone bonus off the HP gain at those levels (0 for the
-- original data; an edited value keeps its difference). Players keep their experience;
-- one whose experience already covers the (slightly moved) next level gets it on the
-- next victory.
local function v3_leveling_formulas()
	local db = dk.db
	local bonus = "CASE WHEN id IN (10, 20, 30) THEN 10 WHEN id IN (40, 50, 60) THEN 15 " ..
								"WHEN id IN (70, 80, 90) THEN 20 ELSE 50 END"
	for class = 1, 3 do
		db:exec(string.format('ALTER TABLE levels DROP COLUMN "%d_exp"', class))
		db:exec(string.format('ALTER TABLE levels DROP COLUMN "%d_tp"', class))
		db:exec(string.format('UPDATE levels SET "%d_hp" = max("%d_hp" - (%s), 0) ' ..
													'WHERE id IN (10, 20, 30, 40, 50, 60, 70, 80, 90, 99)', class, class, bonus))
	end
end

-- 4: character classes become content (app/content/classes/*.lua, synced into classes,
-- class_levels and class_spells; app/lib/content/). The original classes keep ids 1-3
-- (users.charclass). Built here from the control row's class names, the levels table and
-- the experience parameters lib/leveling.lua had at version 3; every value an admin could
-- edit (class names, per-level gains and spells) is also recorded in content_adopt, so
-- the sync at the end of `dk migrate` keeps the ones that differ from the content files
-- as admin overrides. A level's spell only when it differs from the original game's
-- (V4_STOCK_SPELLS): the class files have since taught spells at more levels, and a
-- stock database's "no spell here" is no edit. New characters keep the starting stats they got before (the users
-- column defaults; the levels table's row 1 was only shown on the help page).
local V4_CLASSES = {
	{ key = "mage", name = "Mage", exp_base = 15, exp_stages = "2x2,1.5x8,1.25x5,1.125x28" },
	{ key = "warrior", name = "Warrior", exp_base = 18, exp_stages = "2x2,1.5x8,1.25x5,1.125x27" },
	{ key = "paladin", name = "Paladin", exp_base = 20, exp_stages = "2x2,1.5x8,1.25x6,1.125x25" },
}

-- the original game's spell ids per class and level (the levels table's spell columns as
-- installed; ids are the original spells', see V5_SPELLS)
local V4_STOCK_SPELLS = {
	{ [2] = 1, [4] = 6, [7] = 11, [9] = 2, [12] = 7, [14] = 17, [17] = 12, [25] = 3, [31] = 8, [36] = 18,
		[40] = 13, [45] = 4, [51] = 9, [60] = 19, [70] = 5, [79] = 10 },
	{ [2] = 1, [5] = 6, [8] = 11, [11] = 2, [14] = 7, [18] = 14, [22] = 12, [25] = 17, [29] = 3, [34] = 8,
		[38] = 15, [45] = 18, [51] = 13, [58] = 19, [70] = 16 },
	{ [2] = 1, [5] = 6, [8] = 11, [11] = 2, [14] = 7, [18] = 17, [22] = 12, [25] = 14, [29] = 3, [34] = 8,
		[38] = 18, [45] = 4, [51] = 13, [56] = 9, [60] = 15 },
}

local function v4_classes_content()
	local db = dk.db
	db:exec_script([[
CREATE TABLE classes (
	id               INTEGER PRIMARY KEY,
	key              TEXT    NOT NULL UNIQUE,
	name             TEXT    NOT NULL DEFAULT '',
	description      TEXT    NOT NULL DEFAULT '',
	sort             INTEGER NOT NULL DEFAULT 0,
	playable         INTEGER NOT NULL DEFAULT 1,
	start_hp         INTEGER NOT NULL DEFAULT 15,
	start_mp         INTEGER NOT NULL DEFAULT 0,
	start_tp         INTEGER NOT NULL DEFAULT 10,
	start_strength   INTEGER NOT NULL DEFAULT 5,
	start_dexterity  INTEGER NOT NULL DEFAULT 5,
	exp_base         INTEGER NOT NULL DEFAULT 15,
	exp_stages       TEXT    NOT NULL DEFAULT '',
	retired          INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE class_levels (
	class_id   INTEGER NOT NULL REFERENCES classes (id),
	level      INTEGER NOT NULL,
	hp         INTEGER NOT NULL DEFAULT 0,
	mp         INTEGER NOT NULL DEFAULT 0,
	strength   INTEGER NOT NULL DEFAULT 0,
	dexterity  INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (class_id, level)
) WITHOUT ROWID;
CREATE TABLE class_spells (
	class_id  INTEGER NOT NULL REFERENCES classes (id),
	level     INTEGER NOT NULL,
	spell_id  INTEGER NOT NULL,
	PRIMARY KEY (class_id, level, spell_id)
) WITHOUT ROWID;
CREATE TABLE content_overrides (
	kind   TEXT NOT NULL,
	key    TEXT NOT NULL,
	field  TEXT NOT NULL,
	value  TEXT NOT NULL,
	PRIMARY KEY (kind, key, field)
) WITHOUT ROWID;
CREATE TABLE content_adopt (
	kind   TEXT NOT NULL,
	key    TEXT NOT NULL,
	field  TEXT NOT NULL,
	value  TEXT NOT NULL,
	PRIMARY KEY (kind, key, field)
) WITHOUT ROWID;
CREATE TABLE meta (
	key    TEXT PRIMARY KEY,
	value  TEXT NOT NULL
) WITHOUT ROWID;
]])
	local control = db:first("SELECT class1name, class2name, class3name FROM control WHERE id = 1") or {}
	local levels = db:query("SELECT * FROM levels WHERE id >= 2 AND id <= 100 ORDER BY id")
	for id, c in ipairs(V4_CLASSES) do
		local function adopt(field, value)
			db:exec("INSERT INTO content_adopt (kind, key, field, value) VALUES ('classes', ?, ?, ?)",
							c.key, field, tostring(value))
		end
		local name = control["class" .. id .. "name"]
		if name == nil or name == "" then name = c.name end
		db:exec("INSERT INTO classes (id, key, name, sort, exp_base, exp_stages) VALUES (?, ?, ?, ?, ?, ?)",
						id, c.key, name, id, c.exp_base, c.exp_stages)
		adopt("name", name)
		for _, row in ipairs(levels) do
			local function col(stat) return row[id .. "_" .. stat] end
			db:exec("INSERT INTO class_levels (class_id, level, hp, mp, strength, dexterity) VALUES (?, ?, ?, ?, ?, ?)",
							id, row.id, col("hp"), col("mp"), col("strength"), col("dexterity"))
			for _, stat in ipairs({ "hp", "mp", "strength", "dexterity" }) do
				adopt("levels." .. row.id .. "." .. stat, col(stat))
			end
			local spell = col("spells")
			if spell > 0 then
				db:exec("INSERT INTO class_spells (class_id, level, spell_id) VALUES (?, ?, ?)", id, row.id, spell)
			end
			if spell ~= (V4_STOCK_SPELLS[id][row.id] or 0) then
				adopt("levels." .. row.id .. ".spells", spell > 0 and spell or "")
			end
		end
	end
	db:exec_script([[
DROP TABLE levels;
ALTER TABLE control DROP COLUMN class1name;
ALTER TABLE control DROP COLUMN class2name;
ALTER TABLE control DROP COLUMN class3name;
]])
end

-- 5: spells become content (app/content/spells/<key>.lua, synced into spells; what they do
-- is a list of effects, the engine of the time, until version 7 scripted them) and the
-- spells a character knows move from the users.spells comma list to user_spells. The
-- original spells keep ids 1-19 and get their
-- keys; type + attribute become one effect (1 heal_hp amount, 2 damage max, 3 sleep chance,
-- 4 buff_attack_pct pct, 5 buff_defense_pct pct). Admin edits of the name, MP and attribute
-- go to content_adopt (kept as overrides by the sync at the end of `dk migrate` where they
-- differ from the files and are valid); a changed type can't be kept (the file's effect
-- wins; reported). Other spell rows (ids from 20, no file) get the key spell_<id> and are
-- retired by the sync; characters keep them. A known spell's learned_level is the level at
-- which the character's class learns it, if that is not above the character's level, else
-- NULL (unknown). Class level overrides listing spell ids now list keys.
local V5_SPELLS = {
	{ "heal", "Heal", 1 }, { "revive", "Revive", 1 }, { "life", "Life", 1 }, { "breath", "Breath", 1 },
	{ "gaia", "Gaia", 1 }, { "hurt", "Hurt", 2 }, { "pain", "Pain", 2 }, { "maim", "Maim", 2 },
	{ "rend", "Rend", 2 }, { "chaos", "Chaos", 2 }, { "sleep", "Sleep", 3 }, { "dream", "Dream", 3 },
	{ "nightmare", "Nightmare", 3 }, { "craze", "Craze", 4 }, { "rage", "Rage", 4 }, { "fury", "Fury", 4 },
	{ "ward", "Ward", 5 }, { "fend", "Fend", 5 }, { "barrier", "Barrier", 5 },
}
local V5_EFFECTS = {
	{ "heal_hp", "amount" }, { "damage", "max" }, { "sleep", "chance" }, { "buff_attack_pct", "pct" },
	{ "buff_defense_pct", "pct" },
}

local function v5_spells_content()
	local db = dk.db
	local php = require("lib.php")
	local old = db:query("SELECT * FROM spells ORDER BY id")
	db:exec_script([[
CREATE TABLE spells_new (
	id           INTEGER PRIMARY KEY,
	key          TEXT    NOT NULL UNIQUE,
	name         TEXT    NOT NULL DEFAULT '',
	description  TEXT    NOT NULL DEFAULT '',
	mp           INTEGER NOT NULL DEFAULT 0,
	usable_in    TEXT    NOT NULL DEFAULT 'fight',
	effects      TEXT    NOT NULL DEFAULT '',
	retired      INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE user_spells (
	user_id        INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	spell_id       INTEGER NOT NULL REFERENCES spells (id),
	learned_level  INTEGER,
	PRIMARY KEY (user_id, spell_id)
) WITHOUT ROWID;
]])
	local key_of = {}
	for _, s in ipairs(old) do
		local orig = V5_SPELLS[s.id]
		local key = orig and orig[1] or ("spell_" .. s.id)
		local attribute = php.mysql_int(s.attribute)
		local effect = V5_EFFECTS[s.type]
		db:exec("INSERT INTO spells_new (id, key, name, mp, usable_in, effects) VALUES (?, ?, ?, ?, ?, ?)",
						s.id, key, s.name, s.mp, s.type == 1 and "both" or "fight",
						effect and (effect[1] .. " " .. effect[2] .. "=" .. attribute) or "")
		key_of[s.id] = key
		if orig then
			local function adopt(field, value)
				db:exec("INSERT INTO content_adopt (kind, key, field, value) VALUES ('spells', ?, ?, ?)",
								key, field, tostring(value))
			end
			adopt("name", s.name)
			adopt("mp", s.mp)
			if s.type == orig[3] then
				adopt("effects.1." .. effect[2], attribute)
			else
				print(("warning: spell %d (%s) had its type changed to %s; it keeps the effect of %s"):format(
					s.id, s.name, tostring(s.type), "app/content/spells/" .. key .. ".lua"))
			end
		end
	end
	-- partial installs had no spells: the original ids get their keys (the sync fills in the rest)
	for id, orig in ipairs(V5_SPELLS) do
		if not key_of[id] then
			db:exec("INSERT INTO spells_new (id, key, name) VALUES (?, ?, ?)", id, orig[1], orig[2])
			key_of[id] = orig[1]
		end
	end
	db:exec_script([[
DROP TABLE spells;
ALTER TABLE spells_new RENAME TO spells;
DELETE FROM sqlite_sequence WHERE name = 'spells';
CREATE TABLE class_spells_new (
	class_id  INTEGER NOT NULL REFERENCES classes (id),
	level     INTEGER NOT NULL,
	spell_id  INTEGER NOT NULL REFERENCES spells (id),
	PRIMARY KEY (class_id, level, spell_id)
) WITHOUT ROWID;
INSERT INTO class_spells_new (class_id, level, spell_id)
	SELECT class_id, level, spell_id FROM class_spells WHERE spell_id IN (SELECT id FROM spells);
DROP TABLE class_spells;
ALTER TABLE class_spells_new RENAME TO class_spells;
]])

	-- users.spells -> user_spells, with legacy's matching (php.in_list: "0" and unknown ids
	-- match no spell, duplicates count once)
	local ids = {}
	for id in pairs(key_of) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, u in ipairs(db:query("SELECT id, charclass, level, spells FROM users ORDER BY id")) do
		for _, id in ipairs(ids) do
			if php.in_list(u.spells, id) then
				db:exec("INSERT INTO user_spells (user_id, spell_id, learned_level) VALUES (?, ?, " ..
								"(SELECT min(level) FROM class_spells WHERE class_id = ? AND spell_id = ? AND level <= ?))",
								u.id, id, u.charclass, id, u.level)
			end
		end
	end

	-- class level spells (overrides and pending adoptions of version 4) as keys
	for _, tbl in ipairs({ "content_overrides", "content_adopt" }) do
		for _, r in ipairs(db:query("SELECT key, field, value FROM " .. tbl ..
																" WHERE kind = 'classes' AND field LIKE 'levels.%.spells'")) do
			local keys = {}
			for id in r.value:gmatch("%d+") do
				local key = key_of[math.tointeger(tonumber(id))]
				if key then keys[#keys + 1] = key end
			end
			table.sort(keys)
			db:exec("UPDATE " .. tbl .. " SET value = ? WHERE kind = 'classes' AND key = ? AND field = ?",
							table.concat(keys, ","), r.key, r.field)
		end
	end
	db:exec("ALTER TABLE users DROP COLUMN spells")
end

-- 6: items become content (app/content/items/<key>.lua, synced into items), the drops are
-- accessory items, characters carry user_items (equipped or in the bag), towns sell
-- town_items, and the users table keeps base stats (lib/stats.lua derives the rest from
-- the equipped items). The original items keep ids 1-33 and their keys; drop N becomes
-- item 33 + N (drop_level = mlevel, its two attributes stat modifiers); the new
-- consumables get 66-68 (the sync fills them in). Other item and drop rows (admin-added)
-- get the keys item_<id> / drop_<id> and ids from 69 on, and are retired by the sync:
-- characters keep them, but shops and monsters no longer offer them (a content file with
-- that key brings one back, same id). Admin edits of the original items and drops (name, cost,
-- attribute, special, monster level, attributes) go to content_adopt (kept as overrides by
-- the sync where they differ from the files). weaponid/armorid/shieldid and slot1-3id
-- become equipped user_items (the stored names go: items have one name now), dropcode the
-- new id, towns.itemslist town_items (with the original matching; every town also sells
-- Herbs, and towns 2-8 Potions and Ethers, like a new install).
--
-- Stats: the stored maxhp/maxmp/maxtp/strength/dexterity/expbonus/goldbonus held the gear's
-- contributions; base = stored - what the equipped items add (stats.solve), and
-- attack/defense power beyond strength/dexterity + gear (old data, admin edits) is kept in
-- base_attack/base_defense (reported). Then every character's effective stats are
-- recomputed (stats.derive) and must equal the stored ones, or the migration fails. The
-- expected values stay in a temporary table until after the content sync (after_sync):
-- an admin edit the item files can't express (a special on a column that isn't a stat,
-- a changed item type) would change them, so those characters' base stats are adjusted to
-- keep their effective stats, and reported.
-- The original items and drops (seed data up to version 5): key, name, type, buycost,
-- attribute, special / key, name, mlevel, attribute1, attribute2.
local V6_ITEMS = {
	{ "stick", "Stick", 1, 10, 2, "X" },
	{ "branch", "Branch", 1, 30, 4, "X" },
	{ "club", "Club", 1, 40, 5, "X" },
	{ "dagger", "Dagger", 1, 90, 8, "X" },
	{ "hatchet", "Hatchet", 1, 150, 12, "X" },
	{ "axe", "Axe", 1, 200, 16, "X" },
	{ "brand", "Brand", 1, 300, 25, "X" },
	{ "poleaxe", "Poleaxe", 1, 500, 35, "X" },
	{ "broadsword", "Broadsword", 1, 800, 45, "X" },
	{ "battle_axe", "Battle Axe", 1, 1200, 50, "X" },
	{ "claymore", "Claymore", 1, 2000, 60, "X" },
	{ "dark_axe", "Dark Axe", 1, 3000, 100, "expbonus,-5" },
	{ "dark_sword", "Dark Sword", 1, 4500, 125, "expbonus,-10" },
	{ "bright_sword", "Bright Sword", 1, 6000, 100, "expbonus,10" },
	{ "magic_sword", "Magic Sword", 1, 10000, 150, "maxmp,50" },
	{ "destiny_blade", "Destiny Blade", 1, 50000, 250, "strength,50" },
	{ "skivvies", "Skivvies", 2, 25, 2, "goldbonus,10" },
	{ "clothes", "Clothes", 2, 50, 5, "X" },
	{ "leather_armor", "Leather Armor", 2, 75, 10, "X" },
	{ "hard_leather_armor", "Hard Leather Armor", 2, 150, 25, "X" },
	{ "chain_mail", "Chain Mail", 2, 300, 30, "X" },
	{ "bronze_plate", "Bronze Plate", 2, 900, 50, "X" },
	{ "iron_plate", "Iron Plate", 2, 2000, 100, "X" },
	{ "magic_armor", "Magic Armor", 2, 4000, 125, "maxmp,50" },
	{ "dark_armor", "Dark Armor", 2, 5000, 150, "expbonus,-10" },
	{ "bright_armor", "Bright Armor", 2, 10000, 175, "expbonus,10" },
	{ "destiny_raiment", "Destiny Raiment", 2, 50000, 200, "dexterity,50" },
	{ "reed_shield", "Reed Shield", 3, 50, 2, "X" },
	{ "buckler", "Buckler", 3, 100, 4, "X" },
	{ "small_shield", "Small Shield", 3, 500, 10, "X" },
	{ "large_shield", "Large Shield", 3, 2500, 30, "X" },
	{ "silver_shield", "Silver Shield", 3, 10000, 60, "X" },
	{ "destiny_aegis", "Destiny Aegis", 3, 25000, 100, "maxhp,50" },
}
local V6_DROPS = {
	{ "life_pebble", "Life Pebble", 1, "maxhp,10", "X" },
	{ "life_stone", "Life Stone", 10, "maxhp,25", "X" },
	{ "life_rock", "Life Rock", 25, "maxhp,50", "X" },
	{ "magic_pebble", "Magic Pebble", 1, "maxmp,10", "X" },
	{ "magic_stone", "Magic Stone", 10, "maxmp,25", "X" },
	{ "magic_rock", "Magic Rock", 25, "maxmp,50", "X" },
	{ "dragons_scale", "Dragon's Scale", 10, "defensepower,25", "X" },
	{ "dragons_plate", "Dragon's Plate", 30, "defensepower,50", "X" },
	{ "dragons_claw", "Dragon's Claw", 10, "attackpower,25", "X" },
	{ "dragons_tooth", "Dragon's Tooth", 30, "attackpower,50", "X" },
	{ "dragons_tear", "Dragon's Tear", 35, "strength,50", "X" },
	{ "dragons_wing", "Dragon's Wing", 35, "dexterity,50", "X" },
	{ "demons_sin", "Demon's Sin", 35, "maxhp,-50", "strength,50" },
	{ "demons_fall", "Demon's Fall", 35, "maxmp,-50", "strength,50" },
	{ "demons_lie", "Demon's Lie", 45, "maxhp,-100", "strength,100" },
	{ "demons_hate", "Demon's Hate", 45, "maxmp,-100", "strength,100" },
	{ "angels_joy", "Angel's Joy", 25, "maxhp,25", "strength,25" },
	{ "angels_rise", "Angel's Rise", 30, "maxhp,50", "strength,50" },
	{ "angels_truth", "Angel's Truth", 35, "maxhp,75", "strength,75" },
	{ "angels_love", "Angel's Love", 40, "maxhp,100", "strength,100" },
	{ "seraphs_joy", "Seraph's Joy", 25, "maxmp,25", "dexterity,25" },
	{ "seraphs_rise", "Seraph's Rise", 30, "maxmp,50", "dexterity,50" },
	{ "seraphs_truth", "Seraph's Truth", 35, "maxmp,75", "dexterity,75" },
	{ "seraphs_love", "Seraph's Love", 40, "maxmp,100", "dexterity,100" },
	{ "ruby", "Ruby", 50, "maxhp,150", "X" },
	{ "pearl", "Pearl", 50, "maxmp,150", "X" },
	{ "emerald", "Emerald", 50, "strength,150", "X" },
	{ "topaz", "Topaz", 50, "dexterity,150", "X" },
	{ "obsidian", "Obsidian", 50, "attackpower,150", "X" },
	{ "diamond", "Diamond", 50, "defensepower,150", "X" },
	{ "memory_drop", "Memory Drop", 5, "expbonus,10", "X" },
	{ "fortune_drop", "Fortune Drop", 5, "goldbonus,10", "X" },
}
local V6_CONSUMABLES = { { 66, "herb", "Herb" }, { 67, "potion", "Potion" }, { 68, "ether", "Ether" } }
local V6_CATEGORY = { [1] = "weapon", [2] = "armor", [3] = "shield" }
local V6_STAT = {
	maxhp = "maxhp", maxmp = "maxmp", maxtp = "maxtp", strength = "strength", dexterity = "dexterity",
	attackpower = "attack", defensepower = "defense", expbonus = "exp_bonus_pct", goldbonus = "gold_bonus_pct",
}

-- A special code / drop attribute ("stat,value", "X") -> { stat, amount } or nil, and
-- whether it was something other than "X" that isn't a stat (a one-off like "gold,100").
local function v6_modifier(code)
	if code == nil or code == "X" or code == "" then return nil, false end
	local php = require("lib.php")
	local parts = php.explode(",", code)
	local stat = V6_STAT[php.trim(parts[1] or "")]
	local n = tonumber(tostring(parts[2] or ""):match("^%s*([+-]?%d+%.?%d*)")) or 0
	if not stat then return nil, true end
	return { kind = "stat", stat = stat, amount = php.mysql_int(n) }, false
end

local function v6_items_content()
	local db = dk.db
	local php = require("lib.php")
	local stats = require("lib.stats")
	local old_items = db:query("SELECT * FROM items ORDER BY id")
	local old_drops = db:query("SELECT * FROM drops ORDER BY id")
	db:exec_script([[
CREATE TABLE items_new (
	id           INTEGER PRIMARY KEY,
	key          TEXT    NOT NULL UNIQUE,
	name         TEXT    NOT NULL DEFAULT '',
	description  TEXT    NOT NULL DEFAULT '',
	category     TEXT    NOT NULL DEFAULT 'misc',
	slot         TEXT,
	price        INTEGER NOT NULL DEFAULT 0,
	attack       INTEGER NOT NULL DEFAULT 0,
	defense      INTEGER NOT NULL DEFAULT 0,
	modifiers    TEXT    NOT NULL DEFAULT '',
	use_effects  TEXT    NOT NULL DEFAULT '',
	max_stack    INTEGER NOT NULL DEFAULT 1,
	drop_level   INTEGER,
	sellable     INTEGER NOT NULL DEFAULT 0,
	droppable    INTEGER NOT NULL DEFAULT 1,
	retired      INTEGER NOT NULL DEFAULT 0
);
]])
	local function adopt(key, field, value)
		db:exec("INSERT OR REPLACE INTO content_adopt (kind, key, field, value) VALUES ('items', ?, ?, ?)",
						key, field, tostring(value))
	end
	-- modifiers that differ from the original data: adopt index i (stat and amount), or
	-- amount 0 when the original had one there and the edit removed it
	local function adopt_modifier(key, i, code, original, label)
		if code == original then return end
		local m, odd = v6_modifier(code)
		if m then
			adopt(key, "modifiers." .. i .. ".stat", m.stat)
			adopt(key, "modifiers." .. i .. ".amount", m.amount)
		elseif v6_modifier(original) then
			adopt(key, "modifiers." .. i .. ".amount", 0)
		end
		if odd then
			print(("warning: %s has the special \"%s\", which is not a stat; items can't do that any more"):format(
				label, code))
		end
	end

	local rows = {}         -- new id -> { attack, defense, modifiers } (what equipping it adds)
	local item_map, drop_map = {}, {}
	local next_id = 69
	local function insert(id, key, name, r)
		db:exec("INSERT INTO items_new (id, key, name, category, slot, price, attack, defense, modifiers, " ..
						"drop_level, sellable) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", id, key, name, r.category, r.slot,
						r.price, r.attack, r.defense, stats.encode_modifiers(r.modifiers), r.drop_level, r.price > 0 and 1 or 0)
		rows[id] = r
	end
	for _, it in ipairs(old_items) do
		local category = V6_CATEGORY[it.type] or "misc"
		local m = v6_modifier(it.special)
		local r = {
			category = category, slot = category ~= "misc" and category or nil, price = php.mysql_uint(it.buycost),
			attack = it.type == 1 and php.mysql_int(it.attribute) or 0,
			defense = (it.type == 2 or it.type == 3) and php.mysql_int(it.attribute) or 0,
			modifiers = { m },
		}
		local orig = V6_ITEMS[it.id]
		local id, key = it.id, orig and orig[1]
		if not orig then
			id, key = next_id, "item_" .. it.id
			next_id = next_id + 1
		end
		insert(id, key, it.name, r)
		item_map[it.id] = id
		if orig then
			local label = ("item %d (%s)"):format(it.id, it.name)
			if it.name ~= orig[2] then adopt(key, "name", it.name) end
			if it.buycost ~= orig[4] then adopt(key, "price", r.price) end
			if it.type ~= orig[3] then
				print(("warning: %s had its type changed to %s; it keeps the category of app/content/items/%s.lua"):format(
					label, tostring(it.type), key))
			end
			if it.attribute ~= orig[5] then adopt(key, orig[3] == 1 and "attack" or "defense", php.mysql_int(it.attribute)) end
			adopt_modifier(key, 1, it.special, orig[6], label)
		end
	end
	for _, d in ipairs(old_drops) do
		local mods = {}
		for _, code in ipairs({ d.attribute1, d.attribute2 }) do
			local m = v6_modifier(code)
			if m and m.amount ~= 0 then mods[#mods + 1] = m end
		end
		local r = { category = "accessory", slot = "accessory", price = 0, attack = 0, defense = 0, modifiers = mods,
								drop_level = d.mlevel }
		local orig = V6_DROPS[d.id]
		local id, key = 33 + d.id, orig and orig[1]
		if not orig then
			id, key = next_id, "drop_" .. d.id
			next_id = next_id + 1
		end
		insert(id, key, d.name, r)
		drop_map[d.id] = id
		if orig then
			local label = ("drop %d (%s)"):format(d.id, d.name)
			if d.name ~= orig[2] then adopt(key, "name", d.name) end
			if d.mlevel ~= orig[3] then adopt(key, "drop_level", d.mlevel) end
			adopt_modifier(key, 1, d.attribute1, orig[4], label)
			adopt_modifier(key, 2, d.attribute2, orig[5], label)
		end
	end
	-- partial installs (and deleted rows): the original ids get their keys; the sync fills
	-- in the rest
	local function placeholder(id, key, name)
		if not rows[id] then
			db:exec("INSERT INTO items_new (id, key, name) VALUES (?, ?, ?)", id, key, name)
		end
	end
	for id, orig in ipairs(V6_ITEMS) do placeholder(id, orig[1], orig[2]) end
	for id, orig in ipairs(V6_DROPS) do placeholder(33 + id, orig[1], orig[2]) end
	for _, c in ipairs(V6_CONSUMABLES) do placeholder(c[1], c[2], c[3]) end

	local towns = db:query("SELECT id, itemslist FROM towns ORDER BY id")
	db:exec_script([[
DROP TABLE items;
DROP TABLE drops;
ALTER TABLE items_new RENAME TO items;
DELETE FROM sqlite_sequence WHERE name IN ('items', 'drops');
CREATE TABLE town_items (
	town_id  INTEGER NOT NULL REFERENCES towns (id),
	item_id  INTEGER NOT NULL REFERENCES items (id),
	PRIMARY KEY (town_id, item_id)
) WITHOUT ROWID;
CREATE TABLE user_items (
	id        INTEGER PRIMARY KEY,
	user_id   INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	item_id   INTEGER NOT NULL REFERENCES items (id),
	qty       INTEGER NOT NULL DEFAULT 1,
	equipped  TEXT
);
CREATE UNIQUE INDEX user_items_equipped ON user_items (user_id, equipped);
ALTER TABLE control ADD COLUMN inventory_size INTEGER NOT NULL DEFAULT 12;
ALTER TABLE users RENAME COLUMN maxhp TO base_maxhp;
ALTER TABLE users RENAME COLUMN maxmp TO base_maxmp;
ALTER TABLE users RENAME COLUMN maxtp TO base_maxtp;
ALTER TABLE users ADD COLUMN base_attack INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN base_defense INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN base_exp_bonus INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN base_gold_bonus INTEGER NOT NULL DEFAULT 0;
DROP TABLE IF EXISTS temp.v6_expected;
CREATE TEMP TABLE v6_expected (user_id INTEGER PRIMARY KEY, maxhp INTEGER, maxmp INTEGER, maxtp INTEGER,
	strength INTEGER, dexterity INTEGER, attack INTEGER, defense INTEGER, exp_bonus_pct INTEGER,
	gold_bonus_pct INTEGER);
]])

	-- towns.itemslist -> town_items, with legacy's matching (php.in_list), + the consumables
	for _, t in ipairs(towns) do
		for _, it in ipairs(old_items) do
			if php.in_list(t.itemslist, it.id) then
				db:exec("INSERT OR IGNORE INTO town_items (town_id, item_id) VALUES (?, ?)", t.id, item_map[it.id])
			end
		end
		for _, c in ipairs(V6_CONSUMABLES) do
			if t.id == 1 and c[2] == "herb" or t.id >= 2 and t.id <= 8 then
				db:exec("INSERT OR IGNORE INTO town_items (town_id, item_id) VALUES (?, ?)", t.id, c[1])
			end
		end
	end

	-- equipment -> user_items; stored stats -> base stats, verified
	local slots = {
		{ "weapon", "weaponid", item_map }, { "armor", "armorid", item_map }, { "shield", "shieldid", item_map },
		{ "accessory1", "slot1id", drop_map }, { "accessory2", "slot2id", drop_map }, { "accessory3", "slot3id", drop_map },
	}
	local CLAMPED = { maxhp = true, maxmp = true, maxtp = true, strength = true, dexterity = true, attack = true,
		defense = true }
	local converted, kept = 0, 0
	for _, u in ipairs(db:query("SELECT * FROM users ORDER BY id")) do
		local who = ("character %s (user %d)"):format(u.charname, u.id)
		local equipped = {}
		for _, s in ipairs(slots) do
			local old_id = u[s[2]]
			if old_id ~= 0 then
				local id = s[3][old_id]
				if id then
					db:exec("INSERT INTO user_items (user_id, item_id, qty, equipped) VALUES (?, ?, 1, ?)", u.id, id, s[1])
					equipped[#equipped + 1] = rows[id]
				else
					print(("warning: %s had %s %d, which doesn't exist; it is gone"):format(who, s[2], old_id))
				end
			end
		end
		local mods = stats.item_mods(equipped)
		local expected = {
			maxhp = u.base_maxhp, maxmp = u.base_maxmp, maxtp = u.base_maxtp, strength = u.strength,
			dexterity = u.dexterity, attack = u.attackpower, defense = u.defensepower, exp_bonus_pct = u.expbonus,
			gold_bonus_pct = u.goldbonus,
		}
		for stat in pairs(CLAMPED) do
			if expected[stat] < 0 then
				print(("warning: %s had %s %d (below 0); it counts as 0"):format(who, stat, expected[stat]))
				expected[stat] = 0
			end
		end
		local base = stats.solve(expected, mods)
		local check = stats.derive(base, mods)
		local diff = stats.diff(check, expected)
		if #diff > 0 then
			error(("migration 6: %s: recomputed %s differs from the stored value"):format(who, table.concat(diff, ", ")), 0)
		end
		if base.base_attack ~= 0 or base.base_defense ~= 0 then
			kept = kept + 1
			print(("note: %s keeps %d attack and %d defense power that strength, dexterity and gear don't give " ..
				"(base_attack, base_defense)"):format(who, base.base_attack, base.base_defense))
		end
		db:exec("UPDATE users SET base_maxhp = ?, base_maxmp = ?, base_maxtp = ?, strength = ?, dexterity = ?, " ..
						"base_attack = ?, base_defense = ?, base_exp_bonus = ?, base_gold_bonus = ?, dropcode = ? WHERE id = ?",
						base.base_maxhp, base.base_maxmp, base.base_maxtp, base.strength, base.dexterity, base.base_attack,
						base.base_defense, base.base_exp_bonus, base.base_gold_bonus,
						u.dropcode ~= 0 and drop_map[u.dropcode] or 0, u.id)
		db:exec("INSERT INTO temp.v6_expected (user_id, maxhp, maxmp, maxtp, strength, dexterity, attack, defense, " ..
						"exp_bonus_pct, gold_bonus_pct) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", u.id, expected.maxhp,
						expected.maxmp, expected.maxtp, expected.strength, expected.dexterity, expected.attack, expected.defense,
						expected.exp_bonus_pct, expected.gold_bonus_pct)
		converted = converted + 1
	end
	print(("Converted the stats of %d characters to base stats (verified); %d keep extra attack/defense power."):format(
		converted, kept))

	db:exec_script([[
ALTER TABLE users DROP COLUMN goldbonus;
ALTER TABLE users DROP COLUMN expbonus;
ALTER TABLE users DROP COLUMN attackpower;
ALTER TABLE users DROP COLUMN defensepower;
ALTER TABLE users DROP COLUMN weaponid;
ALTER TABLE users DROP COLUMN armorid;
ALTER TABLE users DROP COLUMN shieldid;
ALTER TABLE users DROP COLUMN slot1id;
ALTER TABLE users DROP COLUMN slot2id;
ALTER TABLE users DROP COLUMN slot3id;
ALTER TABLE users DROP COLUMN weaponname;
ALTER TABLE users DROP COLUMN armorname;
ALTER TABLE users DROP COLUMN shieldname;
ALTER TABLE users DROP COLUMN slot1name;
ALTER TABLE users DROP COLUMN slot2name;
ALTER TABLE users DROP COLUMN slot3name;
ALTER TABLE towns DROP COLUMN itemslist;
]])
end

-- After the content sync: the items now have the file values plus the adopted edits. A
-- character whose effective stats differ from before the migration (an edit the files
-- can't express) gets base stats that keep them. Runs once, right after `dk migrate`
-- synced the content (the temporary table only lives in that connection).
local function v6_after_sync()
	local db = dk.db
	if not db:value("SELECT 1 FROM temp.sqlite_master WHERE name = 'v6_expected'") then return end
	local stats = require("lib.stats")
	for _, e in ipairs(db:query("SELECT * FROM temp.v6_expected ORDER BY user_id")) do
		local u = db:first("SELECT * FROM users WHERE id = ?", e.user_id)
		local list = db:query("SELECT i.attack, i.defense, i.modifiers FROM user_items ui JOIN items i ON i.id = ui.item_id " ..
													"WHERE ui.user_id = ? AND ui.equipped IS NOT NULL", e.user_id)
		for _, it in ipairs(list) do it.modifiers = stats.decode_modifiers(it.modifiers) end
		local mods = stats.item_mods(list)
		local diff = stats.diff(stats.derive(u, mods), e)
		if #diff > 0 then
			local base = stats.solve(e, mods)
			db:exec("UPDATE users SET base_maxhp = ?, base_maxmp = ?, base_maxtp = ?, strength = ?, dexterity = ?, " ..
							"base_attack = ?, base_defense = ?, base_exp_bonus = ?, base_gold_bonus = ? WHERE id = ?",
							base.base_maxhp, base.base_maxmp, base.base_maxtp, base.strength, base.dexterity, base.base_attack,
							base.base_defense, base.base_exp_bonus, base.base_gold_bonus, e.user_id)
			print(("warning: character %s (user %d): the items' new values changed %s; base stats adjusted to keep them"):format(
				u.charname, u.id, table.concat(diff, ", ")))
		end
	end
	db:exec("DROP TABLE temp.v6_expected")
end

-- 7: spells and consumables are scripted (lib/action.lua): what they do is their content
-- file's code (cast / use); their numbers and texts are data. spells.effects and
-- items.use_effects go; spells get power, target, messages and data, items usable_in,
-- target, power, messages and data (the sync at the end of `dk migrate` fills them in from
-- the files). Rows without a file (retired) keep their old first effect's amount as power
-- and a target and usable_in that fit it, for display: they can't be cast or used any
-- more (they have no code). Admin overrides and pending adoptions of an effect's amount
-- ("effects.1.max", "use_effects.1.amount") become power overrides; those of other effect
-- parameters can't be kept (reported).
local V7_POWER = { heal_hp = "amount", heal_mp = "amount", heal_tp = "amount", damage = "max", sleep = "chance",
	buff_attack_pct = "pct", buff_defense_pct = "pct" }
local V7_SELF = { heal_hp = true, heal_mp = true, heal_tp = true, buff_attack_pct = true, buff_defense_pct = true }
local V7_TOWN = { heal_hp = true, heal_mp = true, heal_tp = true }

-- A stored effect list ("damage max=15; sleep chance=5") -> the first effect's kind, its
-- amount (the new power) and whether every effect worked outside fights.
local function v7_effects(text)
	local kind, power, town, n = nil, 0, true, 0
	for part in tostring(text or ""):gmatch("[^;]+") do
		local words = {}
		for w in part:gmatch("%S+") do words[#words + 1] = w end
		if words[1] then
			n = n + 1
			if not V7_TOWN[words[1]] then town = false end
			if n == 1 then
				kind = words[1]
				for i = 2, #words do
					local k, v = words[i]:match("^([%w_]+)=(.*)$")
					if k and k == V7_POWER[kind] then power = math.tointeger(tonumber(v)) or 0 end
				end
			end
		end
	end
	return kind, power, town and n > 0
end

local function v7_scripted()
	local db = dk.db
	db:exec_script([[
ALTER TABLE spells ADD COLUMN power INTEGER NOT NULL DEFAULT 0;
ALTER TABLE spells ADD COLUMN target TEXT NOT NULL DEFAULT 'enemy';
ALTER TABLE spells ADD COLUMN messages TEXT NOT NULL DEFAULT '';
ALTER TABLE spells ADD COLUMN data TEXT NOT NULL DEFAULT '';
ALTER TABLE items ADD COLUMN usable_in TEXT NOT NULL DEFAULT 'fight';
ALTER TABLE items ADD COLUMN target TEXT NOT NULL DEFAULT 'enemy';
ALTER TABLE items ADD COLUMN power INTEGER NOT NULL DEFAULT 0;
ALTER TABLE items ADD COLUMN messages TEXT NOT NULL DEFAULT '';
ALTER TABLE items ADD COLUMN data TEXT NOT NULL DEFAULT '';
]])
	for _, r in ipairs(db:query("SELECT id, effects FROM spells ORDER BY id")) do
		local kind, power = v7_effects(r.effects)
		db:exec("UPDATE spells SET power = ?, target = ? WHERE id = ?", power, V7_SELF[kind] and "self" or "enemy", r.id)
	end
	for _, r in ipairs(db:query("SELECT id, use_effects FROM items WHERE category = 'consumable' ORDER BY id")) do
		local kind, power, town = v7_effects(r.use_effects)
		db:exec("UPDATE items SET power = ?, target = ?, usable_in = ? WHERE id = ?", power,
						V7_SELF[kind] and "self" or "enemy", town and "both" or "fight", r.id)
	end
	-- effect amounts -> power (fixed table names)
	for _, tbl in ipairs({ "content_overrides", "content_adopt" }) do
		local rows = db:query("SELECT kind, key, field, value FROM " .. tbl .. " WHERE (kind = 'spells' AND field LIKE " ..
													"'effects.%') OR (kind = 'items' AND field LIKE 'use_effects.%') ORDER BY kind, key, field")
		for _, r in ipairs(rows) do
			db:exec("DELETE FROM " .. tbl .. " WHERE kind = ? AND key = ? AND field = ?", r.kind, r.key, r.field)
			local i, param = r.field:match("^[%a_]+%.(%d+)%.([%a_]+)$")
			if i == "1" and (param == "amount" or param == "max" or param == "chance" or param == "pct") then
				db:exec("INSERT OR REPLACE INTO " .. tbl .. " (kind, key, field, value) VALUES (?, ?, 'power', ?)",
								r.kind, r.key, r.value)
			else
				print(("warning: %s %s: the edit of %s (%s) can't be kept: spells and items are scripted now, " ..
					"with one power"):format(r.kind == "spells" and "spell" or "item", r.key, r.field, r.value))
			end
		end
	end
	db:exec_script([[
ALTER TABLE spells DROP COLUMN effects;
ALTER TABLE items DROP COLUMN use_effects;
]])
end

-- 8: the fight engine (app/fight/: round pipeline, statuses, summons). A fight in progress
-- moves from the users row's current* columns into fights, fight_combatants and
-- fight_statuses: the player is combatant 1, the monster (when picked; a deleted one is
-- left out, so the fight starts over as before) combatant 2 with its HP and immunity, the
-- monster's sleep and the player's uber damage/defense buffs statuses 1-3 (sleep,
-- uber_damage, uber_defense: rows created here, filled in by the content sync). Statuses
-- and summons become content kinds; world statuses (user_statuses); control.max_allies.
-- A player mid-fight goes on with the same fight.
local function v8_fight_engine()
	local db = dk.db
	db:exec_script([[
CREATE TABLE statuses (
	id             INTEGER PRIMARY KEY,
	key            TEXT    NOT NULL UNIQUE,
	name           TEXT    NOT NULL DEFAULT '',
	description    TEXT    NOT NULL DEFAULT '',
	kind           TEXT    NOT NULL DEFAULT 'neutral',
	tick_on        TEXT    NOT NULL DEFAULT 'turn_end',
	scope          TEXT    NOT NULL DEFAULT 'fight',
	turns          INTEGER NOT NULL DEFAULT 0,
	blocks_action  INTEGER NOT NULL DEFAULT 0,
	retired        INTEGER NOT NULL DEFAULT 0,
	messages       TEXT    NOT NULL DEFAULT '',
	data           TEXT    NOT NULL DEFAULT ''
);
CREATE TABLE summons (
	id           INTEGER PRIMARY KEY,
	key          TEXT    NOT NULL UNIQUE,
	name         TEXT    NOT NULL DEFAULT '',
	description  TEXT    NOT NULL DEFAULT '',
	hp           INTEGER NOT NULL DEFAULT 1,
	attack       INTEGER NOT NULL DEFAULT 0,
	defense      INTEGER NOT NULL DEFAULT 0,
	dexterity    INTEGER NOT NULL DEFAULT 0,
	turns        INTEGER NOT NULL DEFAULT 0,
	retired      INTEGER NOT NULL DEFAULT 0,
	messages     TEXT    NOT NULL DEFAULT '',
	data         TEXT    NOT NULL DEFAULT ''
);
CREATE TABLE fights (
	user_id  INTEGER PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
	round    INTEGER NOT NULL DEFAULT 1,
	wave     INTEGER NOT NULL DEFAULT 1,
	data     TEXT    NOT NULL DEFAULT ''
);
CREATE TABLE fight_combatants (
	user_id     INTEGER NOT NULL REFERENCES fights (user_id) ON DELETE CASCADE,
	id          INTEGER NOT NULL,
	side        TEXT    NOT NULL,
	kind        TEXT    NOT NULL,
	entity_id   INTEGER,
	wave        INTEGER NOT NULL DEFAULT 0,
	hp          INTEGER,
	maxhp       INTEGER,
	turns_left  INTEGER,
	data        TEXT    NOT NULL DEFAULT '',
	PRIMARY KEY (user_id, id)
) WITHOUT ROWID;
CREATE TABLE fight_statuses (
	user_id        INTEGER NOT NULL,
	combatant_id   INTEGER NOT NULL,
	status_id      INTEGER NOT NULL REFERENCES statuses (id),
	position       INTEGER NOT NULL,
	turns_left     INTEGER,
	data           TEXT    NOT NULL DEFAULT '',
	applied_round  INTEGER NOT NULL DEFAULT 0,
	source         INTEGER,
	PRIMARY KEY (user_id, combatant_id, status_id),
	FOREIGN KEY (user_id, combatant_id) REFERENCES fight_combatants (user_id, id) ON DELETE CASCADE
) WITHOUT ROWID;
CREATE TABLE user_statuses (
	user_id     INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	status_id   INTEGER NOT NULL REFERENCES statuses (id),
	position    INTEGER NOT NULL,
	turns_left  INTEGER,
	data        TEXT    NOT NULL DEFAULT '',
	PRIMARY KEY (user_id, status_id)
) WITHOUT ROWID;
ALTER TABLE control ADD COLUMN max_allies INTEGER NOT NULL DEFAULT 1;
INSERT INTO statuses (id, key, name) VALUES (1, 'sleep', 'Asleep');
INSERT INTO statuses (id, key, name) VALUES (2, 'uber_damage', 'Damage Up');
INSERT INTO statuses (id, key, name) VALUES (3, 'uber_defense', 'Defense Up');
]])
	local moved = 0
	for _, u in ipairs(db:query("SELECT id, currentfight, currentmonster, currentmonsterhp, currentmonstersleep, " ..
			"currentmonsterimmune, currentuberdamage, currentuberdefense FROM users WHERE currentfight > 0 ORDER BY id")) do
		db:exec("INSERT INTO fights (user_id, round, wave, data) VALUES (?, ?, 1, '')", u.id, u.currentfight)
		db:exec("INSERT INTO fight_combatants (user_id, id, side, kind) VALUES (?, 1, 'player', 'player')", u.id)
		local m = u.currentmonster ~= 0 and db:first("SELECT id, maxhp FROM monsters WHERE id = ?", u.currentmonster)
		if m then
			-- "name=i:value" lines: fight/state.lua state.encode
			db:exec("INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, wave, hp, maxhp, data) " ..
				"VALUES (?, 2, 'enemy', 'monster', ?, 1, ?, ?, ?)", u.id, m.id, u.currentmonsterhp, m.maxhp,
				"immune=i:" .. u.currentmonsterimmune)
			if u.currentmonstersleep ~= 0 then
				db:exec("INSERT INTO fight_statuses (user_id, combatant_id, status_id, position, data, applied_round) " ..
					"VALUES (?, 2, 1, 1, ?, ?)", u.id, "chance=i:" .. u.currentmonstersleep, u.currentfight)
			end
		end
		local pos = 0
		for _, b in ipairs({ { 2, u.currentuberdamage }, { 3, u.currentuberdefense } }) do
			if b[2] ~= 0 then
				pos = pos + 1
				db:exec("INSERT INTO fight_statuses (user_id, combatant_id, status_id, position, data, applied_round) " ..
					"VALUES (?, 1, ?, ?, ?, ?)", u.id, b[1], pos, "pct=i:" .. b[2], u.currentfight)
			end
		end
		moved = moved + 1
	end
	if moved > 0 then print(("Moved %d fight%s in progress to the new fight tables."):format(moved, moved == 1 and "" or "s")) end
	db:exec_script([[
ALTER TABLE users DROP COLUMN currentfight;
ALTER TABLE users DROP COLUMN currentmonster;
ALTER TABLE users DROP COLUMN currentmonsterhp;
ALTER TABLE users DROP COLUMN currentmonstersleep;
ALTER TABLE users DROP COLUMN currentmonsterimmune;
ALTER TABLE users DROP COLUMN currentuberdamage;
ALTER TABLE users DROP COLUMN currentuberdefense;
]])
end

-- 9: monsters become content (app/content/monsters/<key>.lua, synced into monsters) with
-- MP, equipment, items and spells (the loadout tables monster_equipment, monster_items,
-- monster_spells). The table is rebuilt with key, description, maxmp, uses_mp,
-- attack_weight, roams and retired; the original monsters keep ids 1-151 and get their keys
-- (from the original names), so fights in progress keep their monster. Admin edits of the
-- original monsters' stats go to content_adopt (kept as overrides by the sync at the end of
-- `dk migrate` where they differ from the files and are valid). Other monster rows (added
-- by hand) keep their ids and stats under the key monster_<id> and are retired by the sync:
-- fights against them go on, but they are no longer met (a content file with that key
-- brings one back, same id; reported). Their maxmp is the Mage's MP at their level (at
-- least 5), like the files' (V9_MAXMP). A monster's MP in a fight is fight_combatants.mp / maxmp (NULL
-- in the fights moved here: full).
local V9_MONSTERS = {
	"blue_slime", "red_slime", "critter", "creature", "shadow", "drake", "shade", "drakelor", "silver_slime",
	"scamp", "raven", "scorpion", "illusion", "nightshade", "drakemal", "shadow_raven", "ghost", "frost_raven",
	"rogue_scorpion", "ghoul", "magician", "rogue", "drakefin", "shimmer", "fire_raven", "dybbuk", "knave",
	"goblin", "skeleton", "dark_slime", "silver_scorpion", "mirage", "sorceror", "imp", "nymph", "scoundrel",
	"megaskeleton", "grey_wolf", "phantom", "specter", "dark_scorpion", "warlock", "orc", "sylph", "wraith",
	"hellion", "bandit", "ultraskeleton", "dark_wolf", "troll", "werewolf", "hellcat", "spirit", "nisse", "dawk",
	"figment", "hellhound", "wizard", "uruk", "siren", "megawraith", "dawkin", "grey_bear", "haunt", "hellbeast",
	"fear", "beast", "ogre", "dark_bear", "fire", "polgergeist", "fright", "lycan", "terra_elemental",
	"necromancer", "ultrawraith", "dawkor", "werebear", "brute", "large_beast", "horror", "flame", "lycanthor",
	"wyrm", "aero_elemental", "dawkare", "large_brute", "frost_wyrm", "knight", "lycanthra", "terror", "blaze",
	"aqua_elemental", "fire_wyrm", "lesser_wyvern", "doomer", "armor_knight", "wyvern", "nightmare",
	"fira_elemental", "megadoomer", "greater_wyvern", "advocate", "strong_knight", "liche", "ultradoomer",
	"fanatic", "green_dragon", "fiend", "greatest_wyvern", "lesser_devil", "liche_master", "zealot", "serafiend",
	"pale_knight", "blue_dragon", "obsessive", "devil", "liche_prince", "cherufiend", "red_dragon",
	"greater_devil", "renegade", "archfiend", "liche_lord", "greatest_devil", "dark_knight", "giant",
	"shadow_dragon", "liche_king", "incubus", "traitor", "demon", "dark_dragon", "insurgent", "leviathan",
	"grey_daemon", "succubus", "demon_prince", "black_dragon", "nihilist", "behemoth", "demagogue", "demon_lord",
	"red_daemon", "colossus", "demon_king", "dark_daemon", "titan", "black_daemon", "lucifuge",
}
local V9_ADOPT = { "name", "maxhp", "maxdam", "armor", "level", "maxexp", "maxgold", "immune" }
-- maxmp per level 1-100: the Mage's MP at that level (app/content/classes/mage.lua as of
-- version 9: start + gains), at least 5; what the monster files were written with
local V9_MAXMP = {
	5, 5, 9, 12, 17, 22, 26, 30, 33, 36, 38, 40, 43, 47, 52, 55, 57, 59, 64, 70, 74, 79, 82, 87, 91,
	94, 96, 98, 101, 105, 110, 114, 118, 122, 125, 128, 132, 137, 141, 144, 147, 151, 156, 159, 167,
	172, 176, 180, 183, 186, 188, 190, 192, 196, 200, 204, 209, 214, 217, 221, 226, 230, 235, 240,
	244, 248, 251, 254, 258, 262, 267, 269, 273, 278, 281, 284, 288, 292, 296, 301, 304, 308, 310,
	314, 318, 323, 327, 332, 334, 336, 339, 342, 346, 350, 353, 356, 360, 365, 370, 370,
}

local function v9_monsters_content()
	local db = dk.db
	local old = db:query("SELECT * FROM monsters ORDER BY id")
	db:exec_script([[
CREATE TABLE monsters_new (
	id             INTEGER PRIMARY KEY,
	key            TEXT    NOT NULL UNIQUE,
	name           TEXT    NOT NULL DEFAULT '',
	description    TEXT    NOT NULL DEFAULT '',
	maxhp          INTEGER NOT NULL DEFAULT 1,
	maxdam         INTEGER NOT NULL DEFAULT 0,
	armor          INTEGER NOT NULL DEFAULT 0,
	level          INTEGER NOT NULL DEFAULT 1,
	maxexp         INTEGER NOT NULL DEFAULT 0,
	maxgold        INTEGER NOT NULL DEFAULT 0,
	immune         INTEGER NOT NULL DEFAULT 0,
	maxmp          INTEGER NOT NULL DEFAULT 0,
	uses_mp        INTEGER NOT NULL DEFAULT 1,
	attack_weight  INTEGER NOT NULL DEFAULT 1,
	roams          INTEGER NOT NULL DEFAULT 1,
	retired        INTEGER NOT NULL DEFAULT 0
);
]])
	local seen, others = {}, {}
	for _, m in ipairs(old) do
		local key = V9_MONSTERS[m.id] or ("monster_" .. m.id)
		db:exec("INSERT INTO monsters_new (id, key, name, maxhp, maxdam, armor, level, maxexp, maxgold, immune, maxmp) " ..
			"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", m.id, key, m.name, m.maxhp, m.maxdam, m.armor, m.level, m.maxexp,
			m.maxgold, m.immune, V9_MAXMP[math.min(math.max(m.level, 1), #V9_MAXMP)])
		seen[m.id] = true
		if V9_MONSTERS[m.id] then
			for _, field in ipairs(V9_ADOPT) do
				db:exec("INSERT INTO content_adopt (kind, key, field, value) VALUES ('monsters', ?, ?, ?)", key, field,
					tostring(m[field]))
			end
		else
			others[#others + 1] = ("%d %s (%s)"):format(m.id, tostring(m.name), key)
		end
	end
	-- partial installs had no monsters: the original ids get their keys (the sync fills in the rest)
	for id, key in ipairs(V9_MONSTERS) do
		if not seen[id] then db:exec("INSERT INTO monsters_new (id, key) VALUES (?, ?)", id, key) end
	end
	db:exec_script([[
DROP TABLE monsters;
ALTER TABLE monsters_new RENAME TO monsters;
DELETE FROM sqlite_sequence WHERE name = 'monsters';
CREATE INDEX monsters_level ON monsters (level);
CREATE TABLE monster_equipment (
	monster_id  INTEGER NOT NULL REFERENCES monsters (id),
	slot        TEXT    NOT NULL,
	item_id     INTEGER NOT NULL REFERENCES items (id),
	PRIMARY KEY (monster_id, slot)
) WITHOUT ROWID;
CREATE TABLE monster_items (
	monster_id  INTEGER NOT NULL REFERENCES monsters (id),
	position    INTEGER NOT NULL,
	item_id     INTEGER NOT NULL REFERENCES items (id),
	weight      INTEGER NOT NULL DEFAULT 1,
	stock       INTEGER,
	has_when    INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (monster_id, position)
) WITHOUT ROWID;
CREATE TABLE monster_spells (
	monster_id  INTEGER NOT NULL REFERENCES monsters (id),
	position    INTEGER NOT NULL,
	spell_id    INTEGER NOT NULL REFERENCES spells (id),
	weight      INTEGER NOT NULL DEFAULT 1,
	has_when    INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (monster_id, position)
) WITHOUT ROWID;
ALTER TABLE fight_combatants ADD COLUMN mp INTEGER;
ALTER TABLE fight_combatants ADD COLUMN maxmp INTEGER;
]])
	for _, o in ipairs(others) do
		print(("warning: monster %s has no content file and is retired (fights against it go on; it is no longer " ..
			"met). Write app/content/monsters/%s.lua to bring it back."):format(o, o:match("%(([%w_]+)%)$")))
	end
end

-- 10: realtime (2.3): babble.author_id (by charname, like forum posts in step 1) for the
-- chat's rate limit and deletions, users.online (presence; players seen within the last 10
-- minutes count as announced), the broadcast banner in control.
local function v10_realtime()
	local db = dk.db
	db:exec_script([[
ALTER TABLE babble ADD COLUMN author_id INTEGER REFERENCES users (id) ON DELETE SET NULL;
UPDATE babble SET author_id = (SELECT min(u.id) FROM users u WHERE u.charname = babble.author);
CREATE INDEX babble_author ON babble (author_id, posttime);
ALTER TABLE users ADD COLUMN online INTEGER NOT NULL DEFAULT 0;
ALTER TABLE control ADD COLUMN banner TEXT NOT NULL DEFAULT '';
ALTER TABLE control ADD COLUMN banner_id INTEGER NOT NULL DEFAULT 0;
ALTER TABLE control ADD COLUMN banner_expires INTEGER NOT NULL DEFAULT 0;
]])
	db:exec("UPDATE users SET online = 1 WHERE onlinetime >= ?", dk.now() - 600)
end

-- 11: who's online is read through a partial index of the players online (every game page
-- counts them, the town page lists them) instead of a scan of every account.
local function v11_online_index()
	dk.db:exec("CREATE INDEX users_online ON users (charname, id) WHERE online = 1")
end

-- 12: spell icons (2.3.1): spells.icon, the PNG in public/images/skills/ of the fight and
-- Fast Spells buttons ('' = default.png). The content sync that ends the migration fills
-- it in from the spell files.
local function v12_spell_icons()
	dk.db:exec("ALTER TABLE spells ADD COLUMN icon TEXT NOT NULL DEFAULT ''")
end

-- 13: lore (2.4): every content table gets `lore`, the optional story text of tooltips and
-- the help pages ('' = none). The content sync that ends the migration fills it in.
local function v13_lore()
	for _, t in ipairs({ "classes", "items", "monsters", "spells", "statuses", "summons" }) do
		dk.db:exec("ALTER TABLE " .. t .. " ADD COLUMN lore TEXT NOT NULL DEFAULT ''")
	end
end

-- 14: the first item with an effect (2.4): classes.start_spells (spells a new character
-- knows), items.casts/charges/icon (gear that casts a spell with charges; item icons) and
-- user_items.charges (each item's own). The Mage now starts with 5 MP (its level gains are
-- the same): existing Mages get +5 base max MP and +5 current MP (not above the maximum),
-- so every Mage has 5 + their level gains + equipment. After the sync: everyone learns
-- their class's starting spells (the Mage: Magic Bolt, at level 1), items that cast are
-- full, and Midworld sells the Wand.
local MAGE_START_MP = 5

local function v14_charged_items()
	dk.db:exec_script([[
ALTER TABLE classes ADD COLUMN start_spells TEXT NOT NULL DEFAULT '';
ALTER TABLE items ADD COLUMN casts TEXT NOT NULL DEFAULT '';
ALTER TABLE items ADD COLUMN charges INTEGER NOT NULL DEFAULT 0;
ALTER TABLE items ADD COLUMN icon TEXT NOT NULL DEFAULT '';
ALTER TABLE user_items ADD COLUMN charges INTEGER NOT NULL DEFAULT 0;
]])
	-- the spells after the original 19 get the ids a fresh install gives them (seed.sql),
	-- unless the database has spells of its own there (from before 2.2, when the sync numbers
	-- them after those, by key)
	local LATER = { { 20, "call_wolf" }, { 21, "hyper_beam" }, { 22, "poison" }, { 23, "regen" },
		{ 24, "solar_beam" }, { 25, "magic_bolt" } }
	local own = dk.db:value("SELECT count(*) FROM spells WHERE id >= 20 AND key NOT IN " ..
		"('call_wolf', 'hyper_beam', 'poison', 'regen', 'solar_beam', 'magic_bolt')")
	if own == 0 then
		for _, s in ipairs(LATER) do dk.db:exec("INSERT OR IGNORE INTO spells (id, key) VALUES (?, ?)", s[1], s[2]) end
	end
end

local function v14_after_sync()
	local db = dk.db
	local inventory = require("lib.inventory")
	-- after the sync (and step 6's, which keeps older characters' stats as they were): base
	-- max MP +5, current MP +5 up to the new maximum (never lowering MP already above it)
	for _, u in ipairs(db:query("SELECT * FROM users WHERE charclass IN (SELECT id FROM classes WHERE key = 'mage')")) do
		u.base_maxmp = u.base_maxmp + MAGE_START_MP
		local max = inventory.stats(u).maxmp
		local mp = math.max(u.currentmp, math.min(u.currentmp + MAGE_START_MP, max))
		db:exec("UPDATE users SET base_maxmp = ?, currentmp = ? WHERE id = ?", u.base_maxmp, mp, u.id)
	end
	for _, c in ipairs(db:query("SELECT id, start_spells FROM classes WHERE start_spells <> ''")) do
		for key in c.start_spells:gmatch("[^,]+") do
			db:exec("INSERT OR IGNORE INTO user_spells (user_id, spell_id, learned_level) " ..
				"SELECT u.id, s.id, 1 FROM users u, spells s WHERE u.charclass = ? AND s.key = ?", c.id, key)
		end
	end
	db:exec("UPDATE user_items SET charges = (SELECT i.charges FROM items i WHERE i.id = user_items.item_id) " ..
		"WHERE item_id IN (SELECT id FROM items WHERE charges > 0)")
	-- (after the sync: the latest schema, where shop lists name items by key)
	db:exec("INSERT OR IGNORE INTO town_items (town_id, item_key) SELECT id, 'wand' FROM towns WHERE id = 1")
end

-- 15: pure GETs (3.0): a fight keeps its outcome, its last round's lines and a victory's
-- rewards (a finished fight stays for its page). GET /fight used to pick the monster of an
-- encounter that had just begun, and GET /victory paid the rewards: an encounter still
-- waiting for its monster is cancelled (the player is exploring again, where they were),
-- and after the sync a won fight that wasn't paid yet is paid, as the winning round does now.
local function v15_pure_gets()
	dk.db:exec_script([[
ALTER TABLE fights ADD COLUMN outcome TEXT NOT NULL DEFAULT '';
ALTER TABLE fights ADD COLUMN log TEXT NOT NULL DEFAULT '';
ALTER TABLE fights ADD COLUMN result TEXT NOT NULL DEFAULT '';
UPDATE users SET currentaction = 'Exploring' WHERE currentaction = 'Fighting' AND id IN (SELECT f.user_id FROM fights f
	WHERE NOT EXISTS (SELECT 1 FROM fight_combatants c WHERE c.user_id = f.user_id AND c.side = 'enemy'));
DELETE FROM fights WHERE NOT EXISTS (SELECT 1 FROM fight_combatants c WHERE c.user_id = fights.user_id AND c.side = 'enemy');
]])
end

local function v15_after_sync()
	local encounter = require("fight.encounter")
	local game = require("lib.game")
	local state = require("fight.state")
	for _, u in ipairs(dk.db:query("SELECT u.* FROM users u JOIN fights f ON f.user_id = u.id " ..
		"WHERE f.outcome = '' AND u.currentaction = 'Fighting' ORDER BY u.id")) do
		local f = state.load(u, game.player(u))
		if f and #state.side(f, "enemy", true) > 0 and state.won(f) then encounter.win(u, f, nil) end
	end
end

-- 16: items that cast a spell may be single use (items.rechargeable; every item so far is
-- rechargeable).
local function v16_rechargeable()
	dk.db:exec("ALTER TABLE items ADD COLUMN rechargeable INTEGER NOT NULL DEFAULT 1")
end

-- 17: the hotbar (3.1, lib/hotbar.lua): the fight actions each character has met and where
-- they are on the bar. Empty: each bar fills itself from what its character has when their
-- next fight begins.
local function v17_hotbar()
	dk.db:exec_script([[
CREATE TABLE user_hotbar (
	user_id  INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	kind     TEXT    NOT NULL,
	ref_id   INTEGER NOT NULL,
	slot     INTEGER,
	PRIMARY KEY (user_id, kind, ref_id)
) WITHOUT ROWID;
CREATE UNIQUE INDEX user_hotbar_slot ON user_hotbar (user_id, slot);
]])
end

-- 18: towns sell only some maps (town_maps; every town sold every map): each its
-- neighbours' along the road, the towns before and after it by id (the seed's rows on the
-- original towns; an admin's towns get the same rule).
local function v18_town_maps()
	dk.db:exec_script([[
CREATE TABLE town_maps (
	town_id  INTEGER NOT NULL REFERENCES towns (id),
	map_id   INTEGER NOT NULL REFERENCES towns (id),
	PRIMARY KEY (town_id, map_id)
) WITHOUT ROWID;
INSERT INTO town_maps (town_id, map_id)
	SELECT t.id, n.id FROM towns t JOIN towns n
	ON n.id = (SELECT max(id) FROM towns WHERE id < t.id) OR n.id = (SELECT min(id) FROM towns WHERE id > t.id);
]])
end

-- 19: shop lists name items by key (town_items.item_key; before, by id), so a list can
-- name an item the content sync hasn't added yet and nothing depends on the order ids are
-- given in; and the towns (by their original ids) sell the 3.1 wares, plus the Antidote and
-- the Regen Potion, which no shop sold. The same lists as a fresh install's (seed.sql).
local V19_WARES = {
	[1] = { "antidote", "copper_ring", "trail_snack", "travel_tea" },
	[2] = { "antidote", "apprentice_robe", "copper_ring", "fire_flask", "parry_buckler",
		"scouts_jerkin", "sickle", "sleep_powder", "spark_rod", "trail_snack", "travel_tea",
		"traveller_ring" },
	[3] = { "acid_vial", "antidote", "apprentice_robe", "fire_flask", "hi_potion", "lucky_charm",
		"parry_buckler", "regen_potion", "scouts_jerkin", "sickle", "sleep_powder", "spiked_targe",
		"trail_snack", "travel_tea", "traveller_ring" },
	[4] = { "acid_vial", "antidote", "fire_flask", "frost_staff", "hi_potion", "ironclad_plate",
		"lamellar_armor", "lucky_charm", "regen_potion", "sleep_powder", "spiked_targe",
		"strength_tonic", "travel_tea", "traveller_ring", "war_pick", "weakening_dust" },
	[5] = { "acid_vial", "bitter_draught", "cure_all", "ember_staff", "fire_flask", "guard_tonic",
		"hi_ether", "hi_potion", "ironclad_plate", "lamellar_armor", "lucky_charm", "strength_tonic",
		"ward_charm", "warhammer", "weakening_dust" },
	[6] = { "bitter_draught", "cure_all", "greatsword", "guard_tonic", "hi_ether", "hi_potion",
		"ironclad_plate", "lifeward_shield", "ogre_hide_cuirass", "strength_tonic", "vigil_cuirass",
		"war_sabre", "ward_charm", "ward_shield", "warhammer", "weakening_dust" },
	[7] = { "bitter_draught", "cure_all", "dawn_mace", "elixir", "glass_blade", "guard_tonic",
		"hi_ether", "lifeward_shield", "ogre_hide_cuirass", "sunsteel_mail", "tower_shield",
		"vigil_cuirass", "void_flask", "war_sabre", "ward_shield" },
	[8] = { "cure_all", "dragonhide_shield", "elixir", "starsteel_sword", "storm_lance",
		"void_flask" },
}

local function v19_shop_keys()
	local db = dk.db
	db:exec_script([[
CREATE TABLE town_items_new (
	town_id   INTEGER NOT NULL REFERENCES towns (id),
	item_key  TEXT    NOT NULL,
	PRIMARY KEY (town_id, item_key)
) WITHOUT ROWID;
INSERT INTO town_items_new (town_id, item_key) SELECT t.town_id, i.key FROM town_items t JOIN items i ON i.id = t.item_id;
DROP TABLE town_items;
ALTER TABLE town_items_new RENAME TO town_items;
]])
	-- the items after the original drops get the ids a fresh install gives them (seed.sql),
	-- where those ids and keys are free (before, the sync numbered them by key after the
	-- originals, which only matched while no other new key sorted among theirs)
	for _, it in ipairs({ { 69, "antidote", "Antidote" }, { 70, "regen_potion", "Regen Potion" }, { 71, "wand", "Wand" } }) do
		db:exec("INSERT OR IGNORE INTO items (id, key, name) VALUES (?, ?, ?)", it[1], it[2], it[3])
	end
	for town, keys in ipairs(V19_WARES) do
		for _, key in ipairs(keys) do
			db:exec("INSERT OR IGNORE INTO town_items (town_id, item_key) SELECT id, ? FROM towns WHERE id = ?", key, town)
		end
	end
end

-- 20: monsters, statuses and allies have icons (3.1), like spells and items: the name of a
-- PNG in public/images/<monsters|statuses|summons>/; the content sync fills them in.
local function v20_more_icons()
	for _, t in ipairs({ "monsters", "statuses", "summons" }) do
		dk.db:exec("ALTER TABLE " .. t .. " ADD COLUMN icon TEXT NOT NULL DEFAULT ''")
	end
end

-- 21: elements and wards (3.2, lib/elements.lua): monsters, statuses and summons resist
-- elements and ward off statuses (resist, ward), weapons and summons have an element,
-- monsters an attack element and a class. monsters.immune goes: 1 becomes a resistance of
-- 100 to arcane (the hurt spells' element), 2 that and a ward of 100 against sleep, on the
-- rows (a retired monster keeps its immunity) and in admins' overrides of it (an override
-- where the result differs from the file's) and pending adoptions (only what differs from
-- the original game's immunity, V21_STOCK_IMMUNE: the files' affinities have since changed,
-- and a stock database's immunity is no edit).

-- the original monsters' immune where it isn't 0 (the monsters table as installed)
local V21_STOCK_IMMUNE = {
	shadow = 1, shade = 1, silver_slime = 2, illusion = 1, shadow_raven = 1, shimmer = 1, silver_scorpion = 2,
	mirage = 1, phantom = 1, dark_scorpion = 1, warlock = 1, dark_wolf = 1, figment = 1, siren = 2, dark_bear = 1,
	terra_elemental = 1, aero_elemental = 1, aqua_elemental = 1, fira_elemental = 1, incubus = 1, dark_dragon = 1,
	succubus = 1, black_dragon = 1, dark_daemon = 1, black_daemon = 1, lucifuge = 2,
}

local function v21_affinities(immune)
	return { { "resist.arcane", immune >= 1 and 100 or 0 }, { "ward.sleep", immune == 2 and 100 or 0 } }
end

local function v21_elements_and_wards()
	local db = dk.db
	db:exec_script([[
ALTER TABLE items ADD COLUMN element TEXT NOT NULL DEFAULT 'neutral';
ALTER TABLE monsters ADD COLUMN resist TEXT NOT NULL DEFAULT '';
ALTER TABLE monsters ADD COLUMN ward TEXT NOT NULL DEFAULT '';
ALTER TABLE monsters ADD COLUMN attack_element TEXT NOT NULL DEFAULT 'neutral';
ALTER TABLE monsters ADD COLUMN class TEXT NOT NULL DEFAULT '';
UPDATE monsters SET resist = CASE WHEN immune <> 0 THEN 'arcane=100' ELSE '' END,
	ward = CASE WHEN immune = 2 THEN 'sleep=100' ELSE '' END;
ALTER TABLE monsters DROP COLUMN immune;
ALTER TABLE statuses ADD COLUMN resist TEXT NOT NULL DEFAULT '';
ALTER TABLE statuses ADD COLUMN ward TEXT NOT NULL DEFAULT '';
ALTER TABLE summons ADD COLUMN resist TEXT NOT NULL DEFAULT '';
ALTER TABLE summons ADD COLUMN ward TEXT NOT NULL DEFAULT '';
ALTER TABLE summons ADD COLUMN element TEXT NOT NULL DEFAULT 'neutral';
]])
	-- the monster files (read, not the database): an override equal to the file's is none
	local files = require("lib.content.load").kind("monsters").by_key
	for _, tbl in ipairs({ "content_overrides", "content_adopt" }) do
		for _, r in ipairs(db:query("SELECT key, value FROM " .. tbl .. " WHERE kind = 'monsters' AND field = 'immune' " ..
			"ORDER BY key")) do
			local immune = math.tointeger(tonumber(r.value)) or 0
			local file = files[r.key]
			local stock = v21_affinities(V21_STOCK_IMMUNE[r.key] or 0)
			for i, x in ipairs(v21_affinities(immune)) do
				local edited
				if tbl == "content_adopt" then edited = x[2] ~= stock[i][2] else edited = not file or (file[x[1]] or 0) ~= x[2] end
				if edited then
					db:exec("INSERT OR REPLACE INTO " .. tbl .. " (kind, key, field, value) VALUES ('monsters', ?, ?, ?)", r.key,
						x[1], tostring(x[2]))
				end
			end
		end
		db:exec("DELETE FROM " .. tbl .. " WHERE kind = 'monsters' AND field = 'immune'")
	end
end

-- 22: the server's tick and fights in real time (3.2, app/lib/tick.lua, fight/round.lua
-- round.advance): durations are clock ticks (statuses' and summons' turns become ticks,
-- one turn one tick; tick_on goes: statuses tick on the clock), fights save the last tick
-- they played, the player's turn deadline and when the tick must advance them next,
-- statuses the last tick they counted (world statuses tick on the clock too). Those in
-- progress get tick 0, not on the clock yet: the next POST /fight or server tick starts
-- them at its time (fight/round.lua round.advance, lib/world.lua world.advance), the turn
-- with its 30 seconds. Admins' overrides of turns become overrides of ticks. Guard takes
-- the hotbar's key 9: what was on it moves to the first free key of 2-8, or off the bar.
local function v22_fights_on_the_clock()
	local db = dk.db
	db:exec_script([[
ALTER TABLE statuses DROP COLUMN tick_on;
ALTER TABLE statuses RENAME COLUMN turns TO ticks;
ALTER TABLE summons RENAME COLUMN turns TO ticks;
ALTER TABLE fights ADD COLUMN tick INTEGER NOT NULL DEFAULT 0;
ALTER TABLE fights ADD COLUMN deadline INTEGER NOT NULL DEFAULT 0;
ALTER TABLE fights ADD COLUMN due INTEGER NOT NULL DEFAULT 0;
CREATE INDEX fights_due ON fights (due) WHERE outcome = '';
ALTER TABLE fight_combatants RENAME COLUMN turns_left TO ticks_left;
ALTER TABLE fight_statuses RENAME COLUMN turns_left TO ticks_left;
ALTER TABLE fight_statuses RENAME COLUMN applied_round TO tick;
ALTER TABLE user_statuses RENAME COLUMN turns_left TO ticks_left;
ALTER TABLE user_statuses ADD COLUMN tick INTEGER NOT NULL DEFAULT 0;
CREATE INDEX user_statuses_tick ON user_statuses (tick);
UPDATE fight_statuses SET tick = 0;
]])
	for _, tbl in ipairs({ "content_overrides", "content_adopt" }) do
		db:exec("UPDATE " .. tbl .. " SET field = 'ticks' WHERE kind IN ('statuses', 'summons') AND field = 'turns'")
		db:exec("DELETE FROM " .. tbl .. " WHERE kind = 'statuses' AND field = 'tick_on'")
	end
	for _, r in ipairs(db:query("SELECT user_id, kind, ref_id FROM user_hotbar WHERE slot = 9 ORDER BY user_id")) do
		local free = db:value("SELECT min(s) FROM (SELECT 2 AS s UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 " ..
			"UNION SELECT 6 UNION SELECT 7 UNION SELECT 8) WHERE s NOT IN (SELECT slot FROM user_hotbar " ..
			"WHERE user_id = ? AND slot IS NOT NULL)", r.user_id)
		db:exec("UPDATE user_hotbar SET slot = ? WHERE user_id = ? AND kind = ? AND ref_id = ?", free, r.user_id, r.kind,
			r.ref_id)
	end
end

-- 23: fields (3.2, app/fight/fields.lua): effects on the whole battlefield, the weather's
-- or a spell's, a content kind (the sync fills the table). A fight keeps the ones that are
-- up in its data, so fights in progress start without any and take the weather's at their
-- next tick. Monsters' loadout entries may weigh 0 (never chosen): nothing to convert.
local function v23_fields()
	dk.db:exec_script([[
CREATE TABLE fields (
	id           INTEGER PRIMARY KEY,
	key          TEXT    NOT NULL UNIQUE,
	name         TEXT    NOT NULL DEFAULT '',
	description  TEXT    NOT NULL DEFAULT '',
	lore         TEXT    NOT NULL DEFAULT '',
	icon         TEXT    NOT NULL DEFAULT '',
	"group"      TEXT    NOT NULL DEFAULT 'sky',
	damage       TEXT    NOT NULL DEFAULT '',
	stats        TEXT    NOT NULL DEFAULT '',
	statuses     TEXT    NOT NULL DEFAULT '',
	messages     TEXT    NOT NULL DEFAULT '',
	data         TEXT    NOT NULL DEFAULT '',
	retired      INTEGER NOT NULL DEFAULT 0
);
]])
end

-- 24: the 3.2 wares (gear that resists elements and wards off statuses, elemental blades and the
-- ward draughts): the same shop lists as a fresh install's (seed.sql), by key, added to the
-- towns' (by their original ids) without touching anything else they sell. A key no item
-- file has yet is simply not sold (items.town joins on the key).
local V24_WARES = {
	[2] = { "ember_ring", "serpent_ring", "wakeful_ring" },
	[3] = { "ember_ring", "fire_ward_draught", "frost_ward_draught", "rime_ring", "serpent_ring",
		"spark_ring", "wakeful_ring" },
	[4] = { "fire_ward_draught", "flame_charm", "frost_charm", "frost_ward_draught", "rime_ring",
		"rimefur_coat", "spark_ring", "storm_charm", "storm_ward_draught", "viper_charm", "wakeful_ring" },
	[5] = { "cinder_blade", "cinder_shield", "fire_ward_draught", "flame_charm", "frost_charm",
		"frost_ward_draught", "rimefur_coat", "shade_charm", "spark_ring", "storm_charm",
		"storm_ward_draught", "viper_charm", "wakeful_ring" },
	[6] = { "blessed_mace", "cinder_blade", "cinder_shield", "fire_ward_draught", "flame_charm",
		"frost_charm", "frost_ward_draught", "halo_charm", "sentinel_charm", "shade_charm",
		"storm_charm", "storm_ward_draught", "viper_charm" },
	[7] = { "blessed_mace", "fire_ward_draught", "halo_charm", "sentinel_charm", "shade_charm",
		"storm_charm", "storm_ward_draught" },
	[8] = { "fire_ward_draught", "halo_charm", "sentinel_charm" },
}

local function v24_wares()
	for town, keys in pairs(V24_WARES) do
		for _, key in ipairs(keys) do
			dk.db:exec("INSERT OR IGNORE INTO town_items (town_id, item_key) SELECT id, ? FROM towns WHERE id = ?", key, town)
		end
	end
end

-- 25: interactables (3.3, docs/plans/interactables.md): objects on the battlefield, a content
-- kind (the sync fills the table), standing in a fight as its combatants of side and kind
-- 'object' (their level and the side they stand over in the new columns); the fields' wind,
-- spells' and items' area, and the monsters' loadout entries that aim at an object. Fights in
-- progress have no objects and their target is the first living enemy, as before: nothing to
-- convert.
local function v25_interactables()
	dk.db:exec_script([[
CREATE TABLE interactables (
	id            INTEGER PRIMARY KEY,
	key           TEXT    NOT NULL UNIQUE,
	name          TEXT    NOT NULL DEFAULT '',
	description   TEXT    NOT NULL DEFAULT '',
	lore          TEXT    NOT NULL DEFAULT '',
	icon          TEXT    NOT NULL DEFAULT '',
	hp            INTEGER NOT NULL DEFAULT 1,
	hp_per_level  INTEGER NOT NULL DEFAULT 0,
	resist        TEXT    NOT NULL DEFAULT '',
	ward          TEXT    NOT NULL DEFAULT '',
	spawn         TEXT    NOT NULL DEFAULT '',
	messages      TEXT    NOT NULL DEFAULT '',
	data          TEXT    NOT NULL DEFAULT '',
	retired       INTEGER NOT NULL DEFAULT 0
);
ALTER TABLE fields ADD COLUMN wind INTEGER NOT NULL DEFAULT 0;
ALTER TABLE spells ADD COLUMN area INTEGER NOT NULL DEFAULT 0;
ALTER TABLE items ADD COLUMN area INTEGER NOT NULL DEFAULT 0;
ALTER TABLE monster_items ADD COLUMN aim TEXT NOT NULL DEFAULT '';
ALTER TABLE monster_spells ADD COLUMN aim TEXT NOT NULL DEFAULT '';
ALTER TABLE fight_combatants ADD COLUMN level INTEGER;
ALTER TABLE fight_combatants ADD COLUMN over TEXT;
]])
end

-- 26: the 3.3 ware: the Explosive Barrel in the shops of Kalle, Narcissa and Gilead (a fresh
-- install's lists, seed.sql), added to the towns' by key without touching anything else they
-- sell. Nothing else changes: the objects are content files.
local V26_WARES = {
	[4] = { "explosive_barrel" },
	[5] = { "explosive_barrel" },
	[7] = { "explosive_barrel" },
}

local function v26_wares()
	for town, keys in pairs(V26_WARES) do
		for _, key in ipairs(keys) do
			dk.db:exec("INSERT OR IGNORE INTO town_items (town_id, item_key) SELECT id, ? FROM towns WHERE id = ?", key, town)
		end
	end
end

-- 27: the World Map's fog of war (lib/explored.lua): what each character has mapped, a bitmap
-- of the map's cells; every character has mapped where they stand (their towns are mapped
-- by users.towns).
local function v27_explored()
	dk.db:exec_script([[
CREATE TABLE user_explored (
	user_id  INTEGER PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
	cells    TEXT    NOT NULL DEFAULT ''
);
]])
	local explored = require("lib.explored")
	for _, u in ipairs(dk.db:query("SELECT id, latitude, longitude FROM users ORDER BY id")) do
		local set = {}
		for _, i in ipairs(explored.around(u.latitude, u.longitude)) do set[i] = true end
		dk.db:exec("INSERT INTO user_explored (user_id, cells) VALUES (?, ?)", u.id, explored.encode(set))
	end
end

migrations.STEPS = {
	{ name = "forum boards; news titles, authors and discussion threads", up = v1_boards_and_news_threads },
	{ name = "remove difficulty levels", up = v2_drop_difficulty },
	{ name = "experience, TP and HP milestones per level are formulas (edited exp/tp values are discarded)",
		up = v3_leveling_formulas },
	{ name = "character classes are content files (class names and level data become classes, " ..
		"class_levels and class_spells; admin edits are kept as overrides)", up = v4_classes_content },
	{ name = "spells are content files with effects; the spells characters know move to user_spells " ..
		"(admin edits are kept as overrides)", up = v5_spells_content },
	{ name = "items and drops are content files; inventories (user_items), shop lists (town_items) and " ..
		"base stats (admin edits are kept as overrides)", up = v6_items_content, after_sync = v6_after_sync },
	{ name = "spells and consumables are scripted content (their effects become code in the content files; " ..
		"edited amounts are kept as power overrides)", up = v7_scripted },
	{ name = "the fight engine: fights in progress move to their own tables (sleep and the damage/defense " ..
		"buffs become statuses); statuses and summons are content files", up = v8_fight_engine },
	{ name = "monsters are content files with MP, equipment, items and spells (admin edits are kept as " ..
		"overrides; fights in progress keep their monster)", up = v9_monsters_content },
	{ name = "realtime: chat messages keep their author's account, who's online is kept live, and " ..
		"the broadcast banner", up = v10_realtime },
	{ name = "who's online is read from an index of the players online", up = v11_online_index },
	{ name = "spells have icons (the fight and Fast Spells buttons)", up = v12_spell_icons },
	{ name = "classes, spells, items, monsters, statuses and summons have lore", up = v13_lore },
	{ name = "starting spells, items that cast spells with charges, item icons; Mages start with 5 MP " ..
		"(existing Mages get +5 MP and learn Magic Bolt), Midworld sells the Wand",
		up = v14_charged_items, after_sync = v14_after_sync },
	{ name = "GETs don't change the game: an encounter begins on the move, a victory is paid in the " ..
		"winning round, a finished fight is kept for its page (pending encounters are cancelled, won fights " ..
		"are paid)", up = v15_pure_gets, after_sync = v15_after_sync },
	{ name = "items that cast a spell may be single use (not rechargeable)", up = v16_rechargeable },
	{ name = "the hotbar: the fight actions each character puts on number keys", up = v17_hotbar },
	{ name = "towns sell only some maps: each its neighbours' along the road", up = v18_town_maps },
	{ name = "shop lists name items by key; the towns sell the 3.1 wares (and the Antidote and the Regen Potion)",
		up = v19_shop_keys },
	{ name = "monsters, statuses and allies have icons", up = v20_more_icons },
	{ name = "elements and wards: resistances and status wards in place of monsters' immunity (immune 1: arcane, " ..
		"2: arcane and sleep; admins' overrides kept), weapons' and attacks' elements, monster classes",
		up = v21_elements_and_wards },
	{ name = "fights in real time on the server's tick: durations in ticks, the turn's deadline (fights in progress " ..
		"start on the clock when next played), Guard on the hotbar's key 9 (what was there moves to a free key or off the bar)",
		up = v22_fights_on_the_clock },
	{ name = "fields: effects on the whole battlefield (the weather's and spells'), a content kind; monsters' " ..
		"loadout entries may weigh 0", up = v23_fields },
	{ name = "the 3.2 wares: gear that resists elements and wards off statuses, elemental blades and ward draughts " ..
		"in the towns' shops", up = v24_wares },
	{ name = "interactables: objects on the battlefield, a content kind and combatants of their own side; the fields' " ..
		"wind, area spells and items, monsters' loadout entries aiming at an object", up = v25_interactables },
	{ name = "the 3.3 ware: the Explosive Barrel in the shops of Kalle, Narcissa and Gilead", up = v26_wares },
	{ name = "the World Map's fog of war: the map's cells each character has mapped (where they stand, so far)",
		up = v27_explored },
}

migrations.VERSION = #migrations.STEPS

-- The database's schema version (PRAGMA user_version).
-- (kept for the request, lib/cache.lua: main.lua asks on every dispatch, a live answer's
-- redirects followed too; stamping it, a PRAGMA that sets, forgets it)
local version = require("lib.cache").store("schema_version", { size = 2 })
function migrations.current()
	return version:fetch(1, function() return dk.db:value("PRAGMA user_version") end)
end

function migrations.stamp(version)
	dk.db:exec(string.format("PRAGMA user_version = %d", version))
end

-- Whether the database has the game's tables at all.
function migrations.installed()
	return dk.db:value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'control'") ~= nil
end

return migrations
