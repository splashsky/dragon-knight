# tests/e2e/tick.sh :: the server's tick (docs/APP.md "The server tick"; lib/tick.lua):
# the fight page's turn timer, the clock advancing a fight (a turn that ran out is a
# Guard, the lines kept in the fight's log, `stale` told to the player's pages), GETs that
# show the fight as the tick left it without advancing it, a network request that can't
# pose as the tick, and the weather pushed to an open page when it changes. The e2e
# server's own tick is off: t_tick runs it (POST /__test/tick) with the clock moved on.
# Sourced by tests/run.sh.
if ! t_has_sql; then
	t_section "tick (skipped: needs sqlite3 or python3)"
else

t_section "tick: the route only the engine reaches"
t_jar tick; t_reset_jar
t_register ticker tickpw1 ticker@example.com Ticker 1
t_login ticker tickpw1
TQ="WHERE username = 'ticker'"
tk_is() {  # tk_is EXPR EXPECTED (an SQL expression on the users row)
	local got; got=$(t_sql "SELECT $1 FROM users $TQ")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$1: expected '$2', got '$got'"; fi
}
t_get /changepassword
t_post /__tick "csrf=$(t_csrf)"; expect_status 404
t_post /__tick ""; expect_status 403
t_post /__tick "csrf=$(t_csrf)" -H 'X-DK-Tick: 1'; expect_status 404
t_get /__tick; expect_status 405

t_section "tick: the turn's timer on the fight page"
t_sql "UPDATE users SET currenthp = 900, base_maxhp = 900, dexterity = 0, latitude = 3, longitude = 3 $TQ"
t_fight_new ticker
TICK0=$((T_NOW / 10))
tk_is "(SELECT tick || ':' || deadline FROM fights f WHERE f.user_id = users.id)" "$TICK0:$((TICK0 + 3))"
expect_body "<div class=\"fight-clock\" data-r=\"fight-clock\" data-turn-ends=\"$(((TICK0 + 3) * 10))\" data-now=\"$T_NOW\" aria-hidden=\"true\"></div>"
T_NOW=$((T_NOW + 7)) t_get /fight; expect_body "data-turn-ends=\"$(((TICK0 + 3) * 10))\" data-now=\"$((T_NOW + 7))\""
expect_body 'name="guard" value="Guard" title="Guard" aria-label="Guard" aria-keyshortcuts="9"'
# the timer is a region of its own: a live refresh brings it alone
t_get /fight; t_live_page
T_NOW=$((T_NOW + 8)) t_live GET /fight
w_has region fight-clock; w_lacks region main
t_get /static/js/fight.js; expect_body 'data-turn-ends'

t_section "tick: a turn that runs out is a Guard, told to the player's pages"
t_get /fight; ROUND=$(t_sql "SELECT $T_ROUND FROM users $TQ"); HP=$(t_sql "SELECT currenthp FROM users $TQ")
live_open tk
# GETs show the fight as the tick left it: the time passing doesn't play the turn
T_NOW=$((T_NOW + 60)) t_get /fight; expect_no_body 'You hesitate'; tk_is "$T_ROUND" "$ROUND"
t_tick 20; expect_body "tick $((TICK0 + 2)): "; tk_is "$T_ROUND" "$ROUND"
t_tick
tk_is "$T_ROUND" "$((ROUND + 1))"
tk_is "(SELECT deadline FROM fights f WHERE f.user_id = users.id)" "$((TICK0 + 6))"
live_has tk 'event: stale'; live_has tk 'data: {"tab":""}'
t_get /fight; expect_body 'class="fight-yourturn">You hesitate, and raise your guard.'
expect_body 'class="fight-monsterturn">The monster attacks you for'
[ "$(t_sql "SELECT currenthp FROM users $TQ")" -lt "$HP" ] && t_ok || t_fail "the monster's attack hurt"
# the next 30 s: another guard, its lines after the first's (the log is the lines since the
# player's last command)
t_tick 30
t_get /fight; [ "$(grep -o 'You hesitate, and raise your guard.' "$BODY" | wc -l)" = 2 ] && t_ok || t_fail "two guards in the log"
tk_is "$T_ROUND" "$((ROUND + 2))"
# the player's command: the log starts again from it
t_round "csrf=$(t_csrf)&fight=Fight&round=$((ROUND + 2))"
expect_body 'You attack the monster for'; expect_no_body 'You hesitate'
live_close tk
t_fight_clear ticker; t_sql "UPDATE users SET currentaction = 'In Town' $TQ"

t_section "tick: a fight that ends on the clock"
t_sql "UPDATE users SET currenthp = 1, latitude = 3, longitude = 3 $TQ"
t_fight ticker 151 30000
t_get /fight; t_round "csrf=$(t_csrf)&continue=Continue"   # (its first POST puts it on the clock)
live_open tk2
for _ in 1 2 3 4 5 6; do
	t_tick 30
	[ "$(t_sql "SELECT currentaction FROM users $TQ")" = "In Town" ] && break
done
tk_is currentaction "In Town"
live_has tk2 'event: stale'
t_get /fight; expect_body '<b>You have died.</b>'; expect_body 'You hesitate, and raise your guard.'
live_close tk2

t_section "tick: the weather pushed to an open page"
# on the storms' road, the first minute the weather changes (as tests/e2e/weather.sh finds it)
t_sql "UPDATE users SET currentaction = 'Exploring', currenthp = 900, latitude = 100, longitude = -100 $TQ"
t_fight_clear ticker
TW=$((T_NOW - T_NOW % 60 + 60)); TN=
for i in $(seq 0 90); do
	T_NOW=$((TW + 60 * i)) t_get /
	if grep -q 'class="explore-change"' "$BODY"; then TN=$((TW + 60 * i)); break; fi
done
[ -n "$TN" ] && t_ok || t_fail "no change in 90 minutes on the storms' road"
live_open tk3
# a tick between two steps of the weather tells nobody; the one that begins the changed step does
T_NOW=$((TN - 20)); t_tick; live_lacks tk3 'event: stale'
t_tick; t_tick; live_has tk3 'event: stale'
live_close tk3
t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 $TQ"
fi
