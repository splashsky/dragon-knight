# tests/e2e/migrate.sh :: schema versioning: `dk migrate` from the pre-versioning schema
# (tests/fixtures/schema_v0.sql) and from versions 1, 2 and 3 (tests/fixtures/schema_vN.sql,
# with the game data of that time, tests/fixtures/seed_v3.sql), the 503 page for an
# outdated database, and no-op runs.
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
grep -qF "Content synced (classes: 3, 0 new, 0 retired)." "$T/migrate.log" && t_ok || t_fail "content sync message: $(cat "$T/migrate.log")"
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
grep -qF 'Content synced (classes: 3, 0 new, 0 retired).' "$T/migrate.log" && t_ok || t_fail "content not synced by migrate"
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
V2_DATA="SELECT * FROM users ORDER BY id; SELECT id, gamename, gamesize, gameopen, gameurl, adminemail,
	forumtype, forumaddress, compression, verifyemail, shownews, showbabble, showonline FROM control;
	SELECT count(*) FROM monsters"
before=$(mig_sql "$V2_DB" "$V2_DATA")
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
[ "$(mig_sql "$V2_DB" "$V2_DATA")" = "$before" ] && t_ok || t_fail "v2 data changed by the migration"

t_section "migrate: version 3 database"
# version 3 schema + its game data with admin edits to the class names and the levels
# table, and players of each class; only step 4 runs. Every class value of before the
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
V3_USERS=$(mig_sql "$V3_DB" "SELECT * FROM users ORDER BY id")
"$BIN" migrate --config "$MIG/v3.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v3) failed: $(cat "$T/migrate.log")"
grep -qF 'Migrating to version 4: character classes are content files' "$T/migrate.log" && t_ok || t_fail "step 4 not reported (v3)"
grep -qE 'Migrating to version [123]:' "$T/migrate.log" && t_fail "steps 1-3 ran on a version 3 database" || t_ok
grep -qF 'Content synced (classes: 3, 0 new, 0 retired, 8 earlier admin edits kept as overrides).' "$T/migrate.log" \
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
warrior|levels.3.spells|7
warrior|levels.3.strength|30" "admin edits are overrides"
mig_eq "SELECT count(*) FROM content_adopt" "0" "adoptions done"
mig_eq "SELECT * FROM users ORDER BY id" "$V3_USERS" "users unchanged (v3)"
# a second sync changes nothing
before=$(mig_sql "$V3_DB" "$MIG_CLASSES; SELECT * FROM content_overrides")
"$BIN" content sync --config "$MIG/v3.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk content sync (v3)"
[ "$(mig_sql "$V3_DB" "$MIG_CLASSES; SELECT * FROM content_overrides")" = "$before" ] && t_ok || t_fail "resync changed the classes"
"$BIN" content status --config "$MIG/v3.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk content status (v3)"
grep -qF 'classes: 3 files, 3 in the database (0 retired), 8 overrides' "$T/migrate.log" && t_ok || t_fail "status: $(cat "$T/migrate.log")"
grep -qF 'The database is in sync with the content files' "$T/migrate.log" && t_ok || t_fail "status in sync: $(cat "$T/migrate.log")"
# the game on it: names, and a level-up with the migrated (overridden) level 2 gains of a
# Wizard (HP 9, no spell)
"$BIN" serve --config "$MIG/v3.lua" >"$MIG/v3server.log" 2>&1 &
MIG_PID=$!
MIG_PORT=
for _ in $(seq 1 100); do
	MIG_PORT=$(sed -n 's/.*http: listening on [^ ]*:\([0-9][0-9]*\)$/\1/p' "$MIG/v3server.log" | head -n1)
	[ -n "$MIG_PORT" ] && break
	sleep 0.05
done
MAIN_BASE=$BASE
BASE="http://127.0.0.1:$MIG_PORT"
"$BIN" user --config "$MIG/v3.lua" passwd wiz v3pass1 >/dev/null && t_ok || t_fail "dk user passwd (v3)"
t_jar migv3
t_get /register;   expect_body '<option value="1">Wizard</option>'; expect_body '<option value="3">Templar</option>'
t_login wiz v3pass1; expect_redirect /
t_get /character;  expect_body 'Class: Wizard'
mig_sql "$V3_DB" "UPDATE users SET currentaction = 'Fighting', currentfight = 3, currentmonster = 1, currentmonsterhp = 0 WHERE id = 1"
t_get /victory;    expect_status 200; expect_body 'You have gained a level!'
mig_eq "SELECT level || '|' || experience || '|' || maxhp || '|' || maxmp || '|' || maxtp || '|' || spells FROM users WHERE id = 1" \
	"2|15|24|5|11|0" "level-up with the migrated gains"
BASE=$MAIN_BASE
kill "$MIG_PID" 2>/dev/null && wait "$MIG_PID" 2>/dev/null
if grep -q '\[error\]' "$MIG/v3server.log"; then
	t_fail "errors in the v3 server's log:"; grep -A5 '\[error\]' "$MIG/v3server.log" | head -20 >&2
fi
t_jar default

t_section "migrate: partial and forced installs are current"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$MIG/partial.db\"#" "$CONFIG" > "$MIG/partial.lua"
"$BIN" install --config "$MIG/partial.lua" --partial --admin part part@example.com partpw --charname Parter \
	>/dev/null 2>&1 && t_ok || t_fail "partial install"
MIG_DB="$MIG/partial.db"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "partial install stamped"
mig_eq "SELECT count(*) FROM forums" "2" "partial install has the boards"
mig_eq "SELECT count(*) FROM towns" "0" "partial install has no game data"
mig_eq "SELECT count(*) || '|' || (SELECT count(*) FROM class_levels) FROM classes" "3|297" "partial install has the classes"
mig_eq "SELECT f.board || '|' || f.author || '|' || (f.author_id = n.author_id) FROM news n JOIN forum f ON f.id = n.thread_id" \
	"2|Parter|1" "partial install news thread"
"$BIN" install --config "$MIG/partial.lua" --force --admin part part@example.com partpw \
	>/dev/null 2>&1 && t_ok || t_fail "install --force over a current database"
mig_eq "SELECT count(*) || '|' || (SELECT count(*) FROM forum) || '|' || (SELECT count(*) FROM towns) FROM news" "1|1|8" "forced install"

fi
