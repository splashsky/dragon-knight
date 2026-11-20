-- Dragon Knight schema (SQLite). Port of the original install.php: same tables (no dk_ prefix)
-- and column names. Dates are unix seconds (INTEGER). Text comparisons on username,
-- charname and email are case-insensitive like the original MySQL collation.
-- This is the latest schema (`dk install` sets PRAGMA user_version to
-- migrations.VERSION); change it together with a new migration in app/lib/migrations.lua.

-- The Babble Box (chat, app/lib/chat.lua). author is the charname at posting time (shown);
-- author_id links the account (schema version 10; the rate limit counts by it).
CREATE TABLE babble (
	id        INTEGER PRIMARY KEY AUTOINCREMENT,
	posttime  INTEGER NOT NULL DEFAULT 0,
	author    TEXT    NOT NULL DEFAULT '',
	babble    TEXT    NOT NULL DEFAULT '',
	author_id INTEGER REFERENCES users (id) ON DELETE SET NULL
);
CREATE INDEX babble_author ON babble (author_id, posttime);

-- Character classes: content files app/content/classes/<key>.lua synced into these tables
-- (app/lib/content/sync.lua). Rows are never deleted: a class whose file is gone is
-- retired (existing characters keep it). users.charclass holds classes.id. Every content
-- table (classes, items, monsters, spells, statuses, summons) has `lore` (schema
-- version 13): optional story text for tooltips and the help pages ('' = none).
-- start_spells (schema version 14): keys of the spells a new character knows ("a,b").
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
	retired          INTEGER NOT NULL DEFAULT 0,
	lore             TEXT    NOT NULL DEFAULT '',
	start_spells     TEXT    NOT NULL DEFAULT ''
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

-- Small key/value store: content_fingerprint, content_seen, content_error, presence_sweep.
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
	inventory_size INTEGER NOT NULL DEFAULT 12,
	max_allies    INTEGER NOT NULL DEFAULT 1,
	-- the broadcast banner (app/lib/banner.lua): text ('' = none), id (+1 per banner),
	-- expiry (unix time, 0 = never)
	banner        TEXT    NOT NULL DEFAULT '',
	banner_id     INTEGER NOT NULL DEFAULT 0,
	banner_expires INTEGER NOT NULL DEFAULT 0
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
-- modifiers: stat bonuses while equipped (as text, app/lib/stats.lua). Consumables are
-- scripted (app/lib/action.lua; their code stays in the file): usable_in ('town', 'fight',
-- 'both'), target ('enemy', 'self'), power, messages and data ("key=value" lines,
-- app/lib/content/scripted.lua). drop_level: monsters of that level and up drop it (NULL:
-- never). The original items keep ids 1-33 and the original drops are 34-65. Schema
-- version 14: casts (a spell key: gear that casts it in fights; '' = none) and charges
-- (when full; user_items.charges holds each one's), icon (a PNG in public/images/items/,
-- '' = the default icon).
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
	max_stack    INTEGER NOT NULL DEFAULT 1,
	drop_level   INTEGER,
	sellable     INTEGER NOT NULL DEFAULT 0,
	droppable    INTEGER NOT NULL DEFAULT 1,
	retired      INTEGER NOT NULL DEFAULT 0,
	usable_in    TEXT    NOT NULL DEFAULT 'fight',
	target       TEXT    NOT NULL DEFAULT 'enemy',
	power        INTEGER NOT NULL DEFAULT 0,
	messages     TEXT    NOT NULL DEFAULT '',
	data         TEXT    NOT NULL DEFAULT '',
	lore         TEXT    NOT NULL DEFAULT '',
	casts        TEXT    NOT NULL DEFAULT '',
	charges      INTEGER NOT NULL DEFAULT 0,
	icon         TEXT    NOT NULL DEFAULT ''
);

-- Monsters: content files app/content/monsters/<key>.lua (like items; never deleted, a
-- monster whose file is gone is retired: no longer met, fights in progress go on). The
-- original monsters keep ids 1-151. maxmp: MP at the start of every encounter; uses_mp:
-- spells cost it MP (0: free); attack_weight: the weight of its basic attack among its
-- actions; roams: met in random encounters of its level band. The loadout (equipment,
-- items, spells) is in the monster_* tables; `when` conditions stay in the file
-- (has_when says the entry has one).
CREATE TABLE monsters (
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
	retired        INTEGER NOT NULL DEFAULT 0,
	lore           TEXT    NOT NULL DEFAULT ''
);
CREATE INDEX monsters_level ON monsters (level);

-- A monster's equipment (slot: weapon, armor, shield, accessory1-3; like a character's).
CREATE TABLE monster_equipment (
	monster_id  INTEGER NOT NULL REFERENCES monsters (id),
	slot        TEXT    NOT NULL,
	item_id     INTEGER NOT NULL REFERENCES items (id),
	PRIMARY KEY (monster_id, slot)
) WITHOUT ROWID;

-- The consumables a monster may use (position: the file's order), by weight; stock: uses
-- per encounter (NULL: no limit).
CREATE TABLE monster_items (
	monster_id  INTEGER NOT NULL REFERENCES monsters (id),
	position    INTEGER NOT NULL,
	item_id     INTEGER NOT NULL REFERENCES items (id),
	weight      INTEGER NOT NULL DEFAULT 1,
	stock       INTEGER,
	has_when    INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (monster_id, position)
) WITHOUT ROWID;

-- The spells a monster may cast (position: the file's order), by weight.
CREATE TABLE monster_spells (
	monster_id  INTEGER NOT NULL REFERENCES monsters (id),
	position    INTEGER NOT NULL,
	spell_id    INTEGER NOT NULL REFERENCES spells (id),
	weight      INTEGER NOT NULL DEFAULT 1,
	has_when    INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (monster_id, position)
) WITHOUT ROWID;

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
-- whose file is gone is retired). Scripted (app/lib/action.lua): what a spell does is its
-- file's code; usable_in ('town', 'fight', 'both'), target ('enemy', 'self'), power,
-- messages and data ("key=value" lines, app/lib/content/scripted.lua) are data; icon: the
-- PNG of its buttons, public/images/skills/<icon>.png ('' = default.png).
CREATE TABLE spells (
	id           INTEGER PRIMARY KEY,
	key          TEXT    NOT NULL UNIQUE,
	name         TEXT    NOT NULL DEFAULT '',
	description  TEXT    NOT NULL DEFAULT '',
	mp           INTEGER NOT NULL DEFAULT 0,
	usable_in    TEXT    NOT NULL DEFAULT 'fight',
	retired      INTEGER NOT NULL DEFAULT 0,
	power        INTEGER NOT NULL DEFAULT 0,
	target       TEXT    NOT NULL DEFAULT 'enemy',
	messages     TEXT    NOT NULL DEFAULT '',
	data         TEXT    NOT NULL DEFAULT '',
	icon         TEXT    NOT NULL DEFAULT '',
	lore         TEXT    NOT NULL DEFAULT ''
);

-- Statuses: content files app/content/statuses/<key>.lua (like spells; never deleted, a
-- status whose file is gone is retired). Timed effects on a combatant, scripted
-- (app/fight/engine.lua): the hooks are the file's code; kind ('harmful', 'helpful',
-- 'neutral'), tick_on ('turn_start', 'turn_end'), scope ('fight', 'world', 'both'), turns
-- (default duration; 0: no limit), blocks_action, messages and data are data. Ids 1-3 are
-- the original game's mechanics (sleep, uber_damage, uber_defense; seed.sql).
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
	data           TEXT    NOT NULL DEFAULT '',
	lore           TEXT    NOT NULL DEFAULT ''
);

-- Summons: content files app/content/summons/<key>.lua: allies that fight alongside the
-- player (app/fight/engine.lua); act is the file's code, the numbers are data.
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
	data         TEXT    NOT NULL DEFAULT '',
	lore         TEXT    NOT NULL DEFAULT ''
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
-- just dropped (items.id; 0: none). A fight in progress is in the fights tables.
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
	base_gold_bonus       INTEGER NOT NULL DEFAULT 0,
	online                INTEGER NOT NULL DEFAULT 0    -- 1: announced as online (app/lib/presence.lua)
);
CREATE UNIQUE INDEX users_username ON users (username);
CREATE INDEX users_charname ON users (charname);
CREATE INDEX users_email ON users (email);
CREATE INDEX users_onlinetime ON users (onlinetime);
-- Only the players online (lib/presence.lua: every game page counts them, the town page
-- lists them by name), so reading who's online doesn't cost a scan of every account.
CREATE INDEX users_online ON users (charname, id) WHERE online = 1;

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
-- charges (schema version 14): the charges left of an item that casts a spell (full,
-- items.charges, when obtained; 0 for other items).
CREATE TABLE user_items (
	id        INTEGER PRIMARY KEY,
	user_id   INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	item_id   INTEGER NOT NULL REFERENCES items (id),
	qty       INTEGER NOT NULL DEFAULT 1,
	equipped  TEXT,
	charges   INTEGER NOT NULL DEFAULT 0
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

-- A fight (app/fight/state.lua), one per player, loaded and saved once per request.
-- round: the fight's counter (+1 per round played, without the original's cap of 255; the
-- encounter's first strike is round 1, so the first form carries 2); wave: the enemies'
-- wave on the field; data: fight-level values ("name=value" lines, typed). outcome: '' in
-- progress, 'victory' or 'death': a finished fight is kept for its page (GET /fight, GET
-- /victory) until the next encounter or a move (app/fight/encounter.lua); log: the last
-- round's lines ("<part>\t<line>" lines); result: a victory's rewards ("name=value" lines).
CREATE TABLE fights (
	user_id  INTEGER PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
	round    INTEGER NOT NULL DEFAULT 1,
	wave     INTEGER NOT NULL DEFAULT 1,
	data     TEXT    NOT NULL DEFAULT '',
	outcome  TEXT    NOT NULL DEFAULT '',
	log      TEXT    NOT NULL DEFAULT '',
	result   TEXT    NOT NULL DEFAULT ''
);

-- The combatants of a fight, numbered from 1 within it (1: the player). side: player,
-- ally, enemy; kind: player, monster (entity_id: monsters.id), summon (summons.id). wave:
-- an enemy's wave (0 otherwise). hp, maxhp: NULL for the player (users.currenthp and the
-- effective stats hold them). turns_left: rounds a summon stays (NULL: no limit). data:
-- per-combatant values (a monster's immunity, the stock of its items), "name=value" lines.
-- mp, maxmp: a monster's MP (NULL otherwise; NULL for a monster: full).
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
	mp          INTEGER,
	maxmp       INTEGER,
	PRIMARY KEY (user_id, id)
) WITHOUT ROWID;

-- Statuses on the combatants of a fight: one instance per status and bearer (applying it
-- again replaces it), in the order applied (position). turns_left: the bearer's turns left
-- (NULL: until removed or the fight ends); data: the params it was applied with (names and
-- values only, never code); source: the combatant who applied it.
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

-- World statuses of a character (scope 'world' or 'both', applied outside fights): they
-- tick on map moves (turns_left: moves left; NULL: until removed) and outlast fights.
CREATE TABLE user_statuses (
	user_id     INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	status_id   INTEGER NOT NULL REFERENCES statuses (id),
	position    INTEGER NOT NULL,
	turns_left  INTEGER,
	data        TEXT    NOT NULL DEFAULT '',
	PRIMARY KEY (user_id, status_id)
) WITHOUT ROWID;
