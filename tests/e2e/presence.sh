# tests/e2e/presence.sh :: who's online, live (lib/presence.lua): a player's first request
# announces them (`join` on the presence channel, once), the town list and the count in the
# right column, departures found by the sweep (`leave`) for players without a request in
# the window and without an open stream, and the config keys online_seconds and
# presence_sweep_seconds. Sweeps are forced by deleting meta.presence_sweep, idle players
# made by aging users.onlinetime. Sourced by tests/run.sh (live_* helpers there).

pres_sweep() { t_sql "DELETE FROM meta WHERE key = 'presence_sweep'"; }
pres_age() { t_sql "UPDATE users SET onlinetime = onlinetime - 700 WHERE username = '$1'"; }
pres_online() { t_sql "SELECT online FROM users WHERE username = '$1'"; }
# pres_events STREAM EVENT NAME: how many EVENT events about the player NAME the stream has
pres_events() { grep -A1 -xF "event: $2" "$T/live.$1" | grep -cF "\"name\":\"$3\""; }
# pres_expect STREAM EVENT NAME N: wait (3 s at most) until there are N, then check
pres_expect() {
	local i
	for ((i = 0; i < 30; i++)); do [ "$(pres_events "$1" "$2" "$3")" = "$4" ] && break; sleep 0.1; done
	[ "$(pres_events "$1" "$2" "$3")" = "$4" ] && t_ok || t_fail "stream $1: expected $4 $2 events for $3, got $(pres_events "$1" "$2" "$3")"
}

t_section "presence: joining"
t_jar presa; t_reset_jar
t_register presa presapw1 presa@example.com PresA; t_login presa presapw1
t_get /;      expect_status 200
live_open a
t_jar presb; t_reset_jar
t_register presb presbpw1 presb@example.com PresB; t_login presb presbpw1
PRESB_ID=$(t_sql "SELECT id FROM users WHERE username = 'presb'")
[ "$(pres_online presb)" = 0 ] && t_ok || t_fail "online before the first request"
t_get /;      expect_status 200
pres_expect a join PresB 1
live_has a "\"id\":$PRESB_ID,\"name\":\"PresB\",\"online\":"
expect_body "<a data-id=\"$PRESB_ID\" href=\"/character/$PRESB_ID\">PresB</a>"
COUNT=$(t_sql "SELECT count(*) FROM users WHERE online = 1")
expect_body "There are <b data-online-count>$COUNT</b> user(s) online:"
grep -qF "\"online\":$COUNT}" "$T/live.a" && t_ok || t_fail "join: online count $COUNT"
t_get /inn;   expect_body "Online: <span data-online-count>$COUNT</span>"
t_get /;      t_get /inn
pres_expect a join PresB 1

t_section "presence: leaving"
pres_age presb; pres_sweep
t_jar presa; t_get /inn                     # any request runs the due sweep
pres_expect a leave PresB 1
[ "$(pres_online presb)" = 0 ] && t_ok || t_fail "PresB still online"
t_get /;      expect_no_body ">PresB</a>"
pres_sweep; t_get /inn                      # no second leave
pres_expect a leave PresB 1
pres_age presa; pres_sweep; t_get /inn      # the request counts before the sweep
[ "$(pres_online presa)" = 1 ] && t_ok || t_fail "PresA swept on their own request"
pres_expect a leave PresA 0

t_section "presence: an open stream keeps a player online"
t_jar presb
live_open b                                 # a request: PresB is back
pres_expect a join PresB 2
pres_age presb; pres_sweep
t_jar presa; t_get /inn
[ "$(pres_online presb)" = 1 ] && t_ok || t_fail "PresB swept while streaming"
live_close b
for _ in $(seq 1 30); do                    # the server notices the stream closed
	pres_sweep; t_get /inn
	[ "$(pres_online presb)" = 0 ] && break
	sleep 0.1
done
[ "$(pres_online presb)" = 0 ] && t_ok || t_fail "PresB not swept after closing the stream"
pres_expect a leave PresB 2

t_section "presence: config keys"
# short windows from the config (hot): PresC goes after 2 s without requests, swept by
# PresA's requests at most every second
t_jar presc; t_reset_jar
t_register presc prescpw1 presc@example.com PresC; t_login presc prescpw1
t_get /
sed -i 's/^\([[:space:]]*\)online_seconds = 600,$/\1online_seconds = 2,/; s/^\([[:space:]]*\)presence_sweep_seconds = 60,$/\1presence_sweep_seconds = 1,/' "$CONFIG"
t_jar presa
for _ in $(seq 1 80); do
	t_get /changepassword
	[ "$(pres_online presc)" = 0 ] && break
	sleep 0.1
done
[ "$(pres_online presc)" = 0 ] && t_ok || t_fail "PresC not swept with online_seconds = 2"
pres_expect a leave PresC 1
[ "$(pres_online presa)" = 1 ] && t_ok || t_fail "PresA swept while active"
sed -i 's/^\([[:space:]]*\)online_seconds = 2,$/\1online_seconds = 600,/; s/^\([[:space:]]*\)presence_sweep_seconds = 1,$/\1presence_sweep_seconds = 60,/' "$CONFIG"
live_stop
t_jar default
