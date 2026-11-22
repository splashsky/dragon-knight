# tests/e2e/migrate.sh :: schema versioning: `dk migrate` from the pre-versioning schema
# (tests/fixtures/schema_v0.sql) and from versions 1 to 9 and 11 (tests/fixtures/schema_vN.sql,
# with the game data of that time, tests/fixtures/seed_v3.sql to seed_v11.sql), the 503
# page for an outdated database, and no-op runs. Version 5 -> 6 checks that every
# character's effective stats are the same before and after; version 6 -> 7 that edited
# effect amounts become power overrides and a fight goes on; version 7 -> 8 that fights in
# progress move to the fight tables (sleep and buffs as statuses) and go on; version 8 -> 9
# that monsters become content (edits as overrides, hand-made ones retired) and fights in
# progress keep their monster; version 9 -> 10 that chat messages get their author's
# account and recent players count as online; version 11 -> 12 that spells get their icons
# (tests/fixtures/schema_v11.sql and seed_v11.sql) and the game shows them; version 12 -> 13
# the lore columns; version 13 -> 14 (schema_v13.sql, seed_v13.sql) that Mages get +5 MP and
# Magic Bolt, Midworld sells the Wand, and the rest equals a fresh install; version 14 -> 15
# (schema_v14.sql, seed_v14.sql) that a fight in progress goes on, an encounter waiting for
# GET /fight is cancelled and a won fight waiting for GET /victory is paid (and version 16's
# items.rechargeable, version 17's user_hotbar, version 21's resistances and wards in place
# of monsters.immune, admins' overrides of it converted); version 21 -> 22 (schema_v21.sql,
# seed_v21.sql) that durations become ticks (statuses' and allies' turns, fights in
# progress, world statuses, admins' overrides), fights in progress start on the clock and
# go on, and what sat on the hotbar's key 9 (Guard's now) moves to a free key or off the
# bar; version 22 -> 24 (schema_v22.sql) the fields and the 3.2 wares; version 24 -> 25
# (schema_v24.sql) the interactables, the fields' wind, area actions and aims, a fight in
# progress going on; version 25 -> 26 the Explosive Barrel in three shops. Since version
# 14 every migrated Mage has 5 more MP: mig_users takes them off to compare with before.
# Sourced by tests/run.sh. Uses its own database and a second server; the main test
# database is only stamped with other versions for a moment.

# the content files of each kind (what a sync reports)
M_ST=$(ls "$ROOT/app/content/statuses" | wc -l); M_FI=$(ls "$ROOT/app/content/fields" | wc -l); M_IA=$(ls "$ROOT/app/content/interactables" | wc -l); M_SU=$(ls "$ROOT/app/content/summons" | wc -l); M_SP=$(ls "$ROOT/app/content/spells" | wc -l); M_IT=$(ls "$ROOT/app/content/items" | wc -l)

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
# (the fight columns moved to the fight tables in version 8: MIG_FIGHT_V7 / MIG_FIGHT_V8)
# Since version 14 Mages have 5 more MP (start_mp 5; checked on its own): mig_users takes
# them off (MIG_MAGE_MP) so a migrated database compares with its rows of before.
MIG_USERS_COMMON="id, username, password, email, verify, charname, regdate, onlinetime, authlevel, latitude,
	longitude, charclass, currentaction, currenthp, currentmp, currenttp, level, gold,
	experience, strength, dexterity, dropcode, towns"
MIG_MAGE_MP="(CASE WHEN charclass IN (SELECT id FROM classes WHERE key = 'mage') THEN 5 ELSE 0 END)"
mig_users() {
	local max="maxhp, maxmp, maxtp" common=$MIG_USERS_COMMON
	[ "$(mig_sql "$1" "SELECT count(*) FROM pragma_table_info('users') WHERE name = 'base_maxhp'")" = 1 ] \
		&& max="base_maxhp, base_maxmp, base_maxtp"
	if [ "$(mig_sql "$1" "SELECT count(*) FROM pragma_table_info('classes') WHERE name = 'start_spells'")" = 1 ]; then
		max="base_maxhp, base_maxmp - $MIG_MAGE_MP, base_maxtp"
		common=${common/currentmp,/currentmp - $MIG_MAGE_MP,}
	fi
	mig_sql "$1" "SELECT $common, $max FROM users ORDER BY id"
}
# mig_fight DB USER_ID MONSTER_ID HP [ROUND]: on a migrated database, the user is fighting
# the monster (like t_fight).
mig_fight() {
	mig_sql "$1" "DELETE FROM fight_statuses WHERE user_id = $2; DELETE FROM fight_combatants WHERE user_id = $2;
		DELETE FROM fights WHERE user_id = $2; UPDATE users SET currentaction = 'Fighting' WHERE id = $2;
		INSERT INTO fights (user_id, round) VALUES ($2, ${5:-2});
		INSERT INTO fight_combatants (user_id, id, side, kind) VALUES ($2, 1, 'player', 'player');
		INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, wave, hp, maxhp)
			SELECT $2, 2, 'enemy', 'monster', id, 1, $4, maxhp FROM monsters WHERE id = $3"
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
	replace(messages, char(10), '/'), replace(data, char(10), '/'), icon FROM spells"
MIG_SPELLS="$MIG_SPELLS_OF ORDER BY id"
# The content that has lore (schema version 13), "kind:key" sorted, and the lore itself.
MIG_LORE_KEYS="SELECT group_concat(k) FROM (SELECT k FROM (
	SELECT 'classes:' || key AS k FROM classes WHERE lore <> '' UNION ALL SELECT 'items:' || key FROM items WHERE lore <> ''
	UNION ALL SELECT 'monsters:' || key FROM monsters WHERE lore <> '' UNION ALL SELECT 'spells:' || key FROM spells WHERE lore <> ''
	UNION ALL SELECT 'statuses:' || key FROM statuses WHERE lore <> '' UNION ALL SELECT 'summons:' || key FROM summons WHERE lore <> '')
	ORDER BY k)"
MIG_LORE_TEXT="SELECT key, replace(lore, char(10), '/') FROM classes UNION ALL SELECT key, replace(lore, char(10), '/') FROM spells
	UNION ALL SELECT key, replace(lore, char(10), '/') FROM items UNION ALL SELECT key, replace(lore, char(10), '/') FROM monsters
	UNION ALL SELECT key, replace(lore, char(10), '/') FROM statuses UNION ALL SELECT key, replace(lore, char(10), '/') FROM summons
	ORDER BY 1, 2"
# The items and what towns sell (the same on a fresh install and a migrated database without edits).
MIG_ITEMS="SELECT * FROM items ORDER BY id; SELECT * FROM town_items ORDER BY town_id, item_key;
	SELECT * FROM town_maps ORDER BY town_id, map_id"
# The monsters and their loadouts as data (the same on a fresh install and a migrated
# database without edits).
MIG_MONSTERS="SELECT * FROM monsters ORDER BY id; SELECT * FROM monster_equipment ORDER BY monster_id, slot;
	SELECT * FROM monster_items ORDER BY monster_id, position; SELECT * FROM monster_spells ORDER BY monster_id, position"
# The same by key (ids of the monsters added after the original 151 depend on the
# database), but for red_slime, ghost and monster_152 (the version 8 database's edits).
MIG_MONSTERS_BY_KEY="SELECT key, name, description, maxhp, maxdam, armor, level, maxexp, maxgold, resist, ward, maxmp, uses_mp,
	attack_weight, roams, retired, attack_element, class FROM monsters WHERE key NOT IN ('red_slime', 'ghost', 'monster_152') ORDER BY key;
	SELECT m.key, e.slot, e.item_id FROM monster_equipment e JOIN monsters m ON m.id = e.monster_id ORDER BY 1, 2;
	SELECT m.key, i.position, i.item_id, i.weight, i.stock, i.has_when FROM monster_items i JOIN monsters m ON m.id = i.monster_id ORDER BY 1, 2;
	SELECT m.key, x.position, x.spell_id, x.weight, x.has_when FROM monster_spells x JOIN monsters m ON m.id = x.monster_id ORDER BY 1, 2"
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
# (the original spells, ids 1-19: the class files have taught others at more levels since)
MIG_LEVELS_V4="SELECT l.class_id, l.level, l.hp, l.mp, l.strength, l.dexterity,
	coalesce((SELECT group_concat(spell_id) FROM class_spells s WHERE s.class_id = l.class_id AND s.level = l.level AND s.spell_id <= 19), 0)
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
grep -qF "Content synced (statuses: $M_ST, 0 new, 0 retired; fields: $M_FI, 0 new, 0 retired; interactables: $M_IA, 0 new, 0 retired; summons: $M_SU, 0 new, 0 retired; spells: $M_SP, 0 new, 0 retired; classes: 3, 0 new, 0 retired; items: $M_IT, 0 new, 0 retired; monsters: 154, 0 new, 0 retired)." "$T/migrate.log" && t_ok || t_fail "content sync message: $(cat "$T/migrate.log")"
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
grep -qF 'Migrating to version 8: the fight engine' "$T/migrate.log" && t_ok || t_fail "step 8 not reported"
grep -qF 'Migrating to version 12: spells have icons' "$T/migrate.log" && t_ok || t_fail "step 12 not reported"
grep -qF 'Migrating to version 13: classes, spells, items, monsters, statuses and summons have lore' "$T/migrate.log" && t_ok || t_fail "step 13 not reported"
grep -qF 'Converted the stats of 3 characters to base stats (verified); 0 keep extra attack/defense power.' "$T/migrate.log" && t_ok || t_fail "stats conversion not reported"
grep -qF "Content synced (statuses: $M_ST, $((M_ST - 3)) new, 0 retired; fields: $M_FI, $M_FI new, 0 retired; interactables: $M_IA, $M_IA new, 0 retired; summons: $M_SU, $M_SU new, 0 retired; spells: $M_SP, $((M_SP - 25)) new, 0 retired; classes: 3, 0 new, 0 retired; items: $M_IT, $((M_IT - 71)) new, 0 retired; monsters: 154, 3 new, 0 retired)." "$T/migrate.log" && t_ok || t_fail "content not synced by migrate: $(grep "Content synced" "$T/migrate.log")"
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
MIG_SPELL_ICONS="SELECT group_concat(key || '=' || icon) FROM spells WHERE icon <> '' ORDER BY id"
mig_eq "$MIG_SPELL_ICONS" "$(mig_sql "$MIG/fresh.db" "$MIG_SPELL_ICONS")" "spell icons equal a fresh install's (v0)"
mig_eq "$MIG_LORE_KEYS" "$(mig_sql "$MIG/fresh.db" "$MIG_LORE_KEYS")" "lore (v0)"
mig_eq "$MIG_LORE_TEXT" "$(mig_sql "$MIG/fresh.db" "$MIG_LORE_TEXT")" "lore equals a fresh install's (v0)"
mig_eq "$MIG_ITEMS" "$(mig_sql "$MIG/fresh.db" "$MIG_ITEMS")" "items and shops equal a fresh install's"
mig_eq "SELECT count(*) FROM sqlite_sequence WHERE name IN ('items', 'drops')" "0" "items ids are plain rowids now"
mig_eq "SELECT count(*) FROM sqlite_sequence WHERE name = 'spells'" "0" "spells ids are plain rowids now"
mig_eq "$MIG_MONSTERS" "$(mig_sql "$MIG/fresh.db" "$MIG_MONSTERS")" "monsters and loadouts equal a fresh install's"
mig_eq "SELECT count(*) FROM sqlite_sequence WHERE name = 'monsters'" "0" "monster ids are plain rowids now"
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
t_get /;              expect_status 200; expect_body '">Old news &lt;b&gt;title&lt;/b&gt;</a></h2>'
expect_body '&middot; by Oldadmin</p>'; expect_body '>Read more</a>'; expect_body 'href="/forum/thread/6">Reply</a>'
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
	SELECT count(*) FROM monsters WHERE id <= 151; SELECT count(*) FROM forums"
before=$(mig_sql "$V1_DB" "$V1_DATA")
"$BIN" migrate --config "$MIG/v1.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v1) failed: $(cat "$T/migrate.log")"
grep -qF 'Migrating to version 2: remove difficulty levels' "$T/migrate.log" && t_ok || t_fail "step 2 not reported (v1)"
grep -qF 'Migrating to version 1:' "$T/migrate.log" && t_fail "step 1 ran on a version 1 database" || t_ok
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
	SELECT count(*) FROM monsters WHERE id <= 151"
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
grep -qF "Content synced (statuses: $M_ST, $((M_ST - 3)) new, 0 retired; fields: $M_FI, $M_FI new, 0 retired; interactables: $M_IA, $M_IA new, 0 retired; summons: $M_SU, $M_SU new, 0 retired; spells: $M_SP, $((M_SP - 25)) new, 0 retired; classes: 3, 0 new, 0 retired, 8 earlier admin edits kept as overrides; items: $M_IT, $((M_IT - 71)) new, 0 retired; monsters: 154, 3 new, 0 retired)." "$T/migrate.log" \
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
mig_eq "SELECT user_id || '|' || spell_id || '|' || learned_level FROM user_spells ORDER BY user_id, spell_id" "1|25|1
2|1|2" "known spells (v3): the Wizard (a Mage) knows Magic Bolt"
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
mig_fight "$V3_DB" 1 1 0 3
t_fight_win;       expect_status 200; expect_body 'You have gained a level!'
mig_eq "SELECT level || '|' || experience || '|' || base_maxhp || '|' || base_maxmp || '|' || base_maxtp || '|' || coalesce($T_KNOWN, '') FROM users WHERE id = 1" \
	"2|15|24|10|11|25" "level-up with the migrated gains (5 MP from the start, +5)"
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
grep -qF "Content synced (statuses: $M_ST, $((M_ST - 3)) new, 0 retired; fields: $M_FI, $M_FI new, 0 retired; interactables: $M_IA, $M_IA new, 0 retired; summons: $M_SU, $M_SU new, 0 retired; spells: $M_SP, $((M_SP - 19)) new, 1 retired, 4 earlier admin edits kept as overrides; classes: 3, 0 new, 0 retired, 1 earlier admin edits kept as overrides; items: $M_IT, $((M_IT - 71)) new, 0 retired; monsters: 154, 3 new, 0 retired)." \
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
mig_eq "$MIG_SPELLS_OF WHERE id <= 20 ORDER BY id" "$(mig_sql "$MIG/fresh.db" "$MIG_SPELLS_OF WHERE id <= 19 ORDER BY id" | sed 's/^1|heal|Heal|\([^|]*\)|5|both|0|10|/1|heal|Mend|\1|4|both|0|12|/; s/^11|sleep|Sleep|\([^|]*\)|10|fight|0|5|/11|sleep|Sleep|\1|10|fight|0|99|/')
20|spell_20|Fireball||9|fight|1|40|enemy|||" "spells (v4)"
mig_eq "SELECT group_concat(key) FROM (SELECT key FROM spells WHERE id > 20 ORDER BY id)" "$(mig_sql "$MIG/fresh.db" "SELECT group_concat(key) FROM (SELECT key FROM spells WHERE id > 19 ORDER BY key)")" "the 2.2 and 2.4 spells after the database's own (v4)"
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
1|$(mig_sql "$MIG_DB" "SELECT id FROM spells WHERE key = 'magic_bolt'")|1
2|1|-
2|7|-
4|2|-" "known spells (v4)"
[ "$(mig_users "$V4_DB")" = "$V4_USERS" ] && t_ok || t_fail "users otherwise changed (v4)"
"$BIN" content status --config "$MIG/v4.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk content status (v4)"
grep -qF "spells: $M_SP files, $((M_SP + 1)) in the database (1 retired), 4 overrides" "$T/migrate.log" && t_ok || t_fail "status (v4): $(cat "$T/migrate.log")"
grep -qF 'The database is in sync with the content files' "$T/migrate.log" && t_ok || t_fail "status in sync (v4): $(cat "$T/migrate.log")"
# the game on it: the overridden Heal, the retired Fireball (known, but without a file
# there is no code to cast it)
mig_serve "$MIG/v4.lua" "$MIG/v4server.log"
"$BIN" user --config "$MIG/v4.lua" passwd mag v4pass1 >/dev/null && t_ok || t_fail "dk user passwd (v4)"
t_jar migv4
t_login mag v4pass1; expect_redirect /
t_get /character;  expect_body 'Mend<br>'; expect_body 'Hurt<br>'; expect_body 'Fireball<br>'
t_get /;           expect_body 'action="/spell/1" data-tip data-tip-side="left">'
t_post /spell/1 "csrf=$(t_csrf)"; expect_body 'You have cast the Mend spell, and gained 12 Hit Points.'
mig_eq "SELECT currenthp || '|' || currentmp FROM users WHERE id = 1" "13|11" "heal with the migrated values (MP 10 + 5 - 4)"
mig_fight "$V4_DB" 1 2 100
mig_sql "$V4_DB" "UPDATE users SET currentmp = 9 WHERE id = 1"
t_get /fight;      expect_no_body 'title="Fireball ('; expect_body 'name="spell" value="6" title="Hurt ('
t_round "csrf=$(t_csrf)&spell=Spell&userspell=20"; expect_body 'This spell cannot be cast.'
mig_eq "SELECT currentmp || '|' || $T_MONSTER_HP FROM users WHERE id = 1" "9|100" "nothing spent"
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
	"Content synced (statuses: $M_ST, $((M_ST - 3)) new, 0 retired; fields: $M_FI, $M_FI new, 0 retired; interactables: $M_IA, $M_IA new, 0 retired; summons: $M_SU, $M_SU new, 0 retired; spells: $M_SP, $((M_SP - 25)) new, 0 retired; classes: 3, 0 new, 0 retired; items: $M_IT, $((M_IT - 69)) new, 2 retired, 11 earlier admin edits kept as overrides; monsters: 154, 3 new, 0 retired)." \
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
mig_eq "${V5_KEPT/currentmp,/currentmp - $MIG_MAGE_MP,}" "$V5_USERS" "users otherwise unchanged (v5)"
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
mig_eq "SELECT id || '|' || key || '|' || name || '|' || category || '|' || attack || '|' || modifiers || '|' || coalesce(drop_level, '-') || '|' || retired FROM items WHERE id IN (69, 70) ORDER BY id" \
	"69|item_34|Custom Blade|weapon|7|stat stat=strength amount=3|-|1
70|drop_33|Odd Gem|accessory|0|stat stat=maxtp amount=5|3|1" "admin-added items"
V5_EDITED="'stick', 'dark_axe', 'dark_sword', 'clothes', 'magic_sword', 'life_pebble', 'fortune_drop'"
mig_eq "SELECT * FROM items WHERE id <= 68 AND key NOT IN ($V5_EDITED) ORDER BY id" \
	"$(mig_sql "$MIG/fresh.db" "SELECT * FROM items WHERE id <= 68 AND key NOT IN ($V5_EDITED) ORDER BY id")" "unedited items equal a fresh install's"
mig_eq "SELECT name || '|' || price || '|' || modifiers FROM items WHERE key IN ('stick', 'clothes', 'magic_sword') ORDER BY id" \
	"Twig|12|
Magic Sword|10000|stat stat=maxmp amount=0
Clothes|50|stat stat=maxhp amount=20" "edited items"
mig_eq "SELECT group_concat(item_key, ' ') FROM (SELECT item_key FROM town_items WHERE town_id = 1 ORDER BY item_key)" \
	"antidote branch copper_ring herb item_34 stick trail_snack travel_tea wand" "Midworld's edited list (and the new Herbs, the Wand and the 3.1 wares)"
mig_eq "SELECT * FROM town_items WHERE town_id > 1 ORDER BY town_id, item_key" \
	"$(mig_sql "$MIG/fresh.db" "SELECT * FROM town_items WHERE town_id > 1 ORDER BY town_id, item_key")" "other shops equal a fresh install's"
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
# Mages (users 1, 4, 5, 7, 8) have 5 more MP since version 14
V5_BEFORE=$(printf '%s\n' "$V5_BEFORE" | awk 'BEGIN { split("1 4 5 7 8", m); for (i in m) mage[m[i]] = 1 }
	mage[NR] { match($0, /Max MP -?[0-9]+/); n = substr($0, RSTART + 7, RLENGTH - 7) + 5
		$0 = substr($0, 1, RSTART - 1) "Max MP " n substr($0, RSTART + RLENGTH) } { print }')
[ "${after%$'\n'}" = "$V5_BEFORE" ] && t_ok || {
	t_fail "effective stats changed by the migration:"
	diff <(printf '%s\n' "$V5_BEFORE") <(printf '%s' "$after") >&2
}
t_get /character;  expect_body 'Attack Power: 380<'; expect_body 'Defense Power: 370<'; expect_body 'Slot 2: Fortune Stone'
expect_body 'Experience: 0 <span class="light">(+10%)</span>'
expect_stats "100 55 40 130 70 380 370" "gearhead"
t_get /inventory;  expect_body 'Demon&#39;s Sin'
t_post /inventory/unequip/accessory1 "csrf=$(t_csrf)"; expect_body 'You took off the Demon&#39;s Sin.'
expect_stats "150 55 40 80 70 330 370" "without the Demon's Sin"
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
	(70, 'old_elixir', 'Elixir', 'consumable', 50, 5, 'heal_hp amount=9; heal_mp amount=2', 1, 1);
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
V6_KEPT="SELECT $MIG_USERS_COMMON, base_maxhp, base_maxmp, base_maxtp, base_attack, base_defense, base_exp_bonus,
	base_gold_bonus FROM users ORDER BY id; SELECT * FROM user_spells WHERE spell_id NOT IN (SELECT id FROM spells WHERE key = 'magic_bolt') ORDER BY user_id, spell_id;
	SELECT id, user_id, item_id, qty, equipped FROM user_items ORDER BY id"
V6_BEFORE=$(mig_sql "$V6_DB" "$V6_KEPT")
V6_SHOPS=$(mig_sql "$V6_DB" "SELECT t.town_id || '|' || i.key FROM town_items t JOIN items i ON i.id = t.item_id ORDER BY 1")
"$BIN" migrate --config "$MIG/v6.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v6) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version [123456]:' "$T/migrate.log" && t_fail "steps 1-6 ran on a version 6 database" || t_ok
for line in 'Migrating to version 7: spells and consumables are scripted content' \
	'warning: spell zap: the edit of effects.1.min (5) can'"'"'t be kept: spells and items are scripted now, with one power' \
	'warning: spell zap: the edit of effects.2.pct (25) can'"'"'t be kept' \
	"Content synced (statuses: $M_ST, $((M_ST - 3)) new, 0 retired; fields: $M_FI, $M_FI new, 0 retired; interactables: $M_IA, $M_IA new, 0 retired; summons: $M_SU, $M_SU new, 0 retired; spells: $M_SP, $((M_SP - 20)) new, 0 retired, 1 restored, 1 earlier admin edits kept as overrides; classes: 3, 0 new, 0 retired; items: $M_IT, $((M_IT - 69)) new, 0 retired; monsters: 154, 3 new, 0 retired)." \
	'Moved 1 fight in progress to the new fight tables.'; do
	grep -qF "$line" "$T/migrate.log" && t_ok || t_fail "migrate (v6) output lacks: $line
$(cat "$T/migrate.log")"
done
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v6 stamped"
[ "$(mig_layout "$V6_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v6 schema differs from a fresh install:"
	diff <(mig_layout "$V6_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v6)"
V6_KEPT14=${V6_KEPT/currentmp,/currentmp - $MIG_MAGE_MP,}
mig_eq "${V6_KEPT14/base_maxmp,/base_maxmp - $MIG_MAGE_MP,}" "$V6_BEFORE" "characters, their spells and items unchanged (v6)"
# every shop row kept, now by item key (schema 19; the Wand and the 3.1 wares added)
[ -z "$(comm -23 <(echo "$V6_SHOPS" | sort) <(mig_sql "$V6_DB" "SELECT town_id || '|' || item_key FROM town_items" | sort))" ] \
	&& t_ok || t_fail "shop rows lost (v6)"
mig_eq "SELECT currentmp || '|' || base_maxmp || '|' || $T_KNOWN FROM users" "35|35|1,6,20,21,$(mig_sql "$MIG_DB" "SELECT id FROM spells WHERE key = 'magic_bolt'")" "the Mage: +5 MP, Magic Bolt (v6)"
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
	"$(mig_sql "$MIG/fresh.db" "$MIG_SPELLS_OF WHERE key NOT IN ($V6_EDITED) AND id <= 19 ORDER BY id")" "unedited spells equal a fresh install's (v6)"
mig_eq "SELECT key || '|' || name || '|' || power || '|' || target FROM spells WHERE key IN ($V6_EDITED) ORDER BY id" \
	"hurt|Smite|20|enemy
sleep|Sleep|7|enemy
rage|Rage|30|self" "edited spells"
# the database-only rows keep their old amount as power, for display (they have no code)
mig_eq "$MIG_SPELLS_OF WHERE id = 20" "20|zap|Zap||3|fight|1|6|enemy|||" "retired spell (v6)"
# a database-only spell whose key a content file now has (mend) is restored from the file
mig_eq "SELECT retired || '|' || key || '|' || (description <> '') || '|' || (SELECT count(*) FROM spells WHERE key = 'mend') FROM spells WHERE id = 21" "0|mend|1|1" "a database-only spell with a new file's key is restored (v6)"
mig_eq "SELECT id || '|' || key || '|' || usable_in || '|' || target || '|' || power || '|' || retired FROM items WHERE id IN (69, 70) ORDER BY id" \
	"69|bomb|fight|enemy|12|1
70|old_elixir|both|self|9|1" "retired consumables (v6)"
mig_eq "SELECT * FROM items WHERE id <= 68 AND key NOT IN ('herb', 'stick') ORDER BY id" \
	"$(mig_sql "$MIG/fresh.db" "SELECT * FROM items WHERE id <= 68 AND key NOT IN ('herb', 'stick') ORDER BY id")" "unedited items equal a fresh install's (v6)"
# the character mid-fight goes on: the overridden Hurt, a Herb with its new power; the
# retired spell and consumables are known / kept but can't be used
mig_serve "$MIG/v6.lua" "$MIG/v6server.log"
"$BIN" user --config "$MIG/v6.lua" passwd caster v6pass1 >/dev/null && t_ok || t_fail "dk user passwd (v6)"
t_jar migv6
t_login caster v6pass1
t_get /fight;      expect_status 200; expect_body 'name="spell" value="6" title="Smite ('; expect_no_body 'title="Zap ('
expect_body 'name="item" value="66" title="Herb (x2)"'; expect_no_body 'title="Bomb ('; expect_no_body 'title="Elixir ('
V6_CS=$(t_csrf)
t_round "csrf=$V6_CS&spell=Spell&userspell=6"; expect_body 'You have cast the Smite spell for'
V6_HP=$(mig_sql "$V6_DB" "SELECT $T_MONSTER_HP FROM users WHERE id = 1")
[ "$V6_HP" -ge 30 ] && [ "$V6_HP" -le 34 ] && t_ok || t_fail "Smite (power 20: 16-20 damage) left the monster $V6_HP HP"
mig_eq "SELECT currentmp || '|' || $T_UBER_DEFENSE FROM users WHERE id = 1" "30|25" "MP spent (35 - 5), the fight's buff kept"
t_round "csrf=$V6_CS&spell=Spell&userspell=20"; expect_body 'This spell cannot be cast.'
mig_sql "$V6_DB" "UPDATE users SET currenthp = 1 WHERE id = 1"
t_round "csrf=$V6_CS&item=Use+Item&useritem=66"; expect_body 'You have used the Herb, and gained 39 Hit Points.'
t_round "csrf=$V6_CS&item=Use+Item&useritem=69"; expect_body 'This item cannot be used.'
t_get /help/spells; expect_body '>Smite<br>'; expect_no_body '>Zap<'
mig_unserve "$MIG/v6server.log"
"$BIN" migrate --config "$MIG/v6.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v6)"

t_section "migrate: version 7 database"
# version 7 schema + its game data, and characters in every state of a fight: mid-fight
# with the monster asleep and both buffs, an encounter that just began, a victory not yet
# collected, a fight whose monster was deleted, and one not fighting with leftover buff
# values; steps 8 and up run. The fights move to the fight tables and go on; step 15
# (pure GETs) pays the victory and cancels the encounter that had just begun and the one
# whose monster is gone (they were waiting for GET /fight to pick one).
V7_DB="$MIG/v7.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V7_DB\"#" "$CONFIG" > "$MIG/v7.lua"
mig_script "$V7_DB" "$ROOT/tests/fixtures/schema_v7.sql"
mig_script "$V7_DB" "$ROOT/tests/fixtures/seed_v7.sql"
cat > "$MIG/v7_data.sql" <<'SQL'
INSERT INTO monsters (id, name, maxhp, maxdam, armor, level, maxexp, maxgold, immune) VALUES (152, 'Gone Monster', 5, 1, 1, 1, 1, 1, 0);
INSERT INTO users (id, username, email, charname, verify, authlevel, charclass, level, currentaction, currentfight,
	currentmonster, currentmonsterhp, currentmonstersleep, currentmonsterimmune, currentuberdamage, currentuberdefense,
	currenthp, base_maxhp, currentmp, base_maxmp, strength, dexterity) VALUES
	(1, 'sleeper', 's@example.com', 'Sleeper', '1', 1, 1, 10, 'Fighting', 4, 5, 9, 13, 1, 25, 10, 200, 200, 30, 30, 1, 0),
	(2, 'starter', 't@example.com', 'Starter', '1', 0, 1, 1, 'Fighting', 1, 0, 0, 0, 0, 0, 0, 15, 15, 0, 0, 5, 5),
	(3, 'winner', 'w@example.com', 'Winner', '1', 0, 1, 1, 'Fighting', 3, 1, 0, 0, 0, 0, 0, 15, 15, 0, 0, 5, 5),
	(4, 'orphan', 'o@example.com', 'Orphan', '1', 0, 1, 1, 'Fighting', 2, 152, 3, 0, 0, 0, 0, 15, 15, 0, 0, 5, 5),
	(5, 'walker', 'k@example.com', 'Walker', '1', 0, 1, 1, 'Exploring', 0, 0, 0, 0, 0, 30, 0, 15, 15, 0, 0, 5, 5);
DELETE FROM monsters WHERE id = 152;
INSERT INTO user_spells (user_id, spell_id, learned_level) VALUES (1, 6, 4), (1, 1, 2);
PRAGMA user_version = 7;
SQL
mig_script "$V7_DB" "$MIG/v7_data.sql"
MIG_DB=$V7_DB
mig_eq "PRAGMA user_version" "7" "fixture is version 7"
V7_USERS=$(mig_users "$V7_DB")
"$BIN" migrate --config "$MIG/v7.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v7) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version [1-7]:' "$T/migrate.log" && t_fail "steps 1-7 ran on a version 7 database" || t_ok
for line in 'Migrating to version 8: the fight engine: fights in progress move to their own tables' \
	'Moved 4 fights in progress to the new fight tables.' \
	"Content synced (statuses: $M_ST, $((M_ST - 3)) new, 0 retired; fields: $M_FI, $M_FI new, 0 retired; interactables: $M_IA, $M_IA new, 0 retired; summons: $M_SU, $M_SU new, 0 retired; spells: $M_SP, $((M_SP - 25)) new, 0 retired; classes: 3, 0 new, 0 retired; items: $M_IT, $((M_IT - 71)) new, 0 retired; monsters: 154, 3 new, 0 retired)."; do
	grep -qF "$line" "$T/migrate.log" && t_ok || t_fail "migrate (v7) output lacks: $line
$(cat "$T/migrate.log")"
done
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v7 stamped"
[ "$(mig_layout "$V7_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v7 schema differs from a fresh install:"
	diff <(mig_layout "$V7_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v7)"
mig_eq "SELECT count(*) FROM pragma_table_info('users') WHERE name LIKE 'currentmonster%' OR name LIKE 'currentuber%' OR name = 'currentfight'" \
	"0" "the fight columns are gone"
[ "$(mig_users "$V7_DB" | sed -n '1p;5p')" = "$(echo "$V7_USERS" | sed -n '1p;5p')" ] && t_ok || t_fail "users otherwise changed (v7)"
mig_eq "SELECT group_concat(currentaction, ',') FROM (SELECT currentaction FROM users ORDER BY id)" \
	"Fighting,Exploring,Exploring,Exploring,Exploring" "the victory paid, the encounters without a monster cancelled"
mig_eq "SELECT (experience > 0) || '|' || (gold > 0) FROM users WHERE id = 3" "1|1" "the winner paid"
mig_eq "$MIG_SPELLS" "$(mig_sql "$MIG/fresh.db" "$MIG_SPELLS")" "spells equal a fresh install's (v7)"
mig_eq "$MIG_ITEMS" "$(mig_sql "$MIG/fresh.db" "$MIG_ITEMS")" "items equal a fresh install's (v7)"
mig_eq "SELECT * FROM statuses ORDER BY id; SELECT * FROM summons ORDER BY id" \
	"$(mig_sql "$MIG/fresh.db" "SELECT * FROM statuses ORDER BY id; SELECT * FROM summons ORDER BY id")" "statuses and summons equal a fresh install's"
mig_eq "SELECT user_id || '|' || round || '|' || wave || '|' || outcome FROM fights ORDER BY user_id" "1|4|1|
3|3|1|victory" "fights (round = the old counter; the won one kept for its page)"
mig_eq "SELECT user_id || '|' || id || '|' || side || '|' || kind || '|' || coalesce(entity_id, '-') || '|' || coalesce(hp, '-') || '|' || coalesce(maxhp, '-') || '|' || data FROM fight_combatants ORDER BY user_id, id" \
	"1|1|player|player|-|-|-|
1|2|enemy|monster|5|9|10|immune=i:1
3|1|player|player|-|-|-|
3|2|enemy|monster|1|0|4|immune=i:0" "combatants (a deleted monster is left out)"
mig_eq "SELECT $T_STATUSES || '|' || $T_SLEEP || '|' || $T_UBER_DAMAGE || '|' || $T_UBER_DEFENSE FROM users WHERE id = 1" \
	"player:uber_damage,player:uber_defense,enemy:sleep|13|25|10" "sleep and buffs as statuses"
mig_eq "SELECT count(*) FROM fight_statuses WHERE user_id <> 1; SELECT count(*) FROM user_statuses" "0
0" "no other statuses (a walker's leftover buff value is not a fight)"
# the game on it: the sleeper's fight goes on (same monster, HP, sleep, buffs); the
# victory shows; the cancelled encounters are gone
mig_serve "$MIG/v7.lua" "$MIG/v7server.log"
for u in sleeper winner starter orphan; do
	"$BIN" user --config "$MIG/v7.lua" passwd "$u" v7pass1 >/dev/null && t_ok || t_fail "dk user passwd (v7 $u)"
done
t_jar migv7
t_login sleeper v7pass1; expect_redirect /
t_get /;           expect_redirect /fight
t_get /fight;      expect_status 200; expect_body 'You are fighting a <b class="tip-term" data-tip tabindex="0">Shadow<template class="tip">'; expect_body "Monster's HP: 9"
expect_body '<b>Shadow</b> <span class="fight-statuses">&mdash; <img class="fight-status-icon" src="/static/images/statuses/sleep.png" width="16" height="16" alt="">Asleep</span>'
expect_body '<b>You</b> <span class="fight-statuses">&mdash; <img class="fight-status-icon" src="/static/images/statuses/uber_damage.png" width="16" height="16" alt="">Damage Up, <img class="fight-status-icon" src="/static/images/statuses/uber_defense.png" width="16" height="16" alt="">Defense Up</span>'
mig_eq "SELECT $T_ROUND FROM users WHERE id = 1" "4" "the counter is kept"
V7_CS=$(t_csrf)
t_round "csrf=$V7_CS&spell=Spell&userspell=1"; expect_body 'Your Hit Points are already full.'
mig_sql "$V7_DB" "UPDATE users SET currenthp = 100 WHERE id = 1"
t_round "csrf=$V7_CS&spell=Spell&userspell=1"; expect_body 'You have cast the Heal spell, and gained 10 Hit Points.'
# (3.2: asleep, its turn is skipped; it rolls to wake on the clock's ticks)
expect_body 'The Shadow is still asleep.'; mig_eq "SELECT $T_SLEEP FROM users WHERE id = 1" "13" "still asleep"
mig_eq "SELECT currentmp || '|' || $T_UBER_DAMAGE || '|' || $T_UBER_DEFENSE FROM users WHERE id = 1" "30|25|10" "MP spent (35 - 5), buffs kept"
t_jar migv7w
t_login winner v7pass1
t_get /victory;    expect_status 200; expect_body 'You have defeated the Blue Slime.'
mig_eq "SELECT currentaction || '|' || $T_ROUND || '|' || (experience > 0) FROM users WHERE id = 3" "Exploring|0|1" "the victory paid out"
for u in starter orphan; do
	t_jar "migv7$u"
	t_login "$u" v7pass1; expect_redirect /
	t_get /;           expect_status 200; expect_body 'Exploring'
	t_get /fight;      expect_body 'Cheat attempt detected.'
done
mig_unserve "$MIG/v7server.log"
"$BIN" migrate --config "$MIG/v7.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v7)"

t_section "migrate: version 8 database"
# version 8 schema + its game data: admin edits of original monsters (the Red Slime's stats,
# the Ghost's immunity), a monster added by hand (no content file), a fight in progress
# against an original monster (asleep) and one against the added monster; steps 9 on run.
# Monsters become content: the edits are overrides (of the immunity, only what the admin
# changed: step 21), the added monster is retired (its fight goes on), monster MP starts
# full, and the unedited originals have their files' affinities.
V8_DB="$MIG/v8.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V8_DB\"#" "$CONFIG" > "$MIG/v8.lua"
mig_script "$V8_DB" "$ROOT/tests/fixtures/schema_v8.sql"
mig_script "$V8_DB" "$ROOT/tests/fixtures/seed_v8.sql"
cat > "$MIG/v8_data.sql" <<'SQL'
UPDATE monsters SET name = 'Big Slime', maxhp = 7 WHERE id = 2;
UPDATE monsters SET immune = 1 WHERE id = 17;
INSERT INTO monsters (id, name, maxhp, maxdam, armor, level, maxexp, maxgold, immune) VALUES (152, 'Homebrew', 30, 5, 2, 3, 9, 9, 0);
INSERT INTO users (id, username, email, charname, verify, authlevel, charclass, level, currentaction,
	currenthp, base_maxhp, currentmp, base_maxmp, strength, dexterity) VALUES
	(1, 'fighter', 'f@example.com', 'Fighter', '1', 1, 1, 10, 'Fighting', 200, 200, 30, 30, 1, 0),
	(2, 'brewer', 'b@example.com', 'Brewer', '1', 0, 1, 3, 'Fighting', 100, 100, 0, 0, 1, 0),
	(3, 'idler', 'i@example.com', 'Idler', '1', 0, 1, 1, 'Exploring', 15, 15, 0, 0, 5, 5);
INSERT INTO fights (user_id, round, wave, data) VALUES (1, 4, 1, ''), (2, 3, 1, '');
INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, wave, hp, maxhp, data) VALUES
	(1, 1, 'player', 'player', NULL, 0, NULL, NULL, ''), (1, 2, 'enemy', 'monster', 5, 1, 9, 10, 'immune=i:1'),
	(2, 1, 'player', 'player', NULL, 0, NULL, NULL, ''), (2, 2, 'enemy', 'monster', 152, 1, 20, 30, 'immune=i:0');
INSERT INTO fight_statuses (user_id, combatant_id, status_id, position, data, applied_round) VALUES (1, 2, 1, 1, 'chance=i:13', 4);
PRAGMA user_version = 8;
SQL
mig_script "$V8_DB" "$MIG/v8_data.sql"
MIG_DB=$V8_DB
mig_eq "PRAGMA user_version" "8" "fixture is version 8"
V8_USERS=$(mig_users "$V8_DB")
"$BIN" migrate --config "$MIG/v8.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v8) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version [1-8]:' "$T/migrate.log" && t_fail "steps 1-8 ran on a version 8 database" || t_ok
for line in 'Migrating to version 9: monsters are content files with MP, equipment, items and spells' \
	'warning: monster 152 Homebrew (monster_152) has no content file and is retired (fights against it go on; it is no longer met). Write app/content/monsters/monster_152.lua to bring it back.' \
	"Content synced (statuses: $M_ST, $((M_ST - 3)) new, 0 retired; fields: $M_FI, $M_FI new, 0 retired; interactables: $M_IA, $M_IA new, 0 retired; summons: $M_SU, $M_SU new, 0 retired; spells: $M_SP, $((M_SP - 25)) new, 0 retired; classes: 3, 0 new, 0 retired; items: $M_IT, $((M_IT - 71)) new, 0 retired; monsters: 154, 3 new, 1 retired, 3 earlier admin edits kept as overrides)."; do
	grep -qF "$line" "$T/migrate.log" && t_ok || t_fail "migrate (v8) output lacks: $line
$(cat "$T/migrate.log")"
done
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v8 stamped"
[ "$(mig_layout "$V8_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v8 schema differs from a fresh install:"
	diff <(mig_layout "$V8_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v8)"
[ "$(mig_users "$V8_DB")" = "$V8_USERS" ] && t_ok || t_fail "users changed (v8)"
mig_eq "SELECT kind || '|' || key || '|' || field || '|' || value FROM content_overrides ORDER BY key, field" \
	"monsters|ghost|resist.arcane|100
monsters|red_slime|maxhp|7
monsters|red_slime|name|Big Slime" "the edits kept as overrides (the Ghost's immunity 1: arcane, its sleep ward untouched)"
mig_eq "SELECT id || '|' || key || '|' || name || '|' || maxhp || '|' || level || '|' || maxmp || '|' || retired FROM monsters WHERE id IN (2, 152) ORDER BY id" \
	"2|red_slime|Big Slime|7|1|5|0
152|monster_152|Homebrew|30|3|9|1" "an edited and a hand-made monster"
mig_eq "SELECT group_concat(key || '=' || id, ',') FROM (SELECT key, id FROM monsters WHERE id > 152 ORDER BY id)" \
	"bandit_captain=153,bog_witch=154,goblin_shaman=155" "the example monsters after the existing ids"
mig_eq "SELECT * FROM monsters WHERE id <= 151 AND id NOT IN (2, 17) ORDER BY id" \
	"$(mig_sql "$MIG/fresh.db" "SELECT * FROM monsters WHERE id <= 151 AND id NOT IN (2, 17) ORDER BY id")" "the original monsters equal a fresh install's"
# their immunity unedited, the originals have their files' affinities (21): the Red Slime's
# (immune 0), the Silver Slime's (2: its file has more) and the Titan's (0: its file wards
# off sleep at 50); the Ghost's file's but for arcane
V8_AFF="SELECT key || '|' || resist || '|' || ward FROM monsters WHERE key IN ('red_slime', 'silver_slime', 'titan') ORDER BY key"
mig_eq "$V8_AFF" "$(mig_sql "$MIG/fresh.db" "$V8_AFF")" "unedited immunity: the files' affinities, no override (21)"
mig_eq "SELECT ward FROM monsters WHERE key = 'ghost'" "$(mig_sql "$MIG/fresh.db" "SELECT ward FROM monsters WHERE key = 'ghost'")" \
	"the Ghost's sleep ward is its file's (21)"
mig_eq "SELECT ',' || resist || ',' LIKE '%,arcane=100,%' FROM monsters WHERE key = 'ghost'" "1" "the Ghost's edit: immune to arcane (21)"
mig_eq "$MIG_MONSTERS_BY_KEY" "$(mig_sql "$MIG/fresh.db" "$MIG_MONSTERS_BY_KEY")" \
	"the other monsters and the loadouts equal a fresh install's (by key)"
mig_eq "SELECT user_id || '|' || id || '|' || coalesce(entity_id, '-') || '|' || coalesce(hp, '-') || '|' || coalesce(mp, '-') || '|' || coalesce(maxmp, '-') FROM fight_combatants ORDER BY user_id, id" \
	"1|1|-|-|-|-
1|2|5|9|-|-
2|1|-|-|-|-
2|2|152|20|-|-" "fights keep their monster (MP: full when loaded)"
# the game on it: both fights go on (an original monster asleep, the retired hand-made one)
mig_serve "$MIG/v8.lua" "$MIG/v8server.log"
for u in fighter brewer; do
	"$BIN" user --config "$MIG/v8.lua" passwd "$u" v8pass1 >/dev/null && t_ok || t_fail "dk user passwd (v8 $u)"
done
t_jar migv8
t_login fighter v8pass1; expect_redirect /
t_get /fight;      expect_status 200; expect_body 'You are fighting a <b class="tip-term" data-tip tabindex="0">Shadow<template class="tip">'; expect_body "Monster's HP: 9"
expect_body '<b>Shadow</b> <span class="fight-statuses">&mdash; <img class="fight-status-icon" src="/static/images/statuses/sleep.png" width="16" height="16" alt="">Asleep</span>'; expect_no_body "Monster's MP"
mig_eq "SELECT round FROM fights WHERE user_id = 1" "4" "the counter is kept"
t_round "csrf=$(t_csrf)&fight=Fight"; expect_status 200
mig_eq "SELECT mp || '|' || maxmp FROM fight_combatants WHERE user_id = 1 AND id = 2" "5|5" "the Shadow's MP is full"
t_jar migv8b
t_login brewer v8pass1
t_get /fight;      expect_status 200; expect_body 'You are fighting a <b class="tip-term" data-tip tabindex="0">Homebrew<template class="tip">'; expect_body "Monster's HP: 20"
V8_CS=$(t_csrf)
t_round "csrf=$V8_CS&fight=Fight"; expect_status 200; expect_body 'You attack the monster for'
mig_eq "SELECT entity_id FROM fight_combatants WHERE user_id = 2 AND id = 2" "152" "the retired monster's fight goes on"
t_get /help/monsters; expect_body '>Big Slime</td>'; expect_no_body 'Homebrew'
mig_unserve "$MIG/v8server.log"
"$BIN" migrate --config "$MIG/v8.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v8)"

t_section "migrate: version 9 database"
# version 9 schema + its game data, chat messages (by a player, by a name in another case,
# by a deleted player) and a player seen a minute ago; only step 10 runs: messages get
# their author's account, recent players count as online, no banner.
V9_DB="$MIG/v9.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V9_DB\"#" "$CONFIG" > "$MIG/v9.lua"
mig_script "$V9_DB" "$ROOT/tests/fixtures/schema_v9.sql"
mig_script "$V9_DB" "$ROOT/tests/fixtures/seed_v9.sql"
cat > "$MIG/v9_data.sql" <<SQL
INSERT INTO users (id, username, email, charname, verify, onlinetime) VALUES
	(1, 'chatter', 'c@example.com', 'Chatter', '1', strftime('%s', 'now') - 60),
	(2, 'idler', 'i@example.com', 'Idler', '1', 100);
INSERT INTO babble (id, posttime, author, babble) VALUES
	(1, 100, 'Chatter', 'hello <there>'), (2, 200, 'chatter', 'lower case'), (3, 300, 'Gone', 'by a deleted player');
PRAGMA user_version = 9;
SQL
mig_script "$V9_DB" "$MIG/v9_data.sql"
MIG_DB=$V9_DB
mig_eq "PRAGMA user_version" "9" "fixture is version 9"
V9_USERS=$(mig_users "$V9_DB")
"$BIN" migrate --config "$MIG/v9.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v9) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version [1-9]:' "$T/migrate.log" && t_fail "steps 1-9 ran on a version 9 database" || t_ok
grep -qF 'Migrating to version 10: realtime: chat messages keep their author' "$T/migrate.log" && t_ok || t_fail "step 10 not reported: $(cat "$T/migrate.log")"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v9 stamped"
[ "$(mig_layout "$V9_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v9 schema differs from a fresh install:"
	diff <(mig_layout "$V9_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v9)"
[ "$(mig_users "$V9_DB")" = "$V9_USERS" ] && t_ok || t_fail "users changed (v9)"
mig_eq "SELECT id || '|' || coalesce(author_id, '-') FROM babble ORDER BY id" "1|1
2|1
3|-" "messages get their author's account"
mig_eq "SELECT username || '|' || online FROM users ORDER BY id" "chatter|1
idler|0" "recent players are online"
mig_eq "SELECT banner || '|' || banner_id || '|' || banner_expires FROM control" "|0|0" "no banner"
mig_serve "$MIG/v9.lua" "$MIG/v9server.log"
"$BIN" user --config "$MIG/v9.lua" passwd chatter v9pass1 >/dev/null && t_ok || t_fail "dk user passwd (v9)"
t_jar migv9; t_reset_jar
t_login chatter v9pass1; expect_redirect /
t_get /babble;     expect_status 200; expect_body '<b class="babble-author">Chatter</b><span class="babble-text">hello &lt;there&gt;</span></li>'
expect_body '>Chatter</a>'; expect_no_body '>Idler</a>'
t_fetch /babble "babble=after+the+migration"; expect_status 200
mig_eq "SELECT author_id FROM babble WHERE babble = 'after the migration'" "1" "a new message after the migration"
mig_unserve "$MIG/v9server.log"
"$BIN" migrate --config "$MIG/v9.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v9)"

t_section "migrate: version 11 database"
# version 11 schema + its game data (content synced as at version 11: no icon column) and
# a player who knows Heal and Hurt; only step 12 runs: spells.icon, filled in by the sync
V11_DB="$MIG/v11.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V11_DB\"#" "$CONFIG" > "$MIG/v11.lua"
mig_script "$V11_DB" "$ROOT/tests/fixtures/schema_v11.sql"
mig_script "$V11_DB" "$ROOT/tests/fixtures/seed_v11.sql"
cat > "$MIG/v11_data.sql" <<SQL
INSERT INTO users (id, username, email, charname, verify, currentaction, currenthp, base_maxhp, currentmp, base_maxmp) VALUES
	(1, 'caster', 'c@example.com', 'Caster', '1', 'In Town', 5, 30, 7, 20);
INSERT INTO user_spells (user_id, spell_id, learned_level) VALUES (1, 1, 1), (1, 2, 1), (1, 6, 1);
PRAGMA user_version = 11;
SQL
mig_script "$V11_DB" "$MIG/v11_data.sql"
MIG_DB=$V11_DB
mig_eq "PRAGMA user_version" "11" "fixture is version 11"
mig_eq "SELECT count(*) FROM pragma_table_info('spells') WHERE name = 'icon'" "0" "no icon column at version 11"
V11_USERS=$(mig_users "$V11_DB")
"$BIN" migrate --config "$MIG/v11.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v11) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version ([1-9]|1[01]):' "$T/migrate.log" && t_fail "steps 1-11 ran on a version 11 database" || t_ok
grep -qF 'Migrating to version 12: spells have icons (the fight and Fast Spells buttons)' "$T/migrate.log" && t_ok || t_fail "step 12 not reported: $(cat "$T/migrate.log")"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v11 stamped"
[ "$(mig_layout "$V11_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v11 schema differs from a fresh install:"
	diff <(mig_layout "$V11_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v11)"
[ "$(mig_users "$V11_DB")" = "$V11_USERS" ] && t_ok || t_fail "users changed (v11)"
mig_eq "$MIG_SPELLS" "$(mig_sql "$MIG/fresh.db" "$MIG_SPELLS")" "spells equal a fresh install's (v11)"
MIG_SPELL_ICONS="SELECT group_concat(key || '=' || icon) FROM spells WHERE icon <> '' ORDER BY id"
mig_eq "$MIG_SPELL_ICONS" "$(mig_sql "$MIG/fresh.db" "$MIG_SPELL_ICONS")" "spell icons equal a fresh install's (v11)"
mig_eq "SELECT value FROM meta WHERE key = 'content_fingerprint'" \
	"$(mig_sql "$MIG/fresh.db" "SELECT value FROM meta WHERE key = 'content_fingerprint'")" "content fingerprint (v11)"
mig_serve "$MIG/v11.lua" "$MIG/v11server.log"
"$BIN" user --config "$MIG/v11.lua" passwd caster v11pass1 >/dev/null && t_ok || t_fail "dk user passwd (v11)"
t_jar migv11; t_reset_jar
t_login caster v11pass1; expect_redirect /
t_get /; expect_status 200
expect_body 'action="/spell/1" data-tip data-tip-side="left"><input type="hidden" name="csrf" value="'
expect_body 'title="Heal (5 MP)" aria-label="Heal (5 MP)"><img src="/static/images/skills/heal.png" width="34" height="34"'
expect_body 'title="Revive (10 MP)" aria-label="Revive (10 MP)" disabled><img src="/static/images/skills/revive.png"'
t_post /spell/1 "csrf=$(t_csrf)"; expect_body 'You have cast the Heal spell, and gained 10 Hit Points.'
mig_eq "SELECT currenthp || '|' || currentmp FROM users WHERE id = 1" "15|2" "a Fast Spell after the migration"
mig_unserve "$MIG/v11server.log"
"$BIN" migrate --config "$MIG/v11.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v11)"

t_section "migrate: version 12 database"
# version 12 schema + its game data (content synced as at version 12: no lore columns), a
# player in a fight against the Blue Slime who knows Heal and Hurt, and an admin override of
# Heal's name from that time; only step 13 runs: the lore columns, filled in by the sync
V12_DB="$MIG/v12.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V12_DB\"#" "$CONFIG" > "$MIG/v12.lua"
mig_script "$V12_DB" "$ROOT/tests/fixtures/schema_v12.sql"
mig_script "$V12_DB" "$ROOT/tests/fixtures/seed_v12.sql"
cat > "$MIG/v12_data.sql" <<SQL
INSERT INTO users (id, username, email, charname, verify, currentaction, currenthp, base_maxhp, currentmp, base_maxmp) VALUES
	(1, 'loreman', 'l@example.com', 'Loreman', '1', 'Fighting', 9, 30, 12, 20);
INSERT INTO user_spells (user_id, spell_id, learned_level) VALUES (1, 1, 1), (1, 6, 1);
INSERT INTO fights (user_id, round, wave, data) VALUES (1, 3, 1, '');
INSERT INTO fight_combatants (user_id, id, side, kind) VALUES (1, 1, 'player', 'player');
INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, wave, hp, maxhp, mp, maxmp, data)
	VALUES (1, 2, 'enemy', 'monster', 1, 1, 3, 4, 5, 5, 'immune=i:0');
INSERT INTO content_overrides (kind, key, field, value) VALUES ('spells', 'heal', 'name', 'Mend');
PRAGMA user_version = 12;
SQL
mig_script "$V12_DB" "$MIG/v12_data.sql"
MIG_DB=$V12_DB
mig_eq "PRAGMA user_version" "12" "fixture is version 12"
mig_eq "SELECT count(*) FROM pragma_table_info('spells') WHERE name = 'lore'" "0" "no lore column at version 12"
V12_USERS=$(mig_users "$V12_DB")
V12_FIGHT=$(mig_sql "$V12_DB" "SELECT user_id, round, wave, data FROM fights; SELECT * FROM fight_combatants ORDER BY id")
"$BIN" migrate --config "$MIG/v12.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v12) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version ([1-9]|1[012]):' "$T/migrate.log" && t_fail "steps 1-12 ran on a version 12 database" || t_ok
grep -qF 'Migrating to version 13: classes, spells, items, monsters, statuses and summons have lore' "$T/migrate.log" && t_ok || t_fail "step 13 not reported: $(cat "$T/migrate.log")"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v12 stamped"
[ "$(mig_layout "$V12_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v12 schema differs from a fresh install:"
	diff <(mig_layout "$V12_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
for tbl in classes items monsters spells statuses summons; do
	mig_layout "$V12_DB" | grep -qE "^$tbl\|[0-9]+\|lore\|TEXT\|1\|''\|0$" && t_ok || t_fail "no $tbl.lore column (v12)"
done
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v12)"
[ "$(mig_users "$V12_DB")" = "$V12_USERS" ] && t_ok || t_fail "users changed (v12)"
# (the columns of version 12's fight_combatants: turns_left is ticks_left since version 22)
[ "$(mig_sql "$V12_DB" "SELECT user_id, round, wave, data FROM fights; SELECT user_id, id, side, kind, entity_id, wave, hp,
	maxhp, ticks_left, data, mp, maxmp FROM fight_combatants ORDER BY id")" = "$V12_FIGHT" ] && t_ok || t_fail "the fight changed (v12)"
mig_eq "$MIG_LORE_KEYS" "$(mig_sql "$MIG/fresh.db" "$MIG_LORE_KEYS")" "lore (v12)"
mig_eq "$MIG_LORE_TEXT" "$(mig_sql "$MIG/fresh.db" "$MIG_LORE_TEXT")" "lore equals a fresh install's (v12)"
mig_eq "SELECT name FROM spells WHERE id = 1" "Mend" "the v12 override survives"
mig_eq "$MIG_CLASSES" "$(mig_sql "$MIG/fresh.db" "$MIG_CLASSES")" "classes equal a fresh install's (v12)"
mig_eq "$MIG_ITEMS" "$(mig_sql "$MIG/fresh.db" "$MIG_ITEMS")" "items equal a fresh install's (v12)"
mig_eq "$MIG_MONSTERS" "$(mig_sql "$MIG/fresh.db" "$MIG_MONSTERS")" "monsters equal a fresh install's (v12)"
mig_eq "SELECT value FROM meta WHERE key = 'content_fingerprint'" \
	"$(mig_sql "$MIG/fresh.db" "SELECT value FROM meta WHERE key = 'content_fingerprint'")" "content fingerprint (v12)"
mig_serve "$MIG/v12.lua" "$MIG/v12server.log"
"$BIN" user --config "$MIG/v12.lua" passwd loreman v12pass1 >/dev/null && t_ok || t_fail "dk user passwd (v12)"
t_jar migv12; t_reset_jar
t_login loreman v12pass1; expect_redirect /
t_get /fight; expect_status 200
expect_body '>Blue Slime<template class="tip"><div class="tip-title"><img class="tip-icon" src="/static/images/monsters/blue_slime.png" width="20" height="20" alt="">Blue Slime</div><div class="tip-meta">Level 1</div>'
expect_body '</ul><div class="tip-lore"><p>The humblest monster of the land'
expect_body 'aria-label="Mend (5 MP)"><img src="/static/images/skills/heal.png"'
expect_body '<template class="tip"><div class="tip-title">Mend</div><div class="tip-meta">5 MP · In fights and in town</div>'
expect_body "Monster's HP: 3"
t_round "csrf=$(t_csrf)&round=$(mig_sql "$V12_DB" "SELECT round FROM fights")&spell=1"
expect_body 'You have cast the Mend spell, and gained 10 Hit Points.'
mig_unserve "$MIG/v12server.log"
"$BIN" migrate --config "$MIG/v12.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v12)"

t_section "migrate: version 13 database"
# version 13 schema + its game data (no starting spells, charges or item icons; the Mage
# started with 0 MP), Mages at several MP (one at full MP with a Magic Pebble: +10 max
# MP), a Warrior and a Paladin, and a Mage mid-fight; only step 14 runs. Every Mage gets
# +5 base and current MP (not above the maximum) and learns Magic Bolt at level 1; the
# others don't change; Midworld sells the Wand; the rest equals a fresh install.
V13_DB="$MIG/v13.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V13_DB\"#" "$CONFIG" > "$MIG/v13.lua"
mig_script "$V13_DB" "$ROOT/tests/fixtures/schema_v13.sql"
mig_script "$V13_DB" "$ROOT/tests/fixtures/seed_v13.sql"
cat > "$MIG/v13_data.sql" <<SQL
INSERT INTO users (id, username, email, charname, verify, charclass, level, currentaction, currenthp, base_maxhp,
	currentmp, base_maxmp) VALUES
	(1, 'oldmage', 'm@example.com', 'Oldmage', '1', 1, 5, 'Fighting', 30, 30, 10, 17),
	(2, 'fullmage', 'f@example.com', 'Fullmage', '1', 1, 1, 'In Town', 15, 15, 10, 0),
	(3, 'oldwar', 'w@example.com', 'Oldwar', '1', 2, 3, 'In Town', 20, 20, 0, 0),
	(4, 'oldpal', 'p@example.com', 'Oldpal', '1', 3, 2, 'In Town', 17, 17, 0, 0);
INSERT INTO user_spells (user_id, spell_id, learned_level) VALUES (1, 1, 2), (1, 6, 4), (4, 1, 2);
INSERT INTO user_items (user_id, item_id, qty, equipped) VALUES (2, 37, 1, 'accessory1'), (2, 66, 3, NULL);
INSERT INTO fights (user_id, round, wave, data) VALUES (1, 3, 1, '');
INSERT INTO fight_combatants (user_id, id, side, kind) VALUES (1, 1, 'player', 'player');
INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, wave, hp, maxhp, mp, maxmp, data)
	VALUES (1, 2, 'enemy', 'monster', 2, 1, 40, 50, 5, 5, 'immune=i:0');
PRAGMA user_version = 13;
SQL
mig_script "$V13_DB" "$MIG/v13_data.sql"
MIG_DB=$V13_DB
mig_eq "PRAGMA user_version" "13" "fixture is version 13"
mig_eq "SELECT key FROM items WHERE id = 37" "magic_pebble" "fixture: item 37"
mig_eq "SELECT count(*) FROM pragma_table_info('user_items') WHERE name = 'charges'" "0" "no charges column at version 13"
V13_USERS=$(mig_users "$V13_DB")
"$BIN" migrate --config "$MIG/v13.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v13) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version ([1-9]|1[0-3]):' "$T/migrate.log" && t_fail "steps 1-13 ran on a version 13 database" || t_ok
grep -qF 'Migrating to version 14: starting spells, items that cast spells with charges, item icons; Mages start with 5 MP' "$T/migrate.log" \
	&& t_ok || t_fail "step 14 not reported: $(cat "$T/migrate.log")"
grep -qF "Content synced (statuses: $M_ST, $((M_ST - 3)) new, 0 retired; fields: $M_FI, $M_FI new, 0 retired; interactables: $M_IA, $M_IA new, 0 retired; summons: $M_SU, $M_SU new, 0 retired; spells: $M_SP, $((M_SP - 25)) new, 0 retired; classes: 3, 0 new, 0 retired; items: $M_IT, $((M_IT - 71)) new, 0 retired; monsters: 154, 3 new, 0 retired)." "$T/migrate.log" \
	&& t_ok || t_fail "sync report (v13): $(cat "$T/migrate.log")"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v13 stamped"
[ "$(mig_layout "$V13_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v13 schema differs from a fresh install:"
	diff <(mig_layout "$V13_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v13)"
[ "$(mig_users "$V13_DB")" = "$V13_USERS" ] && t_ok || t_fail "users otherwise changed (v13)"
# Mages: +5 base and current MP (the full one stays full: 15 + 5 of 25 with the Pebble)
mig_eq "SELECT id || '|' || currentmp || '|' || base_maxmp || '|' || coalesce($T_KNOWN, '') FROM users ORDER BY id" \
	"1|15|22|1,6,25
2|15|5|25
3|0|0|
4|0|0|1" "Mages: +5 MP and Magic Bolt"
mig_eq "SELECT group_concat(user_id || ':' || learned_level) FROM user_spells WHERE spell_id = 25" "1:1,2:1" "learned at level 1"
mig_eq "SELECT id || '|' || item_id || '|' || charges FROM user_items ORDER BY id" "1|37|0
2|66|0" "items without charges"
mig_eq "$MIG_CLASSES" "$(mig_sql "$MIG/fresh.db" "$MIG_CLASSES")" "classes equal a fresh install's (v13)"
mig_eq "$MIG_SPELLS" "$(mig_sql "$MIG/fresh.db" "$MIG_SPELLS")" "spells equal a fresh install's (v13)"
mig_eq "$MIG_ITEMS" "$(mig_sql "$MIG/fresh.db" "$MIG_ITEMS")" "items and shops equal a fresh install's (v13)"
mig_eq "SELECT group_concat(k) FROM (SELECT key || '=' || icon AS k FROM items WHERE icon <> '' ORDER BY id)" "$(mig_sql "$MIG/fresh.db" "SELECT group_concat(k) FROM (SELECT key || '=' || icon AS k FROM items WHERE icon <> '' ORDER BY id)")" "item icons equal a fresh install's (v13)"
mig_eq "SELECT key || '|' || casts || '|' || charges || '|' || price FROM items WHERE key = 'wand'" "wand|magic_bolt|5|75" "the Wand (v13)"
mig_eq "SELECT town_id FROM town_items WHERE item_key = 'wand'" "1" "Midworld sells the Wand"
mig_eq "$MIG_MONSTERS" "$(mig_sql "$MIG/fresh.db" "$MIG_MONSTERS")" "monsters equal a fresh install's (v13)"
mig_eq "SELECT value FROM meta WHERE key = 'content_fingerprint'" \
	"$(mig_sql "$MIG/fresh.db" "SELECT value FROM meta WHERE key = 'content_fingerprint'")" "content fingerprint (v13)"
# the game on it: the Mage's fight goes on with Magic Bolt (1 MP)
mig_serve "$MIG/v13.lua" "$MIG/v13server.log"
"$BIN" user --config "$MIG/v13.lua" passwd oldmage v13pass1 >/dev/null && t_ok || t_fail "dk user passwd (v13)"
t_jar migv13; t_reset_jar
t_login oldmage v13pass1; expect_redirect /
t_get /fight; expect_status 200; expect_body "Monster's HP: 40"
expect_body 'name="spell" value="25" title="Magic Bolt (1 MP)" aria-label="Magic Bolt (1 MP)" aria-keyshortcuts="4"><img src="/static/images/skills/magic_bolt.png"'
t_round "csrf=$(t_csrf)&round=$(mig_sql "$V13_DB" "SELECT round FROM fights")&spell=25"
expect_body 'You have cast the Magic Bolt spell for '
mig_eq "SELECT currentmp FROM users WHERE id = 1" "14" "1 MP spent"
mig_unserve "$MIG/v13server.log"
"$BIN" migrate --config "$MIG/v13.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v13)"

t_section "migrate: version 14 database"
# version 14 schema + its game data, characters in every state GET /fight and GET /victory
# used to move on: a fight in progress, an encounter waiting for GET /fight to pick its
# monster, a won fight waiting for GET /victory to pay, and one exploring; only steps 15,
# 16 (items.rechargeable), 17 (the hotbar: an empty table), 18 (the maps towns sell) and
# the later steps run. The fight in progress goes on (its counter kept), the pending encounter is cancelled, the victory is paid and
# kept for its page; nobody else changes. Admins' overrides of monsters' immunity become
# resistances and wards (21): where they differ from the file's only.
V14_DB="$MIG/v14.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V14_DB\"#" "$CONFIG" > "$MIG/v14.lua"
mig_script "$V14_DB" "$ROOT/tests/fixtures/schema_v14.sql"
mig_script "$V14_DB" "$ROOT/tests/fixtures/seed_v14.sql"
cat > "$MIG/v14_data.sql" <<SQL
INSERT INTO users (id, username, email, charname, verify, charclass, level, experience, gold, currentaction, latitude,
	longitude, currenthp, base_maxhp) VALUES
	(1, 'midfight', 'm@example.com', 'Midfight', '1', 2, 3, 40, 10, 'Fighting', 5, 5, 30, 30),
	(2, 'pending', 'p@example.com', 'Pending', '1', 2, 1, 0, 0, 'Fighting', 6, 6, 15, 15),
	(3, 'winner', 'w@example.com', 'Winner', '1', 2, 1, 0, 0, 'Fighting', 7, 7, 15, 15),
	(4, 'walker', 'k@example.com', 'Walker', '1', 2, 1, 0, 0, 'Exploring', 8, 8, 15, 15);
INSERT INTO fights (user_id, round, wave, data) VALUES (1, 3, 1, ''), (2, 1, 1, ''), (3, 4, 1, '');
INSERT INTO fight_combatants (user_id, id, side, kind) VALUES (1, 1, 'player', 'player'), (3, 1, 'player', 'player');
INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, wave, hp, maxhp, data) VALUES
	(1, 2, 'enemy', 'monster', 1, 1, 2, 4, 'immune=i:0'), (3, 2, 'enemy', 'monster', 1, 1, 0, 4, 'immune=i:0');
INSERT INTO content_overrides (kind, key, field, value) VALUES ('monsters', 'red_slime', 'immune', '2'),
	('monsters', 'silver_slime', 'immune', '1'), ('monsters', 'shadow', 'immune', '1'), ('monsters', 'critter', 'maxhp', '9');
PRAGMA user_version = 14;
SQL
mig_script "$V14_DB" "$MIG/v14_data.sql"
MIG_DB=$V14_DB
mig_eq "PRAGMA user_version" "14" "fixture is version 14"
mig_eq "SELECT count(*) FROM pragma_table_info('fights') WHERE name = 'outcome'" "0" "no outcome column at version 14"
V14_USERS=$(mig_users "$V14_DB")
"$BIN" migrate --config "$MIG/v14.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v14) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version ([1-9]|1[0-4]):' "$T/migrate.log" && t_fail "steps 1-14 ran on a version 14 database" || t_ok
grep -qF "Migrating to version 15: GETs don't change the game" "$T/migrate.log" && t_ok || t_fail "step 15 not reported: $(cat "$T/migrate.log")"
grep -qF "Migrating to version 16: items that cast a spell may be single use" "$T/migrate.log" && t_ok || t_fail "step 16 not reported"
mig_eq "SELECT group_concat(DISTINCT rechargeable) FROM items WHERE id <= 71" "1" "every item of the time rechargeable (16)"
grep -qF "Migrating to version 17: the hotbar" "$T/migrate.log" && t_ok || t_fail "step 17 not reported"
grep -qF "Migrating to version 18: towns sell only some maps" "$T/migrate.log" && t_ok || t_fail "step 18 not reported"
mig_eq "SELECT group_concat(town_id || '>' || map_id, ' ') FROM (SELECT * FROM town_maps ORDER BY town_id, map_id)" \
	"1>2 2>1 2>3 3>2 3>4 4>3 4>5 5>4 5>6 6>5 6>7 7>6 7>8 8>7" "each town sells its neighbours' maps (18)"
grep -qF "Migrating to version 19: shop lists name items by key" "$T/migrate.log" && t_ok || t_fail "step 19 not reported"
mig_eq "SELECT group_concat(name) FROM pragma_table_info('town_items')" "town_id,item_key" "shop lists by item key (19)"
mig_eq "SELECT group_concat(town_id) FROM (SELECT town_id FROM town_items WHERE item_key = 'hi_potion' ORDER BY town_id)" \
	"3,4,5,6" "the 3.1 wares in their towns (19)"
mig_eq "SELECT group_concat(town_id) FROM (SELECT town_id FROM town_items WHERE item_key = 'antidote' ORDER BY town_id)" \
	"1,2,3,4" "the Antidote sold at last (19)"
mig_eq "SELECT count(*) FROM user_hotbar" "0" "no hotbar yet (17): the next fight fills it"
grep -qF "Migrating to version 21: elements and wards" "$T/migrate.log" && t_ok || t_fail "step 21 not reported"
mig_eq "SELECT count(*) FROM pragma_table_info('monsters') WHERE name = 'immune'" "0" "monsters.immune is gone (21)"
mig_eq "SELECT group_concat(key || ':' || field || '=' || value, ' ') FROM (SELECT * FROM content_overrides ORDER BY key, field)" \
	"critter:maxhp=9 red_slime:resist.arcane=100 red_slime:ward.sleep=100 silver_slime:ward.sleep=0" \
	"overrides of immune become resistances and wards where they differ from the file (21)"
mig_eq "SELECT group_concat(key || ':' || (',' || resist || ',' LIKE '%,arcane=100,%') || ':' || (',' || ward || ',' LIKE '%,sleep=100,%'), ' ') FROM (SELECT * FROM monsters WHERE key IN ('red_slime', 'shadow', 'silver_slime') ORDER BY key)" \
	"red_slime:1:1 shadow:1:0 silver_slime:1:0" "and apply: immune to arcane, warding off sleep as the overrides say (21)"
V14_AFF="SELECT key || '|' || resist || '|' || ward FROM monsters WHERE key NOT IN ('red_slime', 'silver_slime') ORDER BY key"
mig_eq "$V14_AFF" "$(mig_sql "$MIG/fresh.db" "$V14_AFF")" "the other monsters' affinities are their files' (21)"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v14 stamped"
[ "$(mig_layout "$V14_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v14 schema differs from a fresh install:"
	diff <(mig_layout "$V14_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v14)"
[ "$(mig_users "$V14_DB" | sed -n '1p;4p')" = "$(echo "$V14_USERS" | sed -n '1p;4p')" ] && t_ok || t_fail "users otherwise changed (v14)"
mig_eq "SELECT id || '|' || currentaction || '|' || latitude || '|' || (experience > 0) || '|' || (gold > 0) FROM users WHERE id IN (2, 3) ORDER BY id" \
	"2|Exploring|6|0|0
3|Exploring|7|1|1" "the pending encounter cancelled where it was, the victory paid"
mig_eq "SELECT user_id || '|' || round || '|' || outcome FROM fights ORDER BY user_id" "1|3|
3|4|victory" "fights: one goes on, the won one is kept for its page"
mig_eq "SELECT count(*) FROM fight_combatants WHERE user_id = 2" "0" "the pending encounter is gone"
V14_PAID=$(mig_sql "$V14_DB" "SELECT experience || '|' || gold || '|' || level FROM users WHERE id = 3")
mig_serve "$MIG/v14.lua" "$MIG/v14server.log"
for u in midfight winner; do
	"$BIN" user --config "$MIG/v14.lua" passwd "$u" v14pass1 >/dev/null && t_ok || t_fail "dk user passwd (v14 $u)"
done
t_jar migv14; t_reset_jar
t_login midfight v14pass1; expect_redirect /
t_get /fight; expect_status 200; expect_body "Monster's HP: 2"; expect_body 'name="round" value="3"'
t_get /fight; mig_eq "SELECT round FROM fights WHERE user_id = 1" "3" "GET /fight counts nothing"
t_round "csrf=$(t_csrf)&round=3&fight=Fight"
mig_eq "SELECT (round = 4 AND outcome = '') OR outcome = 'victory' FROM fights WHERE user_id = 1" "1" "a round is played"
t_jar migv14w; t_reset_jar
t_login winner v14pass1; expect_redirect /
t_get /victory; expect_status 200; expect_body 'You have defeated the Blue Slime.'
t_get /victory; expect_status 200; expect_body 'You have defeated the Blue Slime.'
mig_eq "SELECT experience || '|' || gold || '|' || level FROM users WHERE id = 3" "$V14_PAID" "GET /victory pays nothing"
mig_unserve "$MIG/v14server.log"
"$BIN" migrate --config "$MIG/v14.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v14)"

t_section "migrate: version 21 database"
# version 21 schema + its game data: a fight in progress with a status and an ally counting
# turns, a world status, an admin's override of a status's turns, and hotbars with an
# action on key 9 (one with a free key, one full); only step 22 runs.
V21_DB="$MIG/v21.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V21_DB\"#" "$CONFIG" > "$MIG/v21.lua"
mig_script "$V21_DB" "$ROOT/tests/fixtures/schema_v21.sql"
mig_script "$V21_DB" "$ROOT/tests/fixtures/seed_v21.sql"
cat > "$MIG/v21_data.sql" <<SQL
INSERT INTO users (id, username, email, charname, verify, charclass, level, currentaction, latitude, longitude,
	currenthp, base_maxhp, dexterity) VALUES
	(1, 'midfight', 'm@example.com', 'Midfight', '1', 2, 3, 'Fighting', 5, 5, 30, 30, 22500),
	(2, 'hotkeys', 'h@example.com', 'Hotkeys', '1', 1, 9, 'In Town', 0, 0, 15, 15, 5);
INSERT INTO fights (user_id, round, wave, data) VALUES (1, 3, 1, '');
INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, wave, hp, maxhp, turns_left) VALUES
	(1, 1, 'player', 'player', NULL, 0, NULL, NULL, NULL), (1, 2, 'enemy', 'monster', 1, 1, 400, 400, NULL),
	(1, 3, 'ally', 'summon', 1, 0, 30, 30, 4);
INSERT INTO summons (id, key, name, hp, turns) VALUES (1, 'wolf', 'Wolf', 30, 5);
INSERT INTO fight_statuses (user_id, combatant_id, status_id, position, turns_left, data, applied_round)
	VALUES (1, 2, 1, 1, NULL, 'chance=i:15', 3);
INSERT INTO statuses (id, key, name) VALUES (4, 'regen', 'Regenerating');
INSERT INTO user_statuses (user_id, status_id, position, turns_left, data) VALUES (2, 4, 1, 7, 'amount=i:5');
INSERT INTO content_overrides (kind, key, field, value) VALUES ('statuses', 'poison', 'turns', '6'),
	('summons', 'wolf', 'turns', '9'), ('statuses', 'poison', 'name', 'Envenomed');
INSERT INTO user_hotbar (user_id, kind, ref_id, slot) VALUES (1, 'spell', 1, 2), (1, 'spell', 6, 9), (1, 'item', 66, 3),
	(2, 'spell', 1, 2), (2, 'spell', 6, 3), (2, 'spell', 7, 4), (2, 'spell', 8, 5), (2, 'spell', 9, 6), (2, 'spell', 10, 7),
	(2, 'spell', 11, 8), (2, 'spell', 12, 9), (2, 'spell', 13, NULL);
PRAGMA user_version = 21;
SQL
mig_script "$V21_DB" "$MIG/v21_data.sql"
MIG_DB=$V21_DB
mig_eq "PRAGMA user_version" "21" "fixture is version 21"
"$BIN" migrate --config "$MIG/v21.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v21) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version ([1-9]|1[0-9]|2[01]):' "$T/migrate.log" && t_fail "steps 1-21 ran on a version 21 database" || t_ok
grep -qF "Migrating to version 22: fights in real time on the server's tick" "$T/migrate.log" && t_ok || t_fail "step 22 not reported: $(cat "$T/migrate.log")"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v21 stamped"
[ "$(mig_layout "$V21_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v21 schema differs from a fresh install:"
	diff <(mig_layout "$V21_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v21)"
mig_eq "SELECT tick || ':' || deadline || ':' || due || ':' || round FROM fights" "0:0:0:3" \
	"the fight in progress goes on the clock when next played (or ticked)"
mig_eq "SELECT group_concat(id || '=' || coalesce(ticks_left, '-'), ' ') FROM fight_combatants" "1=- 2=- 3=4" "an ally's turns are ticks"
mig_eq "SELECT tick || ':' || data FROM fight_statuses" "0:chance=i:15" "its status counts from then"
mig_eq "SELECT ticks_left || ':' || tick FROM user_statuses" "7:0" "a world status's moves are ticks"
mig_eq "SELECT group_concat(kind || ':' || key || ':' || field || '=' || value, ' ') FROM (SELECT * FROM content_overrides ORDER BY kind, key, field)" \
	"statuses:poison:name=Envenomed statuses:poison:ticks=6 summons:wolf:ticks=9" "overrides of turns are of ticks"
mig_eq "SELECT name || ':' || ticks FROM statuses WHERE key = 'poison'" "Envenomed:6" "and apply"
mig_eq "SELECT ticks FROM summons WHERE key = 'wolf'" "9" "an ally's too"
mig_eq "SELECT count(*) FROM statuses WHERE key = 'guarding'" "1" "the new status guarding"
mig_eq "SELECT group_concat(user_id || ':' || kind || ':' || ref_id || '@' || coalesce(slot, '-'), ' ') FROM (SELECT * FROM user_hotbar ORDER BY user_id, slot IS NULL, slot, ref_id)" \
	"1:spell:1@2 1:item:66@3 1:spell:6@4 2:spell:1@2 2:spell:6@3 2:spell:7@4 2:spell:8@5 2:spell:9@6 2:spell:10@7 2:spell:11@8 2:spell:12@- 2:spell:13@-" \
	"key 9 to the first free key, or off a full bar"
mig_serve "$MIG/v21.lua" "$MIG/v21server.log"
"$BIN" user --config "$MIG/v21.lua" passwd midfight v21pass1 >/dev/null && t_ok || t_fail "dk user passwd (v21)"
t_jar migv21; t_reset_jar
t_login midfight v21pass1; expect_redirect /
t_get /fight; expect_status 200; expect_body 'name="round" value="3"'; expect_body 'data-turn-ends="'
expect_body 'Your <b>Wolf</b>: 30 / 30 HP <span class="light">(40s left)</span>'
expect_body 'aria-keyshortcuts="9"><img src="/static/images/skills/guard.png"'
t_round "csrf=$(t_csrf)&round=3&guard=Guard"
mig_eq "SELECT round || ':' || tick || ':' || deadline FROM fights" "4:$((T_NOW / 10)):$((T_NOW / 10 + 3))" "on the clock, a round is played"
mig_unserve "$MIG/v21server.log"
"$BIN" migrate --config "$MIG/v21.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v21)"

t_section "migrate: version 22 database"
# version 22 schema + its game data (version 21's seed: it didn't change) and a fight in
# progress on the clock, without fields; steps 23 and 24 run: the fields table, which the sync
# fills (the fight takes the weather's fields at its next tick), and the 3.2 wares added to
# the shops.
V22_DB="$MIG/v22.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V22_DB\"#" "$CONFIG" > "$MIG/v22.lua"
mig_script "$V22_DB" "$ROOT/tests/fixtures/schema_v22.sql"
mig_script "$V22_DB" "$ROOT/tests/fixtures/seed_v21.sql"
V22_TICK=$((T_NOW / 10))
cat > "$MIG/v22_data.sql" <<SQL
INSERT INTO users (id, username, email, charname, verify, charclass, level, currentaction, latitude, longitude,
	currenthp, base_maxhp, dexterity) VALUES (1, 'v22fight', 'v22@example.com', 'Vtwotwo', '1', 2, 3, 'Fighting', 5, 5,
	900, 900, 5);
INSERT INTO fights (user_id, round, wave, data, tick, deadline, due) VALUES (1, 3, 1, '', $V22_TICK, $((V22_TICK + 3)),
	$((V22_TICK + 3)));
INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, wave, hp, maxhp) VALUES
	(1, 1, 'player', 'player', NULL, 0, NULL, NULL), (1, 2, 'enemy', 'monster', 1, 1, 400, 400);
PRAGMA user_version = 22;
SQL
mig_script "$V22_DB" "$MIG/v22_data.sql"
MIG_DB=$V22_DB
mig_eq "PRAGMA user_version" "22" "fixture is version 22"
"$BIN" migrate --config "$MIG/v22.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v22) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version ([1-9]|1[0-9]|2[012]):' "$T/migrate.log" && t_fail "steps 1-22 ran on a version 22 database" || t_ok
grep -qF "Migrating to version 23: fields" "$T/migrate.log" && t_ok || t_fail "step 23 not reported: $(cat "$T/migrate.log")"
grep -qF "Migrating to version 24: the 3.2 wares" "$T/migrate.log" && t_ok || t_fail "step 24 not reported: $(cat "$T/migrate.log")"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v22 stamped"
[ "$(mig_layout "$V22_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v22 schema differs from a fresh install:"
	diff <(mig_layout "$V22_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "SELECT count(*) || '|' || sum(retired) FROM fields" "$(ls "$ROOT/app/content/fields" | wc -l)|0" "the fields synced"
mig_eq "SELECT \"group\" || ':' || damage || ':' || statuses FROM fields WHERE key = 'downpour'" \
	"sky:fire=-40,lightning=25,water=15:burning.blocked=1" "a field's data"
mig_eq "SELECT round || ':' || data FROM fights" "3:" "the fight in progress has no fields yet"
# step 24: the shops sell what a fresh install's do, by key, the ward draughts and gear whose files
# come in the same release included (a key without an item is not sold, but is listed)
[ "$(mig_sql "$V22_DB" "SELECT town_id || '|' || item_key FROM town_items ORDER BY 1")" = \
	"$(mig_sql "$MIG/fresh.db" "SELECT town_id || '|' || item_key FROM town_items ORDER BY 1")" ] \
	&& t_ok || t_fail "migrated v22 shops differ from a fresh install's"
mig_eq "SELECT group_concat(item_key, ' ') FROM (SELECT item_key FROM town_items WHERE town_id = 8 AND item_key IN ('halo_charm', 'sentinel_charm', 'fire_ward_draught', 'frost_ward_draught') ORDER BY 1)" \
	"fire_ward_draught halo_charm sentinel_charm" "Endworld's new wares"
mig_eq "SELECT count(*) FROM items i JOIN town_items t ON t.item_key = i.key WHERE t.town_id = 4 AND i.key = 'rimefur_coat' AND i.retired = 0" "1" "a new ware is an item in its shop"
mig_serve "$MIG/v22.lua" "$MIG/v22server.log"
"$BIN" user --config "$MIG/v22.lua" passwd v22fight v22pass1 >/dev/null && t_ok || t_fail "dk user passwd (v22)"
t_jar migv22; t_reset_jar
t_login v22fight v22pass1; expect_redirect /
t_get /fight; expect_status 200; expect_body 'name="round" value="3"'; expect_body 'data-r="battlefield" data-battlefield'
t_round "csrf=$(t_csrf)&round=3&guard=Guard"
mig_eq "SELECT round FROM fights" "4" "a round is played"
mig_unserve "$MIG/v22server.log"
"$BIN" migrate --config "$MIG/v22.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v22)"

t_section "migrate: version 24 database"
# version 24 schema (3.2.0) + its game data (version 21's seed) with a fight in progress on the
# clock and a monster's loadout; steps 25 and 26 run: the interactables table (the sync fills it), the
# fields' wind, area spells and items, loadout entries' aim, objects' columns in the fights.
# The fight goes on as before: no objects, its target the monster.
V24_DB="$MIG/v24.db"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$V24_DB\"#" "$CONFIG" > "$MIG/v24.lua"
mig_script "$V24_DB" "$ROOT/tests/fixtures/schema_v24.sql"
mig_script "$V24_DB" "$ROOT/tests/fixtures/seed_v21.sql"
V24_TICK=$((T_NOW / 10))
cat > "$MIG/v24_data.sql" <<SQL
INSERT INTO users (id, username, email, charname, verify, charclass, level, currentaction, latitude, longitude,
	currenthp, base_maxhp, dexterity) VALUES (1, 'v24fight', 'v24@example.com', 'Vtwofour', '1', 2, 3, 'Fighting', 5, 5,
	900, 900, 5);
INSERT INTO fights (user_id, round, wave, data, tick, deadline, due) VALUES (1, 3, 1, 'field_sky=s:rain', $V24_TICK,
	$((V24_TICK + 3)), $((V24_TICK + 3)));
INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, wave, hp, maxhp) VALUES
	(1, 1, 'player', 'player', NULL, 0, NULL, NULL), (1, 2, 'enemy', 'monster', 1, 1, 400, 400);
PRAGMA user_version = 24;
SQL
mig_script "$V24_DB" "$MIG/v24_data.sql"
MIG_DB=$V24_DB
mig_eq "PRAGMA user_version" "24" "fixture is version 24"
"$BIN" migrate --config "$MIG/v24.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v24) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version ([1-9]|1[0-9]|2[0-4]):' "$T/migrate.log" && t_fail "steps 1-24 ran on a version 24 database" || t_ok
grep -qF "Migrating to version 25: interactables" "$T/migrate.log" && t_ok || t_fail "step 25 not reported: $(cat "$T/migrate.log")"
grep -qF "Migrating to version 26: the 3.3 ware" "$T/migrate.log" && t_ok || t_fail "step 26 not reported: $(cat "$T/migrate.log")"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v24 stamped"
[ "$(mig_layout "$V24_DB")" = "$(mig_layout "$MIG/fresh.db")" ] && t_ok || {
	t_fail "migrated v24 schema differs from a fresh install:"
	diff <(mig_layout "$V24_DB") <(mig_layout "$MIG/fresh.db") | head -20 >&2
}
mig_eq "PRAGMA foreign_key_check" "" "foreign keys (v24)"
# step 26: the Explosive Barrel in Kalle, Narcissa and Gilead only
mig_eq "SELECT group_concat(town_id) FROM (SELECT town_id FROM town_items WHERE item_key = 'explosive_barrel' ORDER BY 1)" \
	"4,5,7" "the Explosive Barrel is sold in Kalle, Narcissa and Gilead"
mig_eq "SELECT count(*) FROM items i JOIN town_items t ON t.item_key = i.key WHERE t.town_id = 5 AND i.key = 'explosive_barrel' AND i.retired = 0 AND i.price = 180" \
	"1" "a ware is an item at its price in its shop"
mig_eq "SELECT count(*) FROM town_items WHERE item_key = 'war_standard'" "0" "the war standard is sold nowhere"
mig_eq "SELECT count(*) || '|' || sum(retired) FROM interactables" "$M_IA|0" "the objects synced"
mig_eq "SELECT hp || ':' || resist || ':' || replace(spawn, char(10), ';') FROM interactables WHERE key = 'beehive'" \
	"12:fire=-50:1.biomes=weald;1.chance=18;1.features=none;1.fields=heat,sun;1.unless=blizzard,downpour,night,rain,snow,thunderstorm;2.biomes=weald;2.chance=9;2.features=hill,lake,pond;2.fields=heat,sun;2.unless=blizzard,downpour,night,rain,snow,thunderstorm;3.chance=12;3.fields=forest;3.unless=blizzard,downpour,night,rain,snow,thunderstorm;4.biomes=weald;4.chance=6;4.features=hill,lake,pond;4.unless=blizzard,downpour,night,rain,snow,thunderstorm" "an object's data"
mig_eq "SELECT group_concat(key || '=' || wind, ' ') FROM (SELECT key, wind FROM fields WHERE wind > 0 ORDER BY key)" \
	"blizzard=3 cinders=1 gale=3 hills=1 peaks=2 sand=1 thunderstorm=3" "the fields' wind"
mig_eq "SELECT (SELECT sum(area) FROM spells) || '|' || (SELECT sum(area) FROM items) || '|' ||
	(SELECT count(*) FROM monster_items WHERE aim <> '') || '|' || (SELECT count(*) FROM monster_spells WHERE aim <> '')" \
	"13|0|8|13" "the area spells (3.3 content), no area items, the monsters' aims (8 items: the footpads' and the deserters' flasks; 13 spells: the bears', giants', aqua elemental's and witch's)"
mig_eq "SELECT group_concat(id || ':' || coalesce(level, '-') || ':' || coalesce(over, '-'), ' ') FROM fight_combatants" \
	"1:-:- 2:-:-" "the fight's combatants: no objects"
mig_serve "$MIG/v24.lua" "$MIG/v24server.log"
"$BIN" user --config "$MIG/v24.lua" passwd v24fight v24pass1 >/dev/null && t_ok || t_fail "dk user passwd (v24)"
t_jar migv24; t_reset_jar
t_login v24fight v24pass1; expect_redirect /
t_get /fight; expect_status 200; expect_body 'name="round" value="3"'; expect_no_body 'name="target"'
t_round "csrf=$(t_csrf)&round=3&fight=Fight"; expect_body 'You attack the monster for'
mig_eq "SELECT round FROM fights" "4" "a round is played"
mig_unserve "$MIG/v24server.log"
"$BIN" migrate --config "$MIG/v24.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v24)"

t_section "migrate: version 25 database"
# step 26 alone: a version 25 database whose shops lack the barrel gets it in the three towns, and nothing else
# changes (the shops' other wares stay, whatever an admin did to them)
MIG_DB=$V24_DB
mig_sql "$V24_DB" "DELETE FROM town_items WHERE item_key = 'explosive_barrel'; INSERT OR IGNORE INTO town_items (town_id, item_key) VALUES (1, 'travel_tea'); DELETE FROM town_items WHERE town_id = 8 AND item_key = 'void_flask'; PRAGMA user_version = 25"
mig_eq "PRAGMA user_version" "25" "fixture is version 25"
"$BIN" migrate --config "$MIG/v24.lua" >"$T/migrate.log" 2>&1 && t_ok || t_fail "dk migrate (v25) failed: $(cat "$T/migrate.log")"
grep -qE 'Migrating to version ([1-9]|1[0-9]|2[0-5]):' "$T/migrate.log" && t_fail "steps 1-25 ran on a version 25 database" || t_ok
grep -qF "Migrating to version 26: the 3.3 ware" "$T/migrate.log" && t_ok || t_fail "step 26 not reported: $(cat "$T/migrate.log")"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "v25 stamped"
mig_eq "SELECT group_concat(town_id) FROM (SELECT town_id FROM town_items WHERE item_key = 'explosive_barrel' ORDER BY 1)" \
	"4,5,7" "the Explosive Barrel is back in Kalle, Narcissa and Gilead"
mig_eq "SELECT count(*) FROM town_items WHERE town_id = 8 AND item_key = 'void_flask'" "0" "what an admin took off a shop stays off"
"$BIN" migrate --config "$MIG/v24.lua" >"$T/migrate.log" 2>&1 && grep -qF 'is up to date' "$T/migrate.log" && t_ok || t_fail "second migrate (v25)"

t_section "migrate: partial and forced installs are current"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$MIG/partial.db\"#" "$CONFIG" > "$MIG/partial.lua"
"$BIN" install --config "$MIG/partial.lua" --partial --admin part part@example.com partpw --charname Parter \
	>/dev/null 2>&1 && t_ok || t_fail "partial install"
MIG_DB="$MIG/partial.db"
mig_eq "PRAGMA user_version" "$CUR_VERSION" "partial install stamped"
mig_eq "SELECT count(*) FROM forums" "2" "partial install has the boards"
mig_eq "SELECT count(*) FROM towns" "0" "partial install has no game data"
mig_eq "SELECT count(*) || '|' || (SELECT count(*) FROM class_levels) FROM classes" "3|297" "partial install has the classes"
mig_eq "SELECT count(*) || '|' || max(id) || '|' || sum(messages <> '') FROM spells" "$M_SP|$M_SP|$M_SP" "partial install has the spells"
mig_eq "SELECT count(*) || '|' || max(id) || '|' || (SELECT count(*) FROM town_items) FROM items" "$M_IT|$M_IT|0" "partial install has the items, no shops"
mig_eq "SELECT f.board || '|' || f.author || '|' || (f.author_id = n.author_id) FROM news n JOIN forum f ON f.id = n.thread_id" \
	"2|Parter|1" "partial install news thread"
"$BIN" install --config "$MIG/partial.lua" --force --admin part part@example.com partpw \
	>/dev/null 2>&1 && t_ok || t_fail "install --force over a current database"
mig_eq "SELECT count(*) || '|' || (SELECT count(*) FROM forum) || '|' || (SELECT count(*) FROM towns) FROM news" "1|1|8" "forced install"

fi
