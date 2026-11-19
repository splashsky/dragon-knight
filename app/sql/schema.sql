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

CREATE TABLE control (
	id            INTEGER PRIMARY KEY,
	gamename      TEXT    NOT NULL DEFAULT '',
	gamesize      INTEGER NOT NULL DEFAULT 0,
	gameopen      INTEGER NOT NULL DEFAULT 0,
	gameurl       TEXT    NOT NULL DEFAULT '',
	adminemail    TEXT    NOT NULL DEFAULT '',
	forumtype     INTEGER NOT NULL DEFAULT 0,
	forumaddress  TEXT    NOT NULL DEFAULT '',
	class1name    TEXT    NOT NULL DEFAULT '',
	class2name    TEXT    NOT NULL DEFAULT '',
	class3name    TEXT    NOT NULL DEFAULT '',
	compression   INTEGER NOT NULL DEFAULT 0,
	verifyemail   INTEGER NOT NULL DEFAULT 0,
	shownews      INTEGER NOT NULL DEFAULT 0,
	showbabble    INTEGER NOT NULL DEFAULT 0,
	showonline    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE drops (
	id          INTEGER PRIMARY KEY AUTOINCREMENT,
	name        TEXT    NOT NULL DEFAULT '',
	mlevel      INTEGER NOT NULL DEFAULT 0,
	type        INTEGER NOT NULL DEFAULT 0,
	attribute1  TEXT    NOT NULL DEFAULT '',
	attribute2  TEXT    NOT NULL DEFAULT ''
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

CREATE TABLE items (
	id         INTEGER PRIMARY KEY AUTOINCREMENT,
	type       INTEGER NOT NULL DEFAULT 0,
	name       TEXT    NOT NULL DEFAULT '',
	buycost    INTEGER NOT NULL DEFAULT 0,
	attribute  INTEGER NOT NULL DEFAULT 0,
	special    TEXT    NOT NULL DEFAULT ''
);

-- Column names start with a digit: quote them in SQL ("1_exp").
CREATE TABLE levels (
	id             INTEGER PRIMARY KEY AUTOINCREMENT,
	"1_exp"        INTEGER NOT NULL DEFAULT 0,
	"1_hp"         INTEGER NOT NULL DEFAULT 0,
	"1_mp"         INTEGER NOT NULL DEFAULT 0,
	"1_tp"         INTEGER NOT NULL DEFAULT 0,
	"1_strength"   INTEGER NOT NULL DEFAULT 0,
	"1_dexterity"  INTEGER NOT NULL DEFAULT 0,
	"1_spells"     INTEGER NOT NULL DEFAULT 0,
	"2_exp"        INTEGER NOT NULL DEFAULT 0,
	"2_hp"         INTEGER NOT NULL DEFAULT 0,
	"2_mp"         INTEGER NOT NULL DEFAULT 0,
	"2_tp"         INTEGER NOT NULL DEFAULT 0,
	"2_strength"   INTEGER NOT NULL DEFAULT 0,
	"2_dexterity"  INTEGER NOT NULL DEFAULT 0,
	"2_spells"     INTEGER NOT NULL DEFAULT 0,
	"3_exp"        INTEGER NOT NULL DEFAULT 0,
	"3_hp"         INTEGER NOT NULL DEFAULT 0,
	"3_mp"         INTEGER NOT NULL DEFAULT 0,
	"3_tp"         INTEGER NOT NULL DEFAULT 0,
	"3_strength"   INTEGER NOT NULL DEFAULT 0,
	"3_dexterity"  INTEGER NOT NULL DEFAULT 0,
	"3_spells"     INTEGER NOT NULL DEFAULT 0
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

CREATE TABLE spells (
	id         INTEGER PRIMARY KEY AUTOINCREMENT,
	name       TEXT    NOT NULL DEFAULT '',
	mp         INTEGER NOT NULL DEFAULT 0,
	attribute  INTEGER NOT NULL DEFAULT 0,
	type       INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE towns (
	id            INTEGER PRIMARY KEY AUTOINCREMENT,
	name          TEXT    NOT NULL DEFAULT '',
	latitude      INTEGER NOT NULL DEFAULT 0,
	longitude     INTEGER NOT NULL DEFAULT 0,
	innprice      INTEGER NOT NULL DEFAULT 0,
	mapprice      INTEGER NOT NULL DEFAULT 0,
	travelpoints  INTEGER NOT NULL DEFAULT 0,
	itemslist     TEXT    NOT NULL DEFAULT ''
);
CREATE INDEX towns_location ON towns (latitude, longitude);

-- password: 'pbkdf2$<iters>$<salt hex>$<hash hex>' (see app/lib/auth.lua).
-- verify: '1' when verified, otherwise the 8-letter code that was emailed.
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
	maxhp                 INTEGER NOT NULL DEFAULT 15,
	maxmp                 INTEGER NOT NULL DEFAULT 0,
	maxtp                 INTEGER NOT NULL DEFAULT 10,
	level                 INTEGER NOT NULL DEFAULT 1,
	gold                  INTEGER NOT NULL DEFAULT 100,
	experience            INTEGER NOT NULL DEFAULT 0,
	goldbonus             INTEGER NOT NULL DEFAULT 0,
	expbonus              INTEGER NOT NULL DEFAULT 0,
	strength              INTEGER NOT NULL DEFAULT 5,
	dexterity             INTEGER NOT NULL DEFAULT 5,
	attackpower           INTEGER NOT NULL DEFAULT 5,
	defensepower          INTEGER NOT NULL DEFAULT 5,
	weaponid              INTEGER NOT NULL DEFAULT 0,
	armorid               INTEGER NOT NULL DEFAULT 0,
	shieldid              INTEGER NOT NULL DEFAULT 0,
	slot1id               INTEGER NOT NULL DEFAULT 0,
	slot2id               INTEGER NOT NULL DEFAULT 0,
	slot3id               INTEGER NOT NULL DEFAULT 0,
	weaponname            TEXT    NOT NULL DEFAULT 'None',
	armorname             TEXT    NOT NULL DEFAULT 'None',
	shieldname            TEXT    NOT NULL DEFAULT 'None',
	slot1name             TEXT    NOT NULL DEFAULT 'None',
	slot2name             TEXT    NOT NULL DEFAULT 'None',
	slot3name             TEXT    NOT NULL DEFAULT 'None',
	dropcode              INTEGER NOT NULL DEFAULT 0,
	spells                TEXT    NOT NULL DEFAULT '0',
	towns                 TEXT    NOT NULL DEFAULT '0'
);
CREATE UNIQUE INDEX users_username ON users (username);
CREATE INDEX users_charname ON users (charname);
CREATE INDEX users_email ON users (email);
CREATE INDEX users_onlinetime ON users (onlinetime);

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
