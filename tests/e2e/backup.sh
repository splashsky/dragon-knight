# tests/e2e/backup.sh :: `dk backup` on the running test server's database: a consistent
# copy while other connections write, default file names, no overwriting, missing database.
# Sourced by tests/run.sh.

if ! t_has_sql; then
	t_section "backup (skipped: needs sqlite3 or python3)"
else

# Row counts of the main tables and the schema version of a database.
bk_summary() {
	t_sql_db "$1" "SELECT (SELECT count(*) FROM users) || ',' || (SELECT count(*) FROM monsters) || ',' ||
		(SELECT count(*) FROM items) || ',' || (SELECT count(*) FROM towns) || ',' ||
		(SELECT count(*) FROM forum) || ',' || (SELECT count(*) FROM news); PRAGMA user_version"
}

t_section "backup: while the server is running"
BK_PAT="^$T/backups/dk-[0-9]{8}-[0-9]{6}(-[0-9]+)?\.db$"
# writers on the live database meanwhile: the server (HTTP) and another connection
(
	for _ in $(seq 1 60); do
		curl -s -o /dev/null -X POST "$BASE/login" --data "username=x&password=y"
		t_sql "UPDATE control SET gamename = gamename"
	done
) >/dev/null 2>&1 &
BK_WRITER=$!
"$BIN" backup --config "$CONFIG" >"$T/backup.out" 2>&1 && t_ok || t_fail "dk backup: $(cat "$T/backup.out")"
BK1=$(cat "$T/backup.out")
"$BIN" backup --config "$CONFIG" >"$T/backup.out" 2>&1 && t_ok || t_fail "second dk backup: $(cat "$T/backup.out")"
BK2=$(cat "$T/backup.out")
wait "$BK_WRITER"
[[ $BK1 =~ $BK_PAT ]] && t_ok || t_fail "default backup path: '$BK1'"
[[ $BK2 =~ $BK_PAT ]] && [ "$BK2" != "$BK1" ] && t_ok || t_fail "second default path: '$BK2' (first '$BK1')"
[ -f "$BK1" ] && [ -f "$BK2" ] && t_ok || t_fail "backup files missing"
[ "$(t_sql_db "$BK1" "PRAGMA integrity_check")" = ok ] && t_ok || t_fail "backup integrity"
[ "$(t_sql_db "$BK1" "PRAGMA journal_mode")" = delete ] && t_ok || t_fail "backup is not a standalone file"
[ "$(bk_summary "$BK1")" = "$(bk_summary "$T/dk.db")" ] && t_ok \
	|| t_fail "backup rows differ: $(bk_summary "$BK1" | tr '\n' ' ') vs $(bk_summary "$T/dk.db" | tr '\n' ' ')"
[ -z "$(find "$T/backups" -name '*.tmp*' -o -name '*-wal' -o -name '*-shm' -o -name '*-journal')" ] \
	&& t_ok || t_fail "leftover files in $T/backups: $(ls "$T/backups")"
t_get /login; expect_status 200

t_section "backup: explicit output, never overwritten"
"$BIN" backup --config "$CONFIG" "$T/bk/sub/copy.db" >"$T/backup.out" 2>&1 && t_ok || t_fail "dk backup OUTPUT: $(cat "$T/backup.out")"
[ "$(cat "$T/backup.out")" = "$T/bk/sub/copy.db" ] && t_ok || t_fail "printed path: $(cat "$T/backup.out")"
[ "$(t_sql_db "$T/bk/sub/copy.db" "SELECT count(*) FROM monsters")" = 151 ] && t_ok || t_fail "explicit copy content"
BK_SUM=$(cksum < "$T/bk/sub/copy.db")
"$BIN" backup --config "$CONFIG" "$T/bk/sub/copy.db" >"$T/backup.out" 2>&1 && t_fail "overwrote an existing file" || t_ok
grep -qF 'already exists; not overwriting it' "$T/backup.out" && t_ok || t_fail "overwrite message: $(cat "$T/backup.out")"
[ "$(cksum < "$T/bk/sub/copy.db")" = "$BK_SUM" ] && t_ok || t_fail "existing file changed"
"$BIN" backup --config "$CONFIG" "$T/bk/a.db" "$T/bk/b.db" >/dev/null 2>&1
[ $? = 2 ] && t_ok || t_fail "two outputs must be a usage error"

t_section "backup: missing database"
mkdir -p "$T/bk/nodb"
sed "s#db_path = \"$T/dk.db\"#db_path = \"$T/bk/nodb/data/dk.db\"#" "$CONFIG" > "$T/bk/nodb/config.lua"
"$BIN" backup --config "$T/bk/nodb/config.lua" >"$T/backup.out" 2>&1
[ $? = 3 ] && t_ok || t_fail "missing database: exit status 3 expected"
grep -qF "no database at $T/bk/nodb/data/dk.db" "$T/backup.out" && t_ok || t_fail "missing database message: $(cat "$T/backup.out")"
[ ! -e "$T/bk/nodb/data" ] && t_ok || t_fail "dk backup created files for a missing database"

fi
