# tests/e2e/quickstart.sh :: `dk serve --port/--bind` and `make run` (scripts/run.sh): first
# run creates the config and installs, later runs reuse them, an old database is migrated.
# Sourced by tests/run.sh. Uses its own directories, ports and servers.

# A port nobody listens on, below Linux's default ephemeral range (32768+), where client
# sockets could hold it.
qs_free_port() {
	local p
	for _ in $(seq 1 50); do
		p=$((20000 + RANDOM % 12000))
		(exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null || { echo "$p"; return 0; }
	done
	return 1
}
# qs_wait URL PID: wait (max ~60 s: the first run hashes a password at full strength) until
# GET URL answers 200, while PID lives.
qs_wait() {
	for _ in $(seq 1 600); do
		[ "$(curl -s -o /dev/null -w '%{http_code}' "$1")" = 200 ] && return 0
		kill -0 "$2" 2>/dev/null || return 1
		sleep 0.1
	done
	return 1
}
qs_stop() { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }
qs_sanitizer() {  # fail on sanitizer reports in a log
	if grep -qE 'runtime error:|Sanitizer' "$1"; then
		t_fail "sanitizer report in $1:"; grep -E -A20 'runtime error:|Sanitizer' "$1" | head -40 >&2
	fi
}

t_section "serve: --port and --bind override the config"
QS_PORT=$(qs_free_port)
"$BIN" serve --config "$CONFIG" --port "$QS_PORT" --bind 127.0.0.2 >"$T/qs-serve.log" 2>&1 &
QS_PID=$!
if qs_wait "http://127.0.0.2:$QS_PORT/login" "$QS_PID"; then t_ok; else t_fail "no server on 127.0.0.2:$QS_PORT: $(cat "$T/qs-serve.log")"; fi
grep -qF "http: listening on 127.0.0.2:$QS_PORT" "$T/qs-serve.log" && t_ok || t_fail "listen line: $(cat "$T/qs-serve.log")"
qs_stop "$QS_PID"
qs_sanitizer "$T/qs-serve.log"
for bad in "--port 65536" "--port -1" "--port 80x" "--port" "--bind nowhere" "--bind" "--verbose"; do
	# shellcheck disable=SC2086
	"$BIN" serve --config "$CONFIG" $bad >"$T/qs-serve.log" 2>&1
	[ $? = 2 ] && t_ok || t_fail "dk serve $bad: expected status 2 ($(cat "$T/qs-serve.log"))"
done

t_section "make run: first run in a fresh copy"
QS="$T/qs"
mkdir -p "$QS"
cp -r "$ROOT/app" "$ROOT/templates" "$ROOT/public" "$QS/"
QS_PORT=$(qs_free_port)
qs_start() {  # qs_start: scripts/run.sh in $QS on $QS_PORT (output in $QS/run.out)
	(cd "$QS" && exec env DK_BIN="$BIN" PORT="$QS_PORT" "$ROOT/scripts/run.sh") >"$QS/run.out" 2>&1 &
	QS_PID=$!
}
qs_start
if qs_wait "http://127.0.0.1:$QS_PORT/login" "$QS_PID"; then t_ok; else t_fail "run.sh server: $(cat "$QS/run.out")"; fi
qs_stop "$QS_PID"
grep -qF 'run: created config.lua from config.example.lua with a random secret' "$QS/run.out" && t_ok || t_fail "no config message"
grep -qE '^[[:space:]]*secret = "[0-9a-f]{64}",$' "$QS/config.lua" && t_ok || t_fail "no random secret in config.lua"
grep -qF "run: log in at http://127.0.0.1:$QS_PORT/ as 'admin' with password 'admin'" "$QS/run.out" && t_ok || t_fail "no login hint"
grep -qF "Dragon Knight on http://127.0.0.1:$QS_PORT/ (Ctrl-C to stop)" "$QS/run.out" && t_ok || t_fail "no URL line"
[ -f "$QS/data/dk.db" ] && t_ok || t_fail "no database"
if t_has_sql; then
	[ "$(t_sql_db "$QS/data/dk.db" "SELECT username || ',' || authlevel FROM users")" = "admin,1" ] && t_ok || t_fail "admin account"
fi
qs_sanitizer "$QS/run.out"

t_section "make run: second run reuses config and database"
QS_CONFIG_SUM=$(cksum < "$QS/config.lua")
QS_DB_INODE=$(stat -c %i "$QS/data/dk.db")
qs_start
if qs_wait "http://127.0.0.1:$QS_PORT/login" "$QS_PID"; then t_ok; else t_fail "second run: $(cat "$QS/run.out")"; fi
qs_stop "$QS_PID"
grep -qE 'run: created|installing|Migrating' "$QS/run.out" && t_fail "second run set things up again: $(cat "$QS/run.out")" || t_ok
[ "$(cksum < "$QS/config.lua")" = "$QS_CONFIG_SUM" ] && t_ok || t_fail "config.lua changed"
[ "$(stat -c %i "$QS/data/dk.db")" = "$QS_DB_INODE" ] && t_ok || t_fail "database replaced"
qs_sanitizer "$QS/run.out"

if t_has_sql; then
	t_section "make run: an old database is backed up and migrated"
	rm -f "$QS/data/dk.db" "$QS/data/dk.db-wal" "$QS/data/dk.db-shm"
	t_sql_script "$QS/data/dk.db" "$ROOT/tests/fixtures/schema_v0.sql"
	grep -v '^INSERT INTO forums ' "$ROOT/tests/fixtures/seed_v3.sql" > "$QS/seed_v0.sql"
	t_sql_script "$QS/data/dk.db" "$QS/seed_v0.sql"
	qs_start
	if qs_wait "http://127.0.0.1:$QS_PORT/login" "$QS_PID"; then t_ok; else t_fail "run on an old database: $(cat "$QS/run.out")"; fi
	qs_stop "$QS_PID"
	grep -qF 'Migrating to version 1' "$QS/run.out" && t_ok || t_fail "not migrated: $(cat "$QS/run.out")"
	ls "$QS/data/backups/"dk-*.db >/dev/null 2>&1 && t_ok || t_fail "no backup before migrating"
	[ "$(t_sql_db "$QS/data/dk.db" "PRAGMA user_version")" = "$(t_sql "PRAGMA user_version")" ] && t_ok || t_fail "schema version"
	qs_sanitizer "$QS/run.out"
fi

# the make target itself, with a ready config (absolute paths) and the binary under test
QS_REL=${BIN#"$ROOT"/}
if [ "$QS_REL" = "$BIN" ] || ! command -v setsid >/dev/null; then
	t_section "make run (skipped: binary outside the tree or no setsid)"
else
	t_section "make run: the target"
	mkdir -p "$T/mr"
	sed "s#db_path = \"$T/dk.db\"#db_path = \"$T/mr/dk.db\"#" "$CONFIG" > "$T/mr/config.lua"
	QS_PORT=$(qs_free_port)
	# own process group (setsid) so make and the server stop together; -o: use $BIN as built
	setsid env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u MAKEOVERRIDES \
		make -C "$ROOT" --no-print-directory -o "$QS_REL" BIN="$QS_REL" run CONFIG="$T/mr/config.lua" \
		PORT="$QS_PORT" BIND=127.0.0.1 ADMIN_USER=mradmin ADMIN_PASS=mrpass1 >"$T/mr/run.out" 2>&1 &
	QS_PID=$!
	if qs_wait "http://127.0.0.1:$QS_PORT/login" "$QS_PID"; then t_ok; else t_fail "make run: $(cat "$T/mr/run.out")"; fi
	kill -TERM -- "-$QS_PID" 2>/dev/null; wait "$QS_PID" 2>/dev/null
	grep -qF "log in at http://127.0.0.1:$QS_PORT/ as 'mradmin' with password 'mrpass1'" "$T/mr/run.out" \
		&& t_ok || t_fail "make run output: $(cat "$T/mr/run.out")"
	grep -qF 'run: created' "$T/mr/run.out" && t_fail "make run rewrote an existing config" || t_ok
	if t_has_sql; then
		[ "$(t_sql_db "$T/mr/dk.db" "SELECT username FROM users")" = mradmin ] && t_ok || t_fail "make run: admin account"
	fi
	qs_sanitizer "$T/mr/run.out"
fi
