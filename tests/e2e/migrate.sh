# tests/e2e/migrate.sh :: schema versioning: `dk migrate` from the pre-versioning schema
# (tests/fixtures/schema_v0.sql) and from versions 1 to 6 (tests/fixtures/schema_vN.sql,
# with the game data of that time, tests/fixtures/seed_v3.sql to seed_v6.sql), the 503
# page for an outdated database, and no-op runs. Version 5 -> 6 checks that every
# character's effective stats are the same before and after; version 6 -> 7 that edited
# effect amounts become power overrides and a fight goes on.
# Sourced by tests/run.sh. Uses its own database and a second server; the main test
# database is only stamped with other versions for a moment.

mig_sql() { t_sql_db "$@"; }  # mig_sql DB "SQL"
mig_script() { t_sql_script "$@"; }  # mig_script DB FILE
mig_eq() {  # mig_eq "SQL" expected label   (on the migrated database)
	local got
	got=$(mig_sql "$MIG_DB" "$1")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$3: expected '$2', got '$got'"; fi
}
# Column, foreign key and index layout of a database (to compare schemas).
mig_layout() {
	mig_sql "$1" "SELECT m.name, p.cid, p.name, p.type, p.\"notnull\", p.dflt_value, p.pk
		FROM sqlite_master m, pragma_table_info(m.name) p WHERE m.type = 'table' ORDER BY 1, 2;
		SELECT m.name, f.id, f.seq, f.\"table\", f.\"from\", f.\"to\", f.on_delete
		FROM sqlite_master m, pragma_foreign_key_list(m.name) f WHERE m.type = 'table' ORDER BY 1, 2, 3;
		SELECT m.name, i.name, c.seqno, c.name FROM sqlite_master m, pragma_index_list(m.name) i,
			pragma_index_info(i.name) c WHERE m.type = 'table' ORDER BY 1, 2, 3;"
}
# The users rows of database $1 (the columns every version has, max HP/MP/TP under their
# name of the time: base_maxhp since version 6, the same for characters without gear).
MIG_USERS_COMMON="id, username, password, email, verify, charname, regdate, onlinetime, authlevel, latitude,
	longitude, charclass, currentaction, currentfight, currentmonster, currentmonsterhp, currentmonstersleep,
	currentmonsterimmune, currentuberdamage, currentuberdefense, currenthp, currentmp, currenttp, level, gold,
	experience, strength, dexterity, dropcode, towns"
mig_users() {
	local max="maxhp, maxmp, maxtp"
	[ "$(mig_sql "$1" "SELECT count(*) FROM pragma_table_info('users') WHERE name = 'base_maxhp'")" = 1 ] \
		&& max="base_maxhp, base_maxmp, base_maxtp"
	mig_sql "$1" "SELECT $MIG_USERS_COMMON, $max FROM users ORDER BY id"
}
# mig_serve CONFIG LOG: start a server on another database and point the t_* helpers at it;
# mig_unserve LOG: stop it (failing on errors in its log) and point them back.
mig_serve() {
	"$BIN" serve --config "$1" >"$2" 2>&1 &
	MIG_PID=$!
	MIG_PORT=
	for _ in $(seq 1 100); do
		MIG_PORT=$(sed -n 's/.*http: listening on [^ ]*:\([0-9][0-9]*\)$/\1/p' "$2" | head -n1)
		[ -n "$MIG_PORT" ] && break
		sleep 0.05
	done
	[ -n "$MIG_PORT" ] && t_ok || t_fail "server on $1 did not start"
	MAIN_BASE=$BASE
	BASE="http://127.0.0.1:$MIG_PORT"
}
mig_unserve() {
	BASE=$MAIN_BASE
	kill "$MIG_PID" 2>/dev/null && wait "$MIG_PID" 2>/dev/null
	if grep -q '\[error\]' "$1"; then
		t_fail "errors in the log $1:"; grep -A5 '\[error\]' "$1" | head -20 >&2
	fi
	t_jar default
}
# The spells as data (the same on a fresh install and a migrated database without edits;
# messages on one line). MIG_SPELLS_OF takes a WHERE and ORDER BY.
MIG_SPELLS_OF="SELECT id, key, name, description, mp, usable_in, retired, power, target,
	replace(messages, char(10), '/'), replace(data, char(10), '/') FROM spells"
MIG_SPELLS="$MIG_SPELLS_OF ORDER BY id"
# The items and what towns sell (the same on a fresh install and a migrated database without edits).
MIG_ITEMS="SELECT * FROM items ORDER BY id; SELECT * FROM town_items ORDER BY town_id, item_id"
# The classes as data (the same on a fresh install and a migrated database without edits).
MIG_CLASSES="SELECT * FROM classes ORDER BY id; SELECT * FROM class_levels ORDER BY class_id, level;
	SELECT * FROM class_spells ORDER BY class_id, level, spell_id"
# Per class and level 2-100: hp|mp|strength|dexterity|spells, from the levels table (before
# version 4) and from class_levels/class_spells (after); spells 0 = none.
MIG_LEVELS_V3="SELECT c, id, hp, mp, st, dx, sp FROM (
	SELECT 1 AS c, id, \"1_hp\" AS hp, \"1_mp\" AS mp, \"1_strength\" AS st, \"1_dexterity\" AS dx, \"1_spells\" AS sp FROM levels
	UNION ALL SELECT 2, id, \"2_hp\", \"2_mp\", \"2_strength\", \"2_dexterity\", \"2_spells\" FROM levels
	UNION ALL SELECT 3, id, \"3_hp\", \"3_mp\", \"3_strength\", \"3_dexterity\", \"3_spells\" FROM levels)
	WHERE id >= 2 ORDER BY c, id"
MIG_LEVELS_V4="SELECT l.class_id, l.level, l.hp, l.mp, l.strength, l.dexterity,
	coalesce((SELECT group_concat(spell_id) FROM class_spells s WHERE s.class_id = l.class_id AND s.level = l.level), 0)
	FROM class_levels l WHERE l.class_id <= 3 ORDER BY 1, 2"
# Before version 3 the levels table's hp columns held the milestone HP (10 at levels 10-30,
# 15 at 40-60, 20 at 70-90, 50 at 99); the seed has 0 there now (lib/leveling.lua adds it).
MIG_MILESTONES="10, 20, 30, 40, 50, 60, 70, 80, 90, 99"
MIG_HP="CASE WHEN id <= 30 THEN 10 WHEN id <= 60 THEN 15 WHEN id <= 90 THEN 20 ELSE 50 END"
MIG_ORIGINAL_HP="UPDATE levels SET \"1_hp\" = $MIG_HP, \"2_hp\" = $MIG_HP, \"3_hp\" = $MIG_HP
	WHERE id IN ($MIG_MILESTONES)"

if ! t_has_sql; then
	t_section "migrate (skipped: needs sqlite3 or python3)"
else

t_section "migrate: fresh install is current"
CUR_VERSION=$(t_sql "PRAGMA user_version")
[ "$CUR_VERSION" -ge 3 ] && t_ok || t_fail "install did not stamp user_version ($CUR_VERSION)"
"$BIN" migrate --config "$CONFIG" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate on a current db failed"
grep -qF "Database schema is up to date (version $CUR_VERSION)." "$T/migrate.log" && t_ok || t_fail "no-op message: $(cat "$T/migrate.log")"
grep -qF "Content synced (spells: 19, 0 new, 0 retired; classes: 3, 0 new, 0 retired; items: 68, 0 new, 0 retired)." "$T/migrate.log" && t_ok || t_fail "content sync message: $(cat "$T/migrate.log")"
[ "$(t_sql "PRAGMA user_version")" = "$CUR_VERSION" ] && t_ok || t_fail "version changed"

t_section "migrate: version checks on every request"
t_jar migcheck
t_sql "PRAGMA user_version = 0"
t_get /login;  expect_status 503; expect_body 'Database schema is out of date — run `dk migrate`.'
expect_header '^retry-after: 60'
t_get /;       expect_status 503
t_sql "PRAGMA user_version = $((CUR_VERSION + 1))"
t_get /login;  expect_status 503; expect_body 'is newer than this version of the game'
t_sql "PRAGMA user_version = $CUR_VERSION"
t_get /login;  expect_status 200

t_section "migrate: old database"
MIG="$T/mig"
mkdir -p "$MIG"
MIG_DB="$MIG/dk.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$MIG_DB\"#" "$CONFIG" > "$MIG/config.lua"
"$BIN" serve --config "$MIG/config.lua" >"$MIG/server.log" 2>&1 &
MIG_PID=$!
MIG_PORT=
for _ in $(seq 1 100); do
	MIG_PORT=$(sed -n 's/.*http: listening on [^ ]*:\([0-9][0-9]*\)$/\1/p' "$MIG/server.log" | head -n1)
	[ -n "$MIG_PORT" ] && break
	sleep 0.05
done
[ -n "$MIG_PORT" ] && t_ok || t_fail "second server did not start"
MAIN_BASE=$BASE
BASE="http://127.0.0.1:$MIG_PORT"

t_jar migold
t_get /login;  expect_status 503; expect_body 'The database is not installed — run `dk install`.'
"$BIN" migrate --config "$MIG/config.lua" >"$T/migrate.log" 2>&1 && t_fail "migrate without tables succeeded" || t_ok
grep -qF 'run dk install' "$T/migrate.log" && t_ok || t_fail "no install hint: $(cat "$T/migrate.log")"

# version 0 schema + the game data (seed lines that fit it) + some players, posts and news
mig_script "$MIG_DB" "$ROOT/tests/fixtures/schema_v0.sql"
grep -v '^INSERT INTO forums ' "$ROOT/tests/fixtures/seed_v3.sql" > "$MIG/seed_v0.sql"
mig_script "$MIG_DB" "$MIG/seed_v0.sql"
# the original levels table had the milestone HP in the hp columns (now a formula)
mig_sql "$MIG_DB" "$MIG_ORIGINAL_HP"
mig_sql "$MIG_DB" "INSERT INTO users (id, username, email, charname, verify, authlevel) VALUES
		(1, 'oldplayer', 'p@example.com', 'Oldplayer', '1', 0),
		(2, 'oldadmin', 'a@example.com', 'Oldadmin', '1', 1),
		(3, 'otheradmin', 'o@example.com', 'Otheradmin', '1', 1);
	INSERT INTO forum (id, postdate, newpostdate, author, parent, replies, title, content) VALUES
		(1, 100, 300, 'Oldplayer', 0, 2, 'Old thread', 'old body'),
		(2, 200, 200, 'Gone', 1, 0, 'Re: Old thread', 'reply by a deleted player'),
		(3, 300, 300, 'oldadmin', 1, 0, 'Re: Old thread', 'reply by the admin'),
		(4, 400, 400, 'Oldplayer', 0, 0, 'Deleted thread', 'x');
	DELETE FROM forum WHERE id = 4;
	INSERT INTO news (id, postdate, content) VALUES (2, 500, 'Old news <b>title</b>
second line

Second paragraph.');"
[ "$(mig_sql "$MIG_DB" "PRAGMA user_version")" = 0 ] && t_ok || t_fail "fixture is not version 0"
mig_eq "SELECT \"1_hp\" || '|' || \"2_hp\" || '|' || \"3_hp\" FROM levels WHERE id IN (10, 40, 70, 99) ORDER BY id" \
	"10|10|10
15|15|15
20|20|20
50|50|50" "fixture has the original milestone HP"
t_get /login;  expect_status 503; expect_body 'Database schema is out of date — run `dk migrate`.'
"$BIN" migrate --config "$MIG/config.lua" --status >"$T/migrate.log" 2>&1
grep -qF "Database schema version 0; this game uses version $CUR_VERSION (run dk migrate)." "$T/migrate.log" \
	&& t_ok || t_fail "status: $(cat "$T/migrate.log")"
[ "$(mig_sql "$MIG_DB" "PRAGMA user_version")" = 0 ] && t_ok || t_fail "--status changed the db"

"$BIN" migrate --config "$MIG/config.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate failed: $(cat "$T/migrate.log")"
grep -qF 'Migrating to version 1: forum boards' "$T/migrate.log" && t_ok || t_fail "step 1 not reported"
grep -qF 'Migrating to version 2: remove difficulty levels' "$T/migrate.log" && t_ok || t_fail "step 2 not reported"
grep -qF 'Migrating to version 3: experience, TP and HP milestones' "$T/migrate.log" && t_ok || t_fail "step 3 not reported"
grep -qF 'Migrating to version 4: character classes are content files' "$T/migrate.log" && t_ok || t_fail "step 4 not reported"
grep -qF 'Migrating to version 5: spells are content files with effects' "$T/migrate.log" && t_ok || t_fail "step 5 not reported"
grep -qF 'Migrating to version 6: items and drops are content files' "$T/migrate.log" && t_ok || t_fail "step 6 not reported"
grep -qF 'Migrating to version 7: spells and consumables are scripted content' "$T/migrate.log" && t_ok || t_fail "step 7 not reported"
grep -qF 'Converted the stats of 3 characters to base stats (verified); 0 keep extra attack/defense power.' "$T/migrate.log" && t_ok || t_fail "stats conversion not reported"
grep -qF 'Content synced (spells: 19, 0 new, 0 retired; classes: 3, 0 new, 0 retired; items: 68, 0 new, 0 retired).' "$T/migrate.log" && t_ok || t_fail "content not synced by migrate"
grep -qF "Database schema is now version $CUR_VERSION." "$T/migrate.log" && t_ok || t_fail "done message"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "stamped"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$MIG/fresh.db\"#" "$CONFIG" > "$MIG/fresh.lua"
"$BIN" install --config "$MIG/fresh.lua" --admin fresh fresh@example.com freshpw >/dev/null 2>&1 \
	&& t_ok || t_fail "fresh install for comparison"
mig_layout "$MIG_DB" | grep -q '^forum|8|board|INTEGER|1|1|0$' && t_ok || t_fail "no forum.board column"
[ "$(mig_layout "$MIG_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated schema differs from a fresh install:"
	diff <(mig_layout "$MIG_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys"
mig_eq "$MIG_CLASSES" "$(mig_sql "$MIG/fresh.db" "$MIG_CLASSES")" "classes equal a fresh install's"
mig_eq "$MIG_SPELLS" "$(mig_sql "$MIG/fresh.db" "$MIG_SPELLS")" "spells equal a fresh install's"
mig_eq "$MIG_ITEMS" "$(mig_sql "$MIG/fresh.db" "$MIG_ITEMS")" "items and shops equal a fresh install's"
mig_eq "SELECT count(*) FROM sqlite_sequence WHERE name IN ('items', 'drops')" "0" "items ids are plain rowids now"
mig_eq "SELECT count(*) FROM sqlite_sequence WHERE name = 'spells'" "0" "spells ids are plain rowids now"
mig_eq "SELECT count(*) FROM content_overrides; SELECT count(*) FROM content_adopt" "0
0" "stock data: no overrides"
mig_eq "SELECT value FROM meta WHERE key = 'content_fingerprint'" \
	"$(mig_sql "$MIG/fresh.db" "SELECT value FROM meta WHERE key = 'content_fingerprint'")" "content fingerprint"
# existing data kept; forum posts moved to General with author_id where the name matches
mig_eq "SELECT count(*) || '|' || min(id) || '|' || max(id) FROM users" "3|1|3" "users kept"
mig_eq "SELECT count(*) FROM towns" "$(t_sql "SELECT count(*) FROM towns")" "game data kept"
mig_eq "SELECT id || ',' || board || ',' || coalesce(author_id, '-') || ',' || author || ',' || parent || ',' || replies || ',' || newpostdate || ',' || content FROM forum WHERE board = 1 ORDER BY id" \
	"1,1,1,Oldplayer,0,2,300,old body
2,1,-,Gone,1,0,200,reply by a deleted player
3,1,2,oldadmin,1,0,300,reply by the admin" "forum posts kept"
mig_eq "SELECT id || '|' || name || '|' || admin_threads FROM forums ORDER BY id" "1|General|0
2|News|1" "boards seeded"
# news: default titles, the lowest-id admin as author, a thread each (ids after the old
# AUTOINCREMENT high-water mark: deleted post 4 is not reused)
mig_eq "SELECT id || '|' || title || '|' || author_id || '|' || thread_id FROM news ORDER BY id" \
	"1|This is the first news post. Please use the admin control pa...|2|5
2|Old news <b>title</b>|2|6" "news backfilled"
mig_eq "SELECT f.board || '|' || f.parent || '|' || f.author || '|' || f.author_id || '|' || (f.title = n.title) || '|' || (f.content = n.content) || '|' || f.postdate || '|' || f.newpostdate FROM news n JOIN forum f ON f.id = n.thread_id WHERE n.id = 2" \
	"2|0|Oldadmin|2|1|1|500|500" "news thread"

t_section "migrate: no-op on the migrated database"
before=$(mig_sql "$MIG_DB" "SELECT * FROM forum; SELECT * FROM news; SELECT * FROM forums")
"$BIN" migrate --config "$MIG/config.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "second migrate failed"
grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate: $(cat "$T/migrate.log")"
[ "$(mig_sql "$MIG_DB" "SELECT * FROM forum; SELECT * FROM news; SELECT * FROM forums")" = "$before" ] \
	&& t_ok || t_fail "second migrate changed data"

t_section "migrate: the game works on the migrated database"
"$BIN" user --config "$MIG/config.lua" passwd oldadmin migpass1 >/dev/null && t_ok || t_fail "dk user passwd"
"$BIN" user --config "$MIG/config.lua" passwd oldplayer migpass2 >/dev/null && t_ok || t_fail "dk user passwd"
t_jar migadmin
t_login oldadmin migpass1; expect_redirect /
t_get /;              expect_status 200; expect_body '<b>Old news &lt;b&gt;title&lt;/b&gt;</b></a>'
expect_body 'by Oldadmin]'; expect_body '>Read more</a>'; expect_body 'href="/forum/thread/6">Reply</a>'
t_get /forum;         expect_status 200; expect_body 'href="/forum/1"><b>General</b>'; expect_body 'href="/forum/2"><b>News</b>'
t_get /forum/1;       expect_body 'href="/forum/thread/1">Old thread</a>'
t_get /forum/thread/1; expect_body 'reply by a deleted player'
t_get /news/1;        expect_status 200; expect_body 'This is the first news post.'
t_get /admin/news
t_post /admin/news "csrf=$(t_csrf)&title=Post-migration&content=Fresh"
expect_redirect '/admin/news\?saved=1'
mig_eq "SELECT n.title || '|' || f.board || '|' || f.author FROM news n JOIN forum f ON f.id = n.thread_id ORDER BY n.id DESC LIMIT 1" \
	"Post-migration|2|Oldadmin" "news after migrating"
t_jar migplayer
t_login oldplayer migpass2
t_get /forum/thread/6; TOKEN=$(t_csrf)
t_post /forum/reply/6 "csrf=$TOKEN&content=Nice"; expect_redirect /forum/thread/6
t_get /news/2;        expect_body 'href="/forum/thread/6">1 reply</a>'
mig_eq "SELECT board || '|' || author_id FROM forum WHERE parent = 6" "2|1" "reply row"

BASE=$MAIN_BASE
kill "$MIG_PID" 2>/dev/null && wait "$MIG_PID" 2>/dev/null
if grep -q '\[error\]' "$MIG/server.log"; then
	t_fail "errors in the second server's log:"; grep -A5 '\[error\]' "$MIG/server.log" | head -20 >&2
fi
t_jar default

t_section "migrate: version 1 database"
# version 1 schema (with difficulty levels) + the game data, a player on each difficulty
# and the old difficulty settings; steps 2 and 3 run
V1_DB="$MIG/v1.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V1_DB\"#" "$CONFIG" > "$MIG/v1.lua"
mig_script "$V1_DB" "$ROOT/tests/fixtures/schema_v1.sql"
mig_script "$V1_DB" "$ROOT/tests/fixtures/seed_v3.sql"
mig_sql "$V1_DB" "$MIG_ORIGINAL_HP"
cat > "$MIG/v1_data.sql" <<'SQL'
UPDATE control SET diff1name = 'Easy', diff1mod = 1, diff2name = 'Medium', diff2mod = 1.2,
	diff3name = 'Hard', diff3mod = 1.5;
INSERT INTO users (id, username, email, charname, verify, authlevel, difficulty, charclass, gold) VALUES
	(1, 'easyone', 'e@example.com', 'Easyone', '1', 1, 1, 1, 10),
	(2, 'medone', 'm@example.com', 'Medone', '1', 0, 2, 2, 20),
	(3, 'hardone', 'h@example.com', 'Hardone', '1', 0, 3, 3, 30);
PRAGMA user_version = 1;
SQL
mig_script "$V1_DB" "$MIG/v1_data.sql"
MIG_DB=$V1_DB
mig_eq "PRAGMA user_version" "1" "fixture is version 1"
V1_DATA="SELECT id, username, charname, charclass, gold, authlevel FROM users ORDER BY id;
	SELECT id, gamename, gamesize, gameopen, forumtype, verifyemail FROM control;
	SELECT count(*) FROM monsters; SELECT count(*) FROM forums"
before=$(mig_sql "$V1_DB" "$V1_DATA")
"$BIN" migrate --config "$MIG/v1.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v1) failed: $(cat "$T/migrate.log")"
grep -qF 'Migrating to version 2: remove difficulty levels' "$T/migrate.log" && t_ok || t_fail "step 2 not reported (v1)"
grep -qF 'Migrating to version 1' "$T/migrate.log" && t_fail "step 1 ran on a version 1 database" || t_ok
grep -qF "Database schema is now version $CUR_VERSION." "$T/migrate.log" && t_ok || t_fail "done message (v1)"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v1 stamped"
mig_eq "SELECT count(*) FROM pragma_table_info('control') WHERE name LIKE 'diff%';
	SELECT count(*) FROM pragma_table_info('users') WHERE name = 'difficulty'" "0
0" "difficulty columns dropped"
[ "$(mig_layout "$V1_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v1 schema differs from a fresh install:"
	diff <(mig_layout "$V1_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v1)"
[ "$(mig_sql "$V1_DB" "$V1_DATA")" = "$before" ] && t_ok || t_fail "v1 data changed by the migration"
mig_eq "$MIG_CLASSES" "$(mig_sql "$MIG/fresh.db" "$MIG_CLASSES")" "classes (v1)"
"$BIN" user --config "$MIG/v1.lua" list >"$T/migrate.log" 2>&1 && grep -q 'hardone' "$T/migrate.log" \
	&& t_ok || t_fail "dk user list on the migrated v1 database: $(cat "$T/migrate.log")"

t_section "migrate: version 2 database"
# version 2 schema (levels with exp and tp columns, milestone HP in the hp columns) + the
# game data, admin edits to levels 5 and 20, and players; only step 3 runs
V2_DB="$MIG/v2.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V2_DB\"#" "$CONFIG" > "$MIG/v2.lua"
mig_script "$V2_DB" "$ROOT/tests/fixtures/schema_v2.sql"
mig_script "$V2_DB" "$ROOT/tests/fixtures/seed_v3.sql"
mig_sql "$V2_DB" "$MIG_ORIGINAL_HP"
cat > "$MIG/v2_data.sql" <<'SQL'
UPDATE levels SET "1_exp" = 15 * id, "2_exp" = 18 * id, "3_exp" = 20 * id, "1_tp" = 1, "2_tp" = 2, "3_tp" = 3;
UPDATE levels SET "1_hp" = 7, "1_exp" = 111 WHERE id = 5;
UPDATE levels SET "2_hp" = 13 WHERE id = 20;
UPDATE levels SET "3_hp" = 4 WHERE id = 99;
INSERT INTO users (id, username, email, charname, verify, authlevel, charclass, level, experience, maxhp) VALUES
	(1, 'veteran', 'v@example.com', 'Veteran', '1', 1, 1, 10, 2995, 120),
	(2, 'rookie', 'r@example.com', 'Rookie', '1', 0, 3, 1, 0, 15);
PRAGMA user_version = 2;
SQL
mig_script "$V2_DB" "$MIG/v2_data.sql"
MIG_DB=$V2_DB
mig_eq "PRAGMA user_version" "2" "fixture is version 2"
V2_DATA="SELECT id, gamename, gamesize, gameopen, gameurl, adminemail,
	forumtype, forumaddress, compression, verifyemail, shownews, showbabble, showonline FROM control;
	SELECT count(*) FROM monsters"
before=$(mig_sql "$V2_DB" "$V2_DATA"; mig_users "$V2_DB")
"$BIN" migrate --config "$MIG/v2.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v2) failed: $(cat "$T/migrate.log")"
grep -qF 'Migrating to version 3: experience, TP and HP milestones per level are formulas (edited exp/tp values are discarded)' \
	"$T/migrate.log" && t_ok || t_fail "step 3 not reported (v2)"
grep -qE 'Migrating to version [12]:' "$T/migrate.log" && t_fail "steps 1-2 ran on a version 2 database" || t_ok
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v2 stamped"
mig_eq "SELECT count(*) FROM sqlite_master WHERE name = 'levels'" "0" "levels table dropped"
[ "$(mig_layout "$V2_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v2 schema differs from a fresh install:"
	diff <(mig_layout "$V2_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v2)"
# milestone HP taken off (an edited value keeps its difference), other gains kept; the
# edits that differ from the class files are overrides now
mig_eq "$MIG_LEVELS_V4" "$(mig_sql "$MIG/fresh.db" "$MIG_LEVELS_V4" | sed \
	-e 's/^1|5|2|/1|5|7|/' -e 's/^2|20|0|/2|20|3|/')" "levels (v2)"
mig_eq "SELECT key || '|' || field || '|' || value FROM content_overrides ORDER BY key, field" \
	"mage|levels.5.hp|7
warrior|levels.20.hp|3" "edited levels kept as overrides (v2)"
[ "$(mig_sql "$V2_DB" "$V2_DATA"; mig_users "$V2_DB")" = "$before" ] && t_ok || t_fail "v2 data changed by the migration"

t_section "migrate: version 3 database"
# version 3 schema + its game data with admin edits to the class names and the levels
# table, and players of each class; steps 4 and 5 run. Every class value of before the
# migration must come out the same (the edits as overrides), and the game must use them.
V3_DB="$MIG/v3.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V3_DB\"#" "$CONFIG" > "$MIG/v3.lua"
mig_script "$V3_DB" "$ROOT/tests/fixtures/schema_v3.sql"
mig_script "$V3_DB" "$ROOT/tests/fixtures/seed_v3.sql"
cat > "$MIG/v3_data.sql" <<'SQL'
UPDATE control SET class1name = 'Wizard', class3name = 'Templar';
UPDATE levels SET "1_hp" = 9, "1_spells" = 0 WHERE id = 2;
UPDATE levels SET "2_spells" = 7, "2_strength" = 30 WHERE id = 3;
UPDATE levels SET "3_mp" = 12, "3_dexterity" = 0 WHERE id = 50;
UPDATE levels SET "1_hp" = 99, "1_mp" = 99 WHERE id = 1;
INSERT INTO users (id, username, email, charname, verify, authlevel, charclass, level, experience, gold, maxhp, currenthp, spells) VALUES
	(1, 'wiz', 'w@example.com', 'Wiz', '1', 1, 1, 1, 14, 100, 15, 15, '0'),
	(2, 'war', 'r@example.com', 'War', '1', 0, 2, 2, 50, 100, 17, 17, '0,1'),
	(3, 'tem', 't@example.com', 'Tem', '1', 0, 3, 5, 300, 100, 30, 30, '0');
PRAGMA user_version = 3;
SQL
mig_script "$V3_DB" "$MIG/v3_data.sql"
MIG_DB=$V3_DB
mig_eq "PRAGMA user_version" "3" "fixture is version 3"
V3_LEVELS=$(mig_sql "$V3_DB" "$MIG_LEVELS_V3")
V3_USERS=$(mig_users "$V3_DB")
"$BIN" migrate --config "$MIG/v3.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v3) failed: $(cat "$T/migrate.log")"
grep -qF 'Migrating to version 4: character classes are content files' "$T/migrate.log" && t_ok || t_fail "step 4 not reported (v3)"
grep -qE 'Migrating to version [123]:' "$T/migrate.log" && t_fail "steps 1-3 ran on a version 3 database" || t_ok
grep -qF 'Content synced (spells: 19, 0 new, 0 retired; classes: 3, 0 new, 0 retired, 8 earlier admin edits kept as overrides; items: 68, 0 new, 0 retired).' "$T/migrate.log" \
	&& t_ok || t_fail "sync report (v3): $(cat "$T/migrate.log")"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v3 stamped"
[ "$(mig_layout "$V3_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v3 schema differs from a fresh install:"
	diff <(mig_layout "$V3_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v3)"
mig_eq "SELECT count(*) FROM pragma_table_info('control') WHERE name LIKE 'class%'" "0" "class names left control"
# every per-level value of before the migration, from the new tables
mig_eq "$MIG_LEVELS_V4" "$V3_LEVELS" "levels equal the pre-migration levels table"
mig_eq "SELECT id || '|' || key || '|' || name || '|' || sort || '|' || playable || '|' || start_hp || '|' || start_tp || '|' || exp_base || '|' || retired FROM classes ORDER BY id" \
	"1|mage|Wizard|1|1|15|10|15|0
2|warrior|Warrior|2|1|15|10|18|0
3|paladin|Templar|3|1|15|10|20|0" "class names kept, starting stats as before"
mig_eq "SELECT key || '|' || field || '|' || value FROM content_overrides ORDER BY key, field" \
	"mage|levels.2.hp|9
mage|levels.2.spells|
mage|name|Wizard
paladin|levels.50.dexterity|0
paladin|levels.50.mp|12
paladin|name|Templar
warrior|levels.3.spells|pain
warrior|levels.3.strength|30" "admin edits are overrides"
mig_eq "SELECT count(*) FROM content_adopt" "0" "adoptions done"
[ "$(mig_users "$V3_DB")" = "$V3_USERS" ] && t_ok || t_fail "users changed (v3)"
# War (level 2, "0,1") knows Heal, learned at level 2 like the Warrior schedule says
mig_eq "SELECT user_id || '|' || spell_id || '|' || learned_level FROM user_spells" "2|1|2" "known spells (v3)"
# a second sync changes nothing
before=$(mig_sql "$V3_DB" "$MIG_CLASSES; SELECT * FROM content_overrides")
"$BIN" content sync --config "$MIG/v3.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk content sync (v3)"
[ "$(mig_sql "$V3_DB" "$MIG_CLASSES; SELECT * FROM content_overrides")" = "$before" ] && t_ok || t_fail "resync changed the classes"
"$BIN" content status --config "$MIG/v3.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk content status (v3)"
grep -qF 'classes: 3 files, 3 in the database (0 retired), 8 overrides' "$T/migrate.log" && t_ok || t_fail "status: $(cat "$T/migrate.log")"
grep -qF 'The database is in sync with the content files' "$T/migrate.log" && t_ok || t_fail "status in sync: $(cat "$T/migrate.log")"
# the game on it: names, and a level-up with the migrated (overridden) level 2 gains of a
# Wizard (HP 9, no spell)
mig_serve "$MIG/v3.lua" "$MIG/v3server.log"
"$BIN" user --config "$MIG/v3.lua" passwd wiz v3pass1 >/dev/null && t_ok || t_fail "dk user passwd (v3)"
t_jar migv3
t_get /register;   expect_body '<option value="1">Wizard</option>'; expect_body '<option value="3">Templar</option>'
t_login wiz v3pass1; expect_redirect /
t_get /character;  expect_body 'Class: Wizard'
mig_sql "$V3_DB" "UPDATE users SET currentaction = 'Fighting', currentfight = 3, currentmonster = 1, currentmonsterhp = 0 WHERE id = 1"
t_get /victory;    expect_status 200; expect_body 'You have gained a level!'
mig_eq "SELECT level || '|' || experience || '|' || base_maxhp || '|' || base_maxmp || '|' || base_maxtp || '|' || coalesce($T_KNOWN, '') FROM users WHERE id = 1" \
	"2|15|24|5|11|" "level-up with the migrated gains"
mig_unserve "$MIG/v3server.log"

t_section "migrate: version 4 database"
# version 4 schema + its game data (spells with type and attribute, users.spells lists),
# admin edits to spells, class level overrides that list spell ids, a pending adoption,
# and players; only step 5 runs
V4_DB="$MIG/v4.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V4_DB\"#" "$CONFIG" > "$MIG/v4.lua"
mig_script "$V4_DB" "$ROOT/tests/fixtures/schema_v4.sql"
mig_script "$V4_DB" "$ROOT/tests/fixtures/seed_v4.sql"
cat > "$MIG/v4_data.sql" <<'SQL'
INSERT INTO class_spells (class_id, level, spell_id) VALUES (1, 2, 1), (1, 4, 6), (2, 2, 1);
UPDATE spells SET name = 'Mend', mp = 4, attribute = 12 WHERE id = 1;
UPDATE spells SET type = 4 WHERE id = 7;
UPDATE spells SET attribute = 99 WHERE id = 11;
INSERT INTO spells (id, name, mp, attribute, type) VALUES (20, 'Fireball', 9, 40, 2);
INSERT INTO content_overrides (kind, key, field, value) VALUES ('classes', 'mage', 'name', 'Wizard'),
	('classes', 'warrior', 'levels.3.spells', '7,99'), ('classes', 'mage', 'levels.2.spells', '');
INSERT INTO content_adopt (kind, key, field, value) VALUES ('classes', 'paladin', 'levels.5.spells', '7');
INSERT INTO users (id, username, email, charname, verify, authlevel, charclass, level, currenthp, maxhp, currentmp, maxmp, spells) VALUES
	(1, 'mag', 'm@example.com', 'Mag', '1', 1, 1, 5, 1, 50, 10, 10, '0,1,6,1,999,abc, 20'),
	(2, 'war', 'w@example.com', 'War', '1', 0, 2, 1, 15, 15, 0, 0, '0,1,7'),
	(3, 'nob', 'n@example.com', 'Nob', '1', 0, 3, 1, 15, 15, 0, 0, '0'),
	(4, 'odd', 'o@example.com', 'Odd', '1', 0, 9, 3, 15, 15, 0, 0, '2');
PRAGMA user_version = 4;
SQL
mig_script "$V4_DB" "$MIG/v4_data.sql"
MIG_DB=$V4_DB
mig_eq "PRAGMA user_version" "4" "fixture is version 4"
V4_USERS=$(mig_users "$V4_DB")
"$BIN" migrate --config "$MIG/v4.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v4) failed: $(cat "$T/migrate.log")"
grep -qF 'Migrating to version 5: spells are content files with effects; the spells characters know move to user_spells' \
	"$T/migrate.log" && t_ok || t_fail "step 5 not reported (v4)"
grep -qE 'Migrating to version [1234]:' "$T/migrate.log" && t_fail "steps 1-4 ran on a version 4 database" || t_ok
grep -qF "warning: spell 7 (Pain) had its type changed to 4; it keeps the effect of app/content/spells/pain.lua" \
	"$T/migrate.log" && t_ok || t_fail "type change not reported: $(cat "$T/migrate.log")"
grep -qF 'Content synced (spells: 19, 0 new, 1 retired, 4 earlier admin edits kept as overrides; classes: 3, 0 new, 0 retired, 1 earlier admin edits kept as overrides; items: 68, 0 new, 0 retired).' \
	"$T/migrate.log" && t_ok || t_fail "sync report (v4): $(cat "$T/migrate.log")"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v4 stamped"
[ "$(mig_layout "$V4_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v4 schema differs from a fresh install:"
	diff <(mig_layout "$V4_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v4)"
mig_eq "SELECT count(*) FROM pragma_table_info('users') WHERE name = 'spells'" "0" "users.spells dropped"
# the unedited spells equal a fresh install's; the edits are overrides (a changed type is
# not kept; the sleep chance of 99, which version 5 couldn't keep, is a power now, as the
# original game would have had it: the monster never wakes up); the extra spell is
# retired, its data kept
mig_eq "$MIG_SPELLS" "$(mig_sql "$MIG/fresh.db" "$MIG_SPELLS" | sed 's/^1|heal|Heal|\([^|]*\)|5|both|0|10|/1|heal|Mend|\1|4|both|0|12|/; s/^11|sleep|Sleep|\([^|]*\)|10|fight|0|5|/11|sleep|Sleep|\1|10|fight|0|99|/')
20|spell_20|Fireball||9|fight|1|40|enemy||" "spells (v4)"
mig_eq "SELECT kind || '|' || key || '|' || field || '|' || value FROM content_overrides ORDER BY kind, key, field" \
	"classes|mage|levels.2.spells|
classes|mage|name|Wizard
classes|paladin|levels.5.spells|pain
classes|warrior|levels.3.spells|pain
spells|heal|mp|4
spells|heal|name|Mend
spells|heal|power|12
spells|sleep|power|99" "spell edits and class spell ids as keys"
mig_eq "SELECT count(*) FROM content_adopt" "0" "adoptions done (v4)"
mig_eq "SELECT class_id || '|' || level || '|' || group_concat(spell_id) FROM class_spells
	WHERE (class_id, level) IN (VALUES (1, 2), (2, 3), (3, 5)) GROUP BY class_id, level ORDER BY 1" \
	"2|3|7
3|5|7" "class spells from the converted overrides"
# users.spells exploded with legacy's matching (0, unknown ids, junk and duplicates
# ignored; " 20" matches 20); learned_level from the class schedule when not above the level
mig_eq "SELECT user_id || '|' || spell_id || '|' || coalesce(learned_level, '-') FROM user_spells ORDER BY user_id, spell_id" \
	"1|1|2
1|6|4
1|20|-
2|1|-
2|7|-
4|2|-" "known spells (v4)"
[ "$(mig_users "$V4_DB")" = "$V4_USERS" ] && t_ok || t_fail "users otherwise changed (v4)"
"$BIN" content status --config "$MIG/v4.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk content status (v4)"
grep -qF 'spells: 19 files, 20 in the database (1 retired), 4 overrides' "$T/migrate.log" && t_ok || t_fail "status (v4): $(cat "$T/migrate.log")"
grep -qF 'The database is in sync with the content files' "$T/migrate.log" && t_ok || t_fail "status in sync (v4): $(cat "$T/migrate.log")"
# the game on it: the overridden Heal, the retired Fireball (known, but without a file
# there is no code to cast it)
mig_serve "$MIG/v4.lua" "$MIG/v4server.log"
"$BIN" user --config "$MIG/v4.lua" passwd mag v4pass1 >/dev/null && t_ok || t_fail "dk user passwd (v4)"
t_jar migv4
t_login mag v4pass1; expect_redirect /
t_get /character;  expect_body 'Mend<br>'; expect_body 'Hurt<br>'; expect_body 'Fireball<br>'
t_get /;           expect_body 'action="/spell/1">'
t_post /spell/1 "csrf=$(t_csrf)"; expect_body 'You have cast the Mend spell, and gained 12 Hit Points.'
mig_eq "SELECT currenthp || '|' || currentmp FROM users WHERE id = 1" "13|6" "heal with the migrated values"
mig_sql "$V4_DB" "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 2, currentmonsterhp = 100 WHERE id = 1"
mig_sql "$V4_DB" "UPDATE users SET currentmp = 9 WHERE id = 1"
t_get /fight;      expect_no_body '<option value="20">Fireball</option>'; expect_body '<option value="6">Hurt</option>'
t_post /fight "csrf=$(t_csrf)&spell=Spell&userspell=20"; expect_body 'This spell cannot be cast.'
mig_eq "SELECT currentmp || '|' || currentmonsterhp FROM users WHERE id = 1" "9|100" "nothing spent"
mig_unserve "$MIG/v4server.log"

t_section "migrate: version 5 database"
# version 5 schema + its game data (items, drops, towns.itemslist), admin edits to items,
# drops and a town, admin-added items, and characters with gear, drops (negative ones too),
# bonuses, a pending drop, and stored stats the original's arithmetic left inconsistent;
# only step 6 runs. Every character's effective stats must be the same before and after.
V5_DB="$MIG/v5.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V5_DB\"#" "$CONFIG" > "$MIG/v5.lua"
mig_script "$V5_DB" "$ROOT/tests/fixtures/schema_v5.sql"
mig_script "$V5_DB" "$ROOT/tests/fixtures/seed_v5.sql"
cat > "$MIG/v5_data.sql" <<'SQL'
UPDATE items SET name = 'Twig', buycost = 12 WHERE id = 1;
UPDATE items SET attribute = 120 WHERE id = 12;
UPDATE items SET special = 'expbonus,-8' WHERE id = 13;
UPDATE items SET special = 'X' WHERE id = 15;
UPDATE items SET special = 'maxhp,20' WHERE id = 18;
UPDATE items SET special = 'gold,100' WHERE id = 19;
UPDATE items SET type = 1 WHERE id = 30;
UPDATE drops SET mlevel = 2, attribute2 = 'dexterity,5' WHERE id = 1;
UPDATE drops SET name = 'Fortune Stone' WHERE id = 32;
INSERT INTO items (id, type, name, buycost, attribute, special) VALUES (34, 1, 'Custom Blade', 99, 7, 'strength,3');
INSERT INTO drops (id, name, mlevel, type, attribute1, attribute2) VALUES (33, 'Odd Gem', 3, 1, 'maxtp,5', 'X');
UPDATE towns SET itemslist = '0,1,34,2' WHERE id = 1;
INSERT INTO users (id, username, email, charname, verify, authlevel, charclass, level, currenthp, maxhp, maxmp, maxtp,
	strength, dexterity, attackpower, defensepower, expbonus, goldbonus, weaponid, armorid, shieldid, slot1id, slot2id,
	slot3id, weaponname, armorname, shieldname, slot1name, slot2name, slot3name, dropcode) VALUES
	(1, 'gearhead', 'g@example.com', 'Gearhead', '1', 1, 1, 30, 90, 100, 50, 40, 130, 70, 380, 370, 10, 10,
		16, 27, 33, 13, 32, 31, 'Destiny Blade', 'Destiny Raiment', 'Destiny Aegis', 'Demon''s Sin', 'Fortune Drop', 'Memory Drop', 0),
	(2, 'negative', 'n@example.com', 'Negative', '1', 0, 2, 45, 0, 0, 0, 10, 105, 5, 105, 5, 0, 0,
		0, 0, 0, 15, 0, 0, 'None', 'None', 'None', 'Demon''s Lie', 'None', 'None', 7),
	(3, 'oddone', 'o@example.com', 'Oddone', '1', 0, 3, 3, 15, 15, 0, 10, 10, 7, 20, 12, 0, 0,
		1, 18, 0, 0, 0, 0, 'Stick', 'Clothes', 'None', 'None', 'None', 'None', 0),
	(4, 'custom', 'c@example.com', 'Custom', '1', 0, 1, 2, 15, 15, 0, 15, 8, 5, 15, 5, 0, 0,
		34, 0, 0, 33, 0, 0, 'Custom Blade', 'None', 'None', 'Odd Gem', 'None', 'None', 0),
	(5, 'plain', 'p@example.com', 'Plain', '1', 0, 1, 1, 15, 15, 0, 10, 5, 5, 5, 5, 5, -3,
		0, 0, 0, 0, 0, 0, 'None', 'None', 'None', 'None', 'None', 'None', 0),
	(6, 'typo', 't@example.com', 'Typo', '1', 0, 2, 4, 15, 15, 0, 10, 5, 5, 15, 5, 0, 0,
		30, 0, 0, 0, 0, 0, 'Small Shield', 'None', 'None', 'None', 'None', 'None', 0),
	(7, 'swordy', 's@example.com', 'Swordy', '1', 0, 1, 20, 15, 15, 0, 10, 5, 5, 130, 7, -8, 10,
		13, 17, 0, 0, 0, 0, 'Dark Sword', 'Skivvies', 'None', 'None', 'None', 'None', 0),
	(8, 'leather', 'l@example.com', 'Leather', '1', 0, 1, 5, 15, 15, 0, 10, 5, 5, 5, 15, 0, 0,
		0, 19, 0, 0, 0, 0, 'None', 'Leather Armor', 'None', 'None', 'None', 'None', 0);
PRAGMA user_version = 5;
SQL
mig_script "$V5_DB" "$MIG/v5_data.sql"
MIG_DB=$V5_DB
mig_eq "PRAGMA user_version" "5" "fixture is version 5"
V5_STATS="SELECT 'Max HP ' || maxhp || ', Max MP ' || maxmp || ', Max TP ' || maxtp || ', Strength ' || strength ||
	', Dexterity ' || dexterity || ', Attack Power ' || attackpower || ', Defense Power ' || defensepower ||
	', Experience Bonus ' || expbonus || '%, Gold Bonus ' || goldbonus || '%' FROM users ORDER BY id"
V5_BEFORE=$(mig_sql "$V5_DB" "$V5_STATS")
V5_KEPT="SELECT id, username, password, email, charname, authlevel, charclass, level, gold, experience, currenthp,
	currentmp, currenttp, currentaction, latitude, longitude, towns FROM users ORDER BY id"
V5_USERS=$(mig_sql "$V5_DB" "$V5_KEPT")
"$BIN" migrate --config "$MIG/v5.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v5) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version [12345]:' "$T/migrate.log" && t_fail "steps 1-5 ran on a version 5 database" || t_ok
for line in 'Migrating to version 6: items and drops are content files; inventories (user_items), shop lists (town_items) and base stats' \
	'Converted the stats of 8 characters to base stats (verified); 1 keep extra attack/defense power.' \
	'note: character Oddone (user 3) keeps 8 attack and 0 defense power that strength, dexterity and gear don'"'"'t give' \
	'warning: item 19 (Leather Armor) has the special "gold,100", which is not a stat' \
	'warning: item 30 (Small Shield) had its type changed to 1; it keeps the category of app/content/items/small_shield.lua' \
	'Content synced (spells: 19, 0 new, 0 retired; classes: 3, 0 new, 0 retired; items: 68, 0 new, 2 retired, 11 earlier admin edits kept as overrides).' \
	'warning: character Typo (user 6): the items'"'"' new values changed attack, defense; base stats adjusted to keep them'; do
	grep -qF "$line" "$T/migrate.log" && t_ok || t_fail "migrate (v5) output lacks: $line
$(cat "$T/migrate.log")"
done
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v5 stamped"
[ "$(mig_layout "$V5_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v5 schema differs from a fresh install:"
	diff <(mig_layout "$V5_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v5)"
mig_eq "SELECT count(*) FROM sqlite_master WHERE name IN ('drops', 'v6_expected')" "0" "drops table dropped, temp table gone"
mig_eq "$V5_KEPT" "$V5_USERS" "users otherwise unchanged (v5)"
# the edits are overrides; the admin-added rows are retired items (69, 70), kept for their owners
mig_eq "SELECT key || '|' || field || '|' || value FROM content_overrides WHERE kind = 'items' ORDER BY key, field" \
	"clothes|modifiers.1.amount|20
clothes|modifiers.1.stat|maxhp
dark_axe|attack|120
dark_sword|modifiers.1.amount|-8
fortune_drop|name|Fortune Stone
life_pebble|drop_level|2
life_pebble|modifiers.2.amount|5
life_pebble|modifiers.2.stat|dexterity
magic_sword|modifiers.1.amount|0
stick|name|Twig
stick|price|12" "item edits kept as overrides"
mig_eq "SELECT id || '|' || key || '|' || name || '|' || category || '|' || attack || '|' || modifiers || '|' || coalesce(drop_level, '-') || '|' || retired FROM items WHERE id > 68 ORDER BY id" \
	"69|item_34|Custom Blade|weapon|7|stat stat=strength amount=3|-|1
70|drop_33|Odd Gem|accessory|0|stat stat=maxtp amount=5|3|1" "admin-added items"
V5_EDITED="'stick', 'dark_axe', 'dark_sword', 'clothes', 'magic_sword', 'life_pebble', 'fortune_drop'"
mig_eq "SELECT * FROM items WHERE id <= 68 AND key NOT IN ($V5_EDITED) ORDER BY id" \
	"$(mig_sql "$MIG/fresh.db" "SELECT * FROM items WHERE key NOT IN ($V5_EDITED) ORDER BY id")" "unedited items equal a fresh install's"
mig_eq "SELECT name || '|' || price || '|' || modifiers FROM items WHERE key IN ('stick', 'clothes', 'magic_sword') ORDER BY id" \
	"Twig|12|
Magic Sword|10000|stat stat=maxmp amount=0
Clothes|50|stat stat=maxhp amount=20" "edited items"
mig_eq "SELECT town_id || '|' || item_id FROM town_items WHERE town_id = 1 ORDER BY item_id" "1|1
1|2
1|66
1|69" "Midworld's edited list (and the new Herbs)"
mig_eq "SELECT * FROM town_items WHERE town_id > 1 ORDER BY town_id, item_id" \
	"$(mig_sql "$MIG/fresh.db" "SELECT * FROM town_items WHERE town_id > 1 ORDER BY town_id, item_id")" "other shops equal a fresh install's"
# equipment and drops became user_items, the pending drop its item id
mig_eq "SELECT id || ':' || coalesce($T_ITEMS, '') || ':' || dropcode FROM users ORDER BY id" \
	"1:destiny_blade@weapon,destiny_raiment@armor,destiny_aegis@shield,demons_sin@accessory1,fortune_drop@accessory2,memory_drop@accessory3:0
2:demons_lie@accessory1:40
3:stick@weapon,clothes@armor:0
4:item_34@weapon,drop_33@accessory1:0
5::0
6:small_shield@weapon:0
7:dark_sword@weapon,skivvies@armor:0
8:leather_armor@armor:0" "inventories"
mig_eq "SELECT id || '|' || base_maxhp || '|' || strength || '|' || dexterity || '|' || base_attack || '|' || base_defense || '|' || base_exp_bonus || '|' || base_gold_bonus FROM users ORDER BY id" \
	"1|100|30|20|0|0|0|0
2|100|5|5|0|0|0|0
3|-5|10|7|8|0|0|0
4|15|5|5|0|0|0|0
5|15|5|5|0|0|5|-3
6|15|5|5|10|-10|0|0
7|15|5|5|0|0|0|0
8|15|5|5|0|0|0|0" "base stats"
# the game computes the same effective stats as were stored before (admin user editor)
mig_serve "$MIG/v5.lua" "$MIG/v5server.log"
"$BIN" user --config "$MIG/v5.lua" passwd gearhead v5pass1 >/dev/null && t_ok || t_fail "dk user passwd (v5)"
t_jar migv5
t_login gearhead v5pass1; expect_redirect /
after=
for id in 1 2 3 4 5 6 7 8; do
	t_get "/admin/users/$id"
	after+="$(grep -o 'Max HP [0-9-]*, Max MP .*Gold Bonus [0-9-]*%' "$BODY")"$'\n'
done
[ "${after%$'\n'}" = "$V5_BEFORE" ] && t_ok || {
	t_fail "effective stats changed by the migration:"
	diff <(printf '%s\n' "$V5_BEFORE") <(printf '%s' "$after") >&2
}
t_get /character;  expect_body 'Attack Power: 380<'; expect_body 'Defense Power: 370<'; expect_body 'Slot 2: Fortune Stone'
expect_body 'Experience: 0 <span class="light">(+10%)</span>'
expect_stats "100 50 40 130 70 380 370" "gearhead"
t_get /inventory;  expect_body 'Demon&#39;s Sin'
t_post /inventory/unequip/accessory1 "csrf=$(t_csrf)"; expect_body 'You took off the Demon&#39;s Sin.'
expect_stats "150 50 40 80 70 330 370" "without the Demon's Sin"
mig_unserve "$MIG/v5server.log"
"$BIN" migrate --config "$MIG/v5.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v5)"

t_section "migrate: version 6 database"
# version 6 schema + its game data, admin edits of effect amounts (overrides and a pending
# adoption, some that can't be kept), retired spells and consumables that only exist in
# the database, and a character mid-fight who knows them; only step 7 runs. The spells
# and consumables become scripted: power, target, messages and data instead of effects.
V6_DB="$MIG/v6.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V6_DB\"#" "$CONFIG" > "$MIG/v6.lua"
mig_script "$V6_DB" "$ROOT/tests/fixtures/schema_v6.sql"
mig_script "$V6_DB" "$ROOT/tests/fixtures/seed_v6.sql"
cat > "$MIG/v6_data.sql" <<'SQL'
INSERT INTO content_overrides (kind, key, field, value) VALUES ('spells', 'hurt', 'effects.1.max', '20'),
	('spells', 'hurt', 'name', 'Smite'), ('spells', 'sleep', 'effects.1.chance', '7'),
	('items', 'herb', 'use_effects.1.amount', '45'), ('items', 'stick', 'price', '12'),
	('spells', 'zap', 'effects.1.min', '5'), ('spells', 'zap', 'effects.2.pct', '25');
INSERT INTO content_adopt (kind, key, field, value) VALUES ('spells', 'rage', 'effects.1.pct', '30');
INSERT INTO spells (id, key, name, mp, usable_in, effects, retired) VALUES
	(20, 'zap', 'Zap', 3, 'fight', 'damage max=6 min=6; buff_defense_pct pct=20', 1),
	(21, 'mend', 'Mend', 2, 'both', 'heal_hp amount=8', 1);
INSERT INTO items (id, key, name, category, price, max_stack, use_effects, sellable, retired) VALUES
	(69, 'bomb', 'Bomb', 'consumable', 5, 5, 'damage max=12', 1, 1),
	(70, 'elixir', 'Elixir', 'consumable', 50, 5, 'heal_hp amount=9; heal_mp amount=2', 1, 1);
INSERT INTO users (id, username, email, charname, verify, authlevel, charclass, level, currentaction, currentfight,
	currentmonster, currentmonsterhp, currentmonsterimmune, currentuberdefense, currenthp, base_maxhp, currentmp,
	base_maxmp) VALUES (1, 'caster', 'c@example.com', 'Caster', '1', 1, 1, 10, 'Fighting', 2, 2, 50, 0, 25, 20, 40, 30, 30);
INSERT INTO user_spells (user_id, spell_id, learned_level) VALUES (1, 1, 2), (1, 6, 4), (1, 20, NULL), (1, 21, NULL);
INSERT INTO user_items (user_id, item_id, qty, equipped) VALUES (1, 66, 2, NULL), (1, 69, 1, NULL), (1, 70, 1, NULL);
PRAGMA user_version = 6;
SQL
mig_script "$V6_DB" "$MIG/v6_data.sql"
MIG_DB=$V6_DB
mig_eq "PRAGMA user_version" "6" "fixture is version 6"
V6_KEPT="SELECT * FROM users ORDER BY id; SELECT * FROM user_spells ORDER BY user_id, spell_id;
	SELECT * FROM user_items ORDER BY id; SELECT * FROM town_items ORDER BY town_id, item_id"
V6_BEFORE=$(mig_sql "$V6_DB" "$V6_KEPT")
"$BIN" migrate --config "$MIG/v6.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v6) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version [123456]:' "$T/migrate.log" && t_fail "steps 1-6 ran on a version 6 database" || t_ok
for line in 'Migrating to version 7: spells and consumables are scripted content' \
	'warning: spell zap: the edit of effects.1.min (5) can'"'"'t be kept: spells and items are scripted now, with one power' \
	'warning: spell zap: the edit of effects.2.pct (25) can'"'"'t be kept' \
	'Content synced (spells: 19, 0 new, 0 retired, 1 earlier admin edits kept as overrides; classes: 3, 0 new, 0 retired; items: 68, 0 new, 0 retired).'; do
	grep -qF "$line" "$T/migrate.log" && t_ok || t_fail "migrate (v6) output lacks: $line
$(cat "$T/migrate.log")"
done
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v6 stamped"
[ "$(mig_layout "$V6_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v6 schema differs from a fresh install:"
	diff <(mig_layout "$V6_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v6)"
mig_eq "$V6_KEPT" "$V6_BEFORE" "characters, their spells and items, shops unchanged (v6)"
# the edited amounts are power overrides now (the adoption too: it differs from the file)
mig_eq "SELECT kind || '|' || key || '|' || field || '|' || value FROM content_overrides ORDER BY kind, key, field" \
	"items|herb|power|45
items|stick|price|12
spells|hurt|name|Smite
spells|hurt|power|20
spells|rage|power|30
spells|sleep|power|7" "effect edits became power overrides"
mig_eq "SELECT count(*) FROM content_adopt" "0" "adoptions done"
V6_EDITED="'hurt', 'sleep', 'rage'"
mig_eq "$MIG_SPELLS_OF WHERE key NOT IN ($V6_EDITED) AND id <= 19 ORDER BY id" \
	"$(mig_sql "$MIG/fresh.db" "$MIG_SPELLS_OF WHERE key NOT IN ($V6_EDITED) ORDER BY id")" "unedited spells equal a fresh install's (v6)"
mig_eq "SELECT key || '|' || name || '|' || power || '|' || target FROM spells WHERE key IN ($V6_EDITED) ORDER BY id" \
	"hurt|Smite|20|enemy
sleep|Sleep|7|enemy
rage|Rage|30|self" "edited spells"
# the database-only rows keep their old amount as power, for display (they have no code)
mig_eq "$MIG_SPELLS_OF WHERE id > 19 ORDER BY id" "20|zap|Zap||3|fight|1|6|enemy||
21|mend|Mend||2|both|1|8|self||" "retired spells (v6)"
mig_eq "SELECT id || '|' || key || '|' || usable_in || '|' || target || '|' || power || '|' || retired FROM items WHERE id > 68 ORDER BY id" \
	"69|bomb|fight|enemy|12|1
70|elixir|both|self|9|1" "retired consumables (v6)"
mig_eq "SELECT * FROM items WHERE id <= 68 AND key NOT IN ('herb', 'stick') ORDER BY id" \
	"$(mig_sql "$MIG/fresh.db" "SELECT * FROM items WHERE key NOT IN ('herb', 'stick') ORDER BY id")" "unedited items equal a fresh install's (v6)"
# the character mid-fight goes on: the overridden Hurt, a Herb with its new power; the
# retired spell and consumables are known / kept but can't be used
mig_serve "$MIG/v6.lua" "$MIG/v6server.log"
"$BIN" user --config "$MIG/v6.lua" passwd caster v6pass1 >/dev/null && t_ok || t_fail "dk user passwd (v6)"
t_jar migv6
t_login caster v6pass1
t_get /fight;      expect_status 200; expect_body '<option value="6">Smite</option>'; expect_no_body '>Zap</option>'
expect_body '<option value="66">Herb (x2)</option>'; expect_no_body '>Bomb ('; expect_no_body '>Elixir ('
V6_CS=$(t_csrf)
t_post /fight "csrf=$V6_CS&spell=Spell&userspell=6"; expect_body 'You have cast the Smite spell for'
V6_HP=$(mig_sql "$V6_DB" "SELECT currentmonsterhp FROM users WHERE id = 1")
[ "$V6_HP" -ge 30 ] && [ "$V6_HP" -le 34 ] && t_ok || t_fail "Smite (power 20: 16-20 damage) left the monster $V6_HP HP"
mig_eq "SELECT currentmp || '|' || currentuberdefense FROM users WHERE id = 1" "25|25" "MP spent, the fight's buff kept"
t_post /fight "csrf=$V6_CS&spell=Spell&userspell=20"; expect_body 'This spell cannot be cast.'
mig_sql "$V6_DB" "UPDATE users SET currenthp = 1 WHERE id = 1"
t_post /fight "csrf=$V6_CS&item=Use+Item&useritem=66"; expect_body 'You have used the Herb, and gained 39 Hit Points.'
t_post /fight "csrf=$V6_CS&item=Use+Item&useritem=69"; expect_body 'This item cannot be used.'
t_get /help/spells; expect_body '>Smite<br>'; expect_no_body '>Zap<'
mig_unserve "$MIG/v6server.log"
"$BIN" migrate --config "$MIG/v6.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v6)"

t_section "migrate: partial and forced installs are current"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$MIG/partial.db\"#" "$CONFIG" > "$MIG/partial.lua"
"$BIN" install --config "$MIG/partial.lua" --partial --admin part part@example.com partpw --charname Parter \
	>/dev/null 2>&1 && t_ok || t_fail "partial install"
MIG_DB="$MIG/partial.db"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "partial install stamped"
mig_eq "SELECT count(*) FROM forums" "2" "partial install has the boards"
mig_eq "SELECT count(*) FROM towns" "0" "partial install has no game data"
mig_eq "SELECT count(*) || '|' || (SELECT count(*) FROM class_levels) FROM classes" "3|297" "partial install has the classes"
mig_eq "SELECT count(*) || '|' || max(id) || '|' || sum(messages <> '') FROM spells" "19|19|19" "partial install has the spells"
mig_eq "SELECT count(*) || '|' || max(id) || '|' || (SELECT count(*) FROM town_items) FROM items" "68|68|0" "partial install has the items, no shops"
mig_eq "SELECT f.board || '|' || f.author || '|' || (f.author_id = n.author_id) FROM news n JOIN forum f ON f.id = n.thread_id" \
	"2|Parter|1" "partial install news thread"
"$BIN" install --config "$MIG/partial.lua" --force --admin part part@example.com partpw \
	>/dev/null 2>&1 && t_ok || t_fail "install --force over a current database"
mig_eq "SELECT count(*) || '|' || (SELECT count(*) FROM forum) || '|' || (SELECT count(*) FROM towns) FROM news" "1|1|8" "forced install"

fi
