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

migrations.STEPS = {
	{ name = "forum boards; news titles, authors and discussion threads", up = v1_boards_and_news_threads },
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
