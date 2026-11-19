-- Dragon Knight schema (SQLite). Port of the original install.php: same tables (no dk_ prefix)
-- and column names. Dates are unix seconds (INTEGER). Text comparisons on username,
-- charname and email are case-insensitive like the original MySQL collation.
-- This is the latest schema (`dk install` sets PRAGMA user_version to
-- migrations.VERSION); change it together with a new migration in app/lib/migrations.lua.

CREATE TABLE babble (
	id        INTEGER PRIMARY KEY AUTOINCREMENT,
	posttime  INTEGER NOT NULL DEFAULT 0,
	author    TEXT    NOT NULL DEFAULT '',
	babble    TEXT    NOT NULL DEFAULT ''
);

-- Character classes: content files app/content/classes/<key>.lua synced into these tables
-- (app/lib/content/sync.lua). Rows are never deleted: a class whose file is gone is
-- retired (existing characters keep it). users.charclass holds classes.id.
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

-- Gains on reaching a level (2 .. 100) per class; hp is without the milestone bonus, and
-- experience and TP are formulas (app/lib/leveling.lua).
CREATE TABLE class_levels (
	class_id   INTEGER NOT NULL REFERENCES classes (id),
	level      INTEGER NOT NULL,
	hp         INTEGER NOT NULL DEFAULT 0,
	mp         INTEGER NOT NULL DEFAULT 0,
	strength   INTEGER NOT NULL DEFAULT 0,
	dexterity  INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (class_id, level)
) WITHOUT ROWID;

-- Spells a class learns on reaching a level (the class files list spell keys).
CREATE TABLE class_spells (
	class_id  INTEGER NOT NULL REFERENCES classes (id),
	level     INTEGER NOT NULL,
	spell_id  INTEGER NOT NULL REFERENCES spells (id),
	PRIMARY KEY (class_id, level, spell_id)
) WITHOUT ROWID;

-- Admin overrides of content values (field: a content field like "name" or
-- "levels.17.hp"; value as text). They survive syncs; deleting one resets to the file.
CREATE TABLE content_overrides (
	kind   TEXT NOT NULL,
	key    TEXT NOT NULL,
	field  TEXT NOT NULL,
	value  TEXT NOT NULL,
	PRIMARY KEY (kind, key, field)
) WITHOUT ROWID;

-- Values a migration carried over from the old schema; the next sync turns those that
-- differ from the content file into overrides and deletes the rows.
CREATE TABLE content_adopt (
	kind   TEXT NOT NULL,
	key    TEXT NOT NULL,
	field  TEXT NOT NULL,
	value  TEXT NOT NULL,
	PRIMARY KEY (kind, key, field)
) WITHOUT ROWID;

-- Small key/value store: content_fingerprint, content_seen, content_error.
CREATE TABLE meta (
	key    TEXT PRIMARY KEY,
	value  TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE control (
	id            INTEGER PRIMARY KEY,
	gamename      TEXT    NOT NULL DEFAULT '',
	gamesize      INTEGER NOT NULL DEFAULT 0,
	gameopen      INTEGER NOT NULL DEFAULT 0,
	gameurl       TEXT    NOT NULL DEFAULT '',
	adminemail    TEXT    NOT NULL DEFAULT '',
	forumtype     INTEGER NOT NULL DEFAULT 0,
	forumaddress  TEXT    NOT NULL DEFAULT '',
	compression   INTEGER NOT NULL DEFAULT 0,
	verifyemail   INTEGER NOT NULL DEFAULT 0,
	shownews      INTEGER NOT NULL DEFAULT 0,
	showbabble    INTEGER NOT NULL DEFAULT 0,
	showonline    INTEGER NOT NULL DEFAULT 0,
	inventory_size INTEGER NOT NULL DEFAULT 12
);

-- Forum boards. admin_threads = 1: only administrators start threads (replies are open).
CREATE TABLE forums (
	id             INTEGER PRIMARY KEY,
	name           TEXT    NOT NULL,
	description    TEXT    NOT NULL DEFAULT '',
	position       INTEGER NOT NULL DEFAULT 0,
	admin_threads  INTEGER NOT NULL DEFAULT 0
);

-- Threads (parent = 0) and replies (parent = thread id); replies share the thread's board.
-- author is the charname at posting time (shown); author_id links the account.
CREATE TABLE forum (
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
CREATE INDEX forum_parent ON forum (parent, newpostdate);
CREATE INDEX forum_board ON forum (board, parent, newpostdate);

-- Items: content files app/content/items/<key>.lua (like classes; never deleted, an item
-- whose file is gone is retired and players keep it). category: weapon, armor, shield,
-- accessory (gear: slot is the category), consumable, quest or misc (slot NULL).
-- modifiers: stat effects while equipped, use_effects: what using it does (effect lists
-- as text, app/lib/effects.lua). drop_level: monsters of that level and up drop it (NULL:
-- never). The original items keep ids 1-33 and the original drops are 34-65.
CREATE TABLE items (
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

CREATE TABLE monsters (
	id       INTEGER PRIMARY KEY AUTOINCREMENT,
	name     TEXT    NOT NULL DEFAULT '',
	maxhp    INTEGER NOT NULL DEFAULT 0,
	maxdam   INTEGER NOT NULL DEFAULT 0,
	armor    INTEGER NOT NULL DEFAULT 0,
	level    INTEGER NOT NULL DEFAULT 0,
	maxexp   INTEGER NOT NULL DEFAULT 0,
	maxgold  INTEGER NOT NULL DEFAULT 0,
	immune   INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX monsters_level ON monsters (level);

-- thread_id: the post's discussion thread in the News board (app/lib/news.lua).
CREATE TABLE news (
	id         INTEGER PRIMARY KEY AUTOINCREMENT,
	postdate   INTEGER NOT NULL DEFAULT 0,
	content    TEXT    NOT NULL DEFAULT '',
	title      TEXT    NOT NULL DEFAULT '',
	author_id  INTEGER REFERENCES users (id) ON DELETE SET NULL,
	thread_id  INTEGER REFERENCES forum (id) ON DELETE SET NULL
);

-- Spells: content files app/content/spells/<key>.lua (like classes; never deleted, a spell
-- whose file is gone is retired). usable_in: 'town', 'fight' or 'both'; effects: the
-- effects list as text (app/lib/effects.lua, "heal_hp amount=10").
CREATE TABLE spells (
	id           INTEGER PRIMARY KEY,
	key          TEXT    NOT NULL UNIQUE,
	name         TEXT    NOT NULL DEFAULT '',
	description  TEXT    NOT NULL DEFAULT '',
	mp           INTEGER NOT NULL DEFAULT 0,
	usable_in    TEXT    NOT NULL DEFAULT 'fight',
	effects      TEXT    NOT NULL DEFAULT '',
	retired      INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE towns (
	id            INTEGER PRIMARY KEY AUTOINCREMENT,
	name          TEXT    NOT NULL DEFAULT '',
	latitude      INTEGER NOT NULL DEFAULT 0,
	longitude     INTEGER NOT NULL DEFAULT 0,
	innprice      INTEGER NOT NULL DEFAULT 0,
	mapprice      INTEGER NOT NULL DEFAULT 0,
	travelpoints  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX towns_location ON towns (latitude, longitude);

-- What each town's shop sells (replaces the old towns.itemslist).
CREATE TABLE town_items (
	town_id  INTEGER NOT NULL REFERENCES towns (id),
	item_id  INTEGER NOT NULL REFERENCES items (id),
	PRIMARY KEY (town_id, item_id)
) WITHOUT ROWID;

-- password: 'pbkdf2$<iters>$<salt hex>$<hash hex>' (see app/lib/auth.lua).
-- verify: '1' when verified, otherwise the 8-letter code that was emailed.
-- base_maxhp .. base_gold_bonus, strength, dexterity: the base stats (app/lib/stats.lua);
-- the effective ones add the equipped items (user_items). dropcode: the item a monster
-- just dropped (items.id; 0: none).
CREATE TABLE users (
	id                    INTEGER PRIMARY KEY AUTOINCREMENT,
	username              TEXT    NOT NULL DEFAULT '' COLLATE NOCASE,
	password              TEXT    NOT NULL DEFAULT '',
	email                 TEXT    NOT NULL DEFAULT '' COLLATE NOCASE,
	verify                TEXT    NOT NULL DEFAULT '0',
	charname              TEXT    NOT NULL DEFAULT '' COLLATE NOCASE,
	regdate               INTEGER NOT NULL DEFAULT 0,
	onlinetime            INTEGER NOT NULL DEFAULT 0,
	authlevel             INTEGER NOT NULL DEFAULT 0,
	latitude              INTEGER NOT NULL DEFAULT 0,
	longitude             INTEGER NOT NULL DEFAULT 0,
	charclass             INTEGER NOT NULL DEFAULT 0,
	currentaction         TEXT    NOT NULL DEFAULT 'In Town',
	currentfight          INTEGER NOT NULL DEFAULT 0,
	currentmonster        INTEGER NOT NULL DEFAULT 0,
	currentmonsterhp      INTEGER NOT NULL DEFAULT 0,
	currentmonstersleep   INTEGER NOT NULL DEFAULT 0,
	currentmonsterimmune  INTEGER NOT NULL DEFAULT 0,
	currentuberdamage     INTEGER NOT NULL DEFAULT 0,
	currentuberdefense    INTEGER NOT NULL DEFAULT 0,
	currenthp             INTEGER NOT NULL DEFAULT 15,
	currentmp             INTEGER NOT NULL DEFAULT 0,
	currenttp             INTEGER NOT NULL DEFAULT 10,
	base_maxhp            INTEGER NOT NULL DEFAULT 15,
	base_maxmp            INTEGER NOT NULL DEFAULT 0,
	base_maxtp            INTEGER NOT NULL DEFAULT 10,
	level                 INTEGER NOT NULL DEFAULT 1,
	gold                  INTEGER NOT NULL DEFAULT 100,
	experience            INTEGER NOT NULL DEFAULT 0,
	strength              INTEGER NOT NULL DEFAULT 5,
	dexterity             INTEGER NOT NULL DEFAULT 5,
	dropcode              INTEGER NOT NULL DEFAULT 0,
	towns                 TEXT    NOT NULL DEFAULT '0',
	base_attack           INTEGER NOT NULL DEFAULT 0,
	base_defense          INTEGER NOT NULL DEFAULT 0,
	base_exp_bonus        INTEGER NOT NULL DEFAULT 0,
	base_gold_bonus       INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX users_username ON users (username);
CREATE INDEX users_charname ON users (charname);
CREATE INDEX users_email ON users (email);
CREATE INDEX users_onlinetime ON users (onlinetime);

-- Spells a character knows. learned_level: the level it was learned at (NULL: unknown,
-- e.g. known before schema version 5 without a matching class schedule, or given by an admin).
CREATE TABLE user_spells (
	user_id        INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	spell_id       INTEGER NOT NULL REFERENCES spells (id),
	learned_level  INTEGER,
	PRIMARY KEY (user_id, spell_id)
) WITHOUT ROWID;

-- Items characters have: equipped (weapon, armor, shield, accessory1-3; one item per
-- slot) or in the bag (equipped NULL; qty up to the item's max_stack per row). The bag
-- holds control.inventory_size rows, quest items not counted (app/lib/inventory.lua).
CREATE TABLE user_items (
	id        INTEGER PRIMARY KEY,
	user_id   INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	item_id   INTEGER NOT NULL REFERENCES items (id),
	qty       INTEGER NOT NULL DEFAULT 1,
	equipped  TEXT
);
CREATE UNIQUE INDEX user_items_equipped ON user_items (user_id, equipped);

-- Server-side login sessions (app/lib/session.lua). token_hash = hex(sha256(cookie)).
CREATE TABLE sessions (
	token_hash  TEXT    PRIMARY KEY,
	user_id     INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	csrf        TEXT    NOT NULL,
	created     INTEGER NOT NULL,
	expires     INTEGER NOT NULL,
	remember    INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;
CREATE INDEX sessions_user ON sessions (user_id);
CREATE INDEX sessions_expires ON sessions (expires);
