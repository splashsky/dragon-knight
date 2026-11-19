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
-- tables (those follow the latest schema). Pure helpers are fine.
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

migrations.STEPS = {
	{ name = "forum boards; news titles, authors and discussion threads", up = v1_boards_and_news_threads },
	{ name = "remove difficulty levels", up = v2_drop_difficulty },
	{ name = "experience, TP and HP milestones per level are formulas (edited exp/tp values are discarded)",
		up = v3_leveling_formulas },
	{ name = "character classes are content files (class names and level data become classes, " ..
		"class_levels and class_spells; admin edits are kept as overrides)", up = v4_classes_content },
	{ name = "spells are content files with effects; the spells characters know move to user_spells " ..
		"(admin edits are kept as overrides)", up = v5_spells_content },
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
