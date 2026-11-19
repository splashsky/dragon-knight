# tests/e2e/live.sh :: event streams (GET /live, server-sent events; src/hub.c): the stream
# head, events published only after their transaction commits (none on rollback), which
# channels a player gets (their own user:<id>, admin only for administrators),
# Last-Event-ID replay and resync, heartbeats, 405 for other methods, the metrics. Uses
# POST /__test/publish (config test_routes = true, set by tests/run.sh) and a 1 s
# heartbeat (stream_heartbeat_ms = 1000). Sourced by tests/run.sh.

LIVE_PIDS=()
# live_open NAME [curl args...]: GET /live with the current jar in the background; the
# stream goes to $T/live.NAME, its head to $T/live.NAME.h
live_open() {
	local name=$1
	shift
	rm -f "$T/live.$name" "$T/live.$name.h"
	curl -sN -m 20 -b "$JAR" -D "$T/live.$name.h" "$@" "$BASE/live" > "$T/live.$name" 2>/dev/null &
	LIVE_PIDS+=($!)
	live_wait "$name" 'id: ' || t_fail "stream $name did not open"
}
# live_wait NAME TEXT [TRIES]: wait (100 ms steps, default 3 s) until the stream has TEXT
live_wait() {
	local i
	for ((i = 0; i < ${3:-30}; i++)); do
		grep -qF -- "$2" "$T/live.$1" 2>/dev/null && return 0
		sleep 0.1
	done
	return 1
}
live_has() { if live_wait "$1" "$2" "${3:-30}"; then t_ok; else t_fail "stream $1 lacks: $2"; fi; }
live_lacks() { if grep -qF -- "$2" "$T/live.$1"; then t_fail "stream $1 unexpectedly has: $2"; else t_ok; fi; }
live_stop() { kill "${LIVE_PIDS[@]}" 2>/dev/null; wait "${LIVE_PIDS[@]}" 2>/dev/null; LIVE_PIDS=(); }
# live_publish CHANNEL EVENT DATA [extra form fields]: POST /__test/publish (current jar)
live_publish() {
	t_get /changepassword
	t_post /__test/publish "csrf=$(t_csrf)&channel=$1&event=$2&data=$(t_enc "$3")${4:+&$4}"
}

t_section "live: guards and methods"
t_jar liveanon; t_reset_jar
t_get /live;               expect_redirect /login
t_jar livea; t_reset_jar
t_register livea liveapw1 livea@example.com LiveA; t_login livea liveapw1
t_head /live;              expect_status 405; expect_header '^allow: GET'
t_get /changepassword; t_post /live "csrf=$(t_csrf)"; expect_status 405
t_post /__test/publish "channel=babble&event=x&data=y"; expect_status 403   # CSRF as usual

t_section "live: the stream"
live_open a
LIVE_HEAD=$(tr -d '\r' < "$T/live.a.h")
for h in 'HTTP/1.1 200 OK' 'Content-Type: text/event-stream' 'Cache-Control: no-store' \
		'X-Accel-Buffering: no' 'Connection: keep-alive'; do
	grep -qxF "$h" <<< "$LIVE_HEAD" && t_ok || t_fail "stream head lacks '$h': $LIVE_HEAD"
done
grep -qi '^content-length' <<< "$LIVE_HEAD" && t_fail "stream head has a Content-Length" || t_ok
head -n1 "$T/live.a" | grep -qx 'retry: 3000' && t_ok || t_fail "no retry line: $(head -c 200 "$T/live.a")"
live_publish babble chat 'hello <b>everyone</b>
second line'
expect_status 200
live_has a $'event: chat\ndata: hello <b>everyone</b>\ndata: second line\n'
live_has a ': ping' 25                   # stream_heartbeat_ms = 1000

t_section "live: published after commit, never on rollback"
live_publish babble slow 'committed late' 'delay_ms=1200' &
SLOW_PID=$!
sleep 0.6
live_lacks a 'committed late'            # still inside its transaction
wait $SLOW_PID
live_has a $'event: slow\ndata: committed late'
live_publish babble doomed 'rolled back' 'fail=1'
expect_status 500
live_publish babble marker 'after the failure'
live_has a 'after the failure'
live_lacks a 'rolled back'
live_publish 'Bad Channel' x y;          expect_status 500

t_section "live: channels per player"
LIVEA_ID=$(t_sql "SELECT id FROM users WHERE username = 'livea'")
t_jar liveb; t_reset_jar
t_register liveb livebpw1 liveb@example.com LiveB; t_login liveb livebpw1
LIVEB_ID=$(t_sql "SELECT id FROM users WHERE username = 'liveb'")
live_open b
t_jar liveadmin; t_reset_jar
t_login "$ADMIN_USER" "$ADMIN_PASS"
live_open admin
live_publish "user:$LIVEA_ID" note 'for a only'
live_publish "user:$LIVEB_ID" note 'for b only'
live_publish admin alert 'for admins'
live_publish notices news 'for everyone'
for s in a b admin; do live_has $s 'for everyone'; done
live_has a 'for a only';   live_lacks a 'for b only';   live_lacks a 'for admins'
live_has b 'for b only';   live_lacks b 'for a only';   live_lacks b 'for admins'
live_has admin 'for admins'; live_lacks admin 'for a only'; live_lacks admin 'for b only'

t_section "live: Last-Event-ID"
# the id of a's "hello" event: a reconnect after it gets what came later, and nothing else
HELLO_ID=$(grep -B1 '^event: chat$' "$T/live.a" | head -n1 | sed 's/^id: //')
BOOT=${HELLO_ID%-*}
[ -n "$BOOT" ] && t_ok || t_fail "no event id in the stream"
t_jar livea
live_open a2 -H "Last-Event-ID: $HELLO_ID"
live_has a2 'committed late'; live_has a2 'for a only'; live_has a2 'for everyone'
live_lacks a2 'hello <b>everyone</b>'; live_lacks a2 'for b only'; live_lacks a2 'rolled back'
live_lacks a2 'event: resync'
live_open a3 -H "Last-Event-ID: 0000-1"
live_has a3 $'event: resync\ndata: \n'
live_lacks a3 'for a only'
live_stop

t_section "live: metrics"
t_jar liveadmin
t_get /admin/server;       expect_status 200
expect_body '<h2>Event streams</h2>'; expect_body '<code>streams_opened</code>'
expect_body '<code>events_published</code>'; expect_body '<code>events_replayed</code>'
STATS_OUT=$("$BIN" stats --config "$CONFIG" 2>&1)
printf '%s\n' "$STATS_OUT" | grep -qE '^  streams_opened +[1-9]' && t_ok || t_fail "dk stats: streams_opened"
printf '%s\n' "$STATS_OUT" | grep -qE '^  events_replayed +[1-9]' && t_ok || t_fail "dk stats: events_replayed"
printf '%s\n' "$STATS_OUT" | grep -qE '^  stream_resyncs +[1-9]' && t_ok || t_fail "dk stats: stream_resyncs"
printf '%s\n' "$STATS_OUT" | grep -qE '^  channel\.babble +[0-9]' && t_ok || t_fail "dk stats: channel.babble"

t_section "live: the test route needs test_routes"
sed -i 's/^\([[:space:]]*\)test_routes = true,$/\1test_routes = false,/' "$CONFIG"
for _ in $(seq 1 50); do
	live_publish babble x y; [ "$STATUS" = 404 ] && break; sleep 0.1
done
expect_status 404
sed -i 's/^\([[:space:]]*\)test_routes = false,$/\1test_routes = true,/' "$CONFIG"
for _ in $(seq 1 50); do
	live_publish babble x y; [ "$STATUS" = 200 ] && break; sleep 0.1
done
expect_status 200
t_jar default
