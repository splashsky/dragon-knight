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
-- as admin overrides. New characters keep the starting stats they got before (the users
-- column defaults; the levels table's row 1 was only shown on the help page).
local V4_CLASSES = {
	{ key = "mage", name = "Mage", exp_base = 15, exp_stages = "2x2,1.5x8,1.25x5,1.125x28" },
	{ key = "warrior", name = "Warrior", exp_base = 18, exp_stages = "2x2,1.5x8,1.25x5,1.125x27" },
	{ key = "paladin", name = "Paladin", exp_base = 20, exp_stages = "2x2,1.5x8,1.25x6,1.125x25" },
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
			adopt("levels." .. row.id .. ".spells", spell > 0 and spell or "")
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
-- is a list of effects, lib/effects.lua) and the spells a character knows move from the
-- users.spells comma list to user_spells. The original spells keep ids 1-19 and get their
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
	local effects = require("lib.effects")
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
						r.price, r.attack, r.defense, effects.encode(r.modifiers), r.drop_level, r.price > 0 and 1 or 0)
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
	local effects = require("lib.effects")
	local stats = require("lib.stats")
	for _, e in ipairs(db:query("SELECT * FROM temp.v6_expected ORDER BY user_id")) do
		local u = db:first("SELECT * FROM users WHERE id = ?", e.user_id)
		local list = db:query("SELECT i.attack, i.defense, i.modifiers FROM user_items ui JOIN items i ON i.id = ui.item_id " ..
													"WHERE ui.user_id = ? AND ui.equipped IS NOT NULL", e.user_id)
		for _, it in ipairs(list) do it.modifiers = effects.decode(it.modifiers) end
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
}

migrations.VERSION = #migrations.STEPS

-- The database's schema version (PRAGMA user_version).
function migrations.current()
	return dk.db:value("PRAGMA user_version")
end

function migrations.stamp(version)
	dk.db:exec(string.format("PRAGMA user_version = %d", version))
end

-- Whether the database has the game's tables at all.
function migrations.installed()
	return dk.db:value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'control'") ~= nil
end

return migrations
