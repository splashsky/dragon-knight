# tests/e2e/migrate.sh :: schema versioning: `dk migrate` from the pre-versioning schema
# (tests/fixtures/schema_v0.sql), from version 1 (tests/fixtures/schema_v1.sql) and from
# version 2 (tests/fixtures/schema_v2.sql), the 503 page for an outdated database, and
# no-op runs.
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
grep -v '^INSERT INTO forums ' "$T/app/sql/seed.sql" > "$MIG/seed_v0.sql"
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
mig_eq "SELECT * FROM levels ORDER BY id" "$(mig_sql "$MIG/fresh.db" "SELECT * FROM levels ORDER BY id")" \
	"levels equal a fresh install's"
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
mig_script "$V1_DB" "$T/app/sql/seed.sql"
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
	SELECT id, gamename, gamesize, gameopen, forumtype, class1name, class2name, class3name, verifyemail FROM control;
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
"$BIN" user --config "$MIG/v1.lua" list >"$T/migrate.log" 2>&1 && grep -q 'hardone' "$T/migrate.log" \
	&& t_ok || t_fail "dk user list on the migrated v1 database: $(cat "$T/migrate.log")"

t_section "migrate: version 2 database"
# version 2 schema (levels with exp and tp columns, milestone HP in the hp columns) + the
# game data, admin edits to levels 5 and 20, and players; only step 3 runs
V2_DB="$MIG/v2.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V2_DB\"#" "$CONFIG" > "$MIG/v2.lua"
mig_script "$V2_DB" "$ROOT/tests/fixtures/schema_v2.sql"
mig_script "$V2_DB" "$T/app/sql/seed.sql"
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
V2_DATA="SELECT * FROM users ORDER BY id; SELECT * FROM control; SELECT count(*) FROM monsters"
before=$(mig_sql "$V2_DB" "$V2_DATA")
"$BIN" migrate --config "$MIG/v2.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v2) failed: $(cat "$T/migrate.log")"
grep -qF 'Migrating to version 3: experience, TP and HP milestones per level are formulas (edited exp/tp values are discarded)' \
	"$T/migrate.log" && t_ok || t_fail "step 3 not reported (v2)"
grep -qE 'Migrating to version [12]:' "$T/migrate.log" && t_fail "steps 1-2 ran on a version 2 database" || t_ok
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v2 stamped"
mig_eq "SELECT count(*) FROM pragma_table_info('levels') WHERE name LIKE '%exp' OR name LIKE '%tp'" "0" \
	"exp and tp columns dropped"
[ "$(mig_layout "$V2_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v2 schema differs from a fresh install:"
	diff <(mig_layout "$V2_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v2)"
# milestone HP taken off (an edited value keeps its difference), other gains kept
mig_eq "SELECT * FROM levels WHERE id NOT IN (5, 20, 99) ORDER BY id" \
	"$(mig_sql "$MIG/fresh.db" "SELECT * FROM levels WHERE id NOT IN (5, 20, 99) ORDER BY id")" "levels (v2)"
mig_eq "SELECT \"1_hp\" || '|' || \"2_hp\" || '|' || \"3_hp\" FROM levels WHERE id IN (5, 20, 99) ORDER BY id" \
	"7|2|2
0|3|0
0|0|0" "edited levels (v2)"
[ "$(mig_sql "$V2_DB" "$V2_DATA")" = "$before" ] && t_ok || t_fail "v2 data changed by the migration"

t_section "migrate: partial and forced installs are current"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$MIG/partial.db\"#" "$CONFIG" > "$MIG/partial.lua"
"$BIN" install --config "$MIG/partial.lua" --partial --admin part part@example.com partpw --charname Parter \
	>/dev/null 2>&1 && t_ok || t_fail "partial install"
MIG_DB="$MIG/partial.db"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "partial install stamped"
mig_eq "SELECT count(*) FROM forums" "2" "partial install has the boards"
mig_eq "SELECT count(*) FROM towns" "0" "partial install has no game data"
mig_eq "SELECT f.board || '|' || f.author || '|' || (f.author_id = n.author_id) FROM news n JOIN forum f ON f.id = n.thread_id" \
	"2|Parter|1" "partial install news thread"
"$BIN" install --config "$MIG/partial.lua" --force --admin part part@example.com partpw \
	>/dev/null 2>&1 && t_ok || t_fail "install --force over a current database"
mig_eq "SELECT count(*) || '|' || (SELECT count(*) FROM forum) || '|' || (SELECT count(*) FROM towns) FROM news" "1|1|8" "forced install"

fi
