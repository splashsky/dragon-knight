# tests/e2e/weather.sh :: the weather (docs/APP.md "Clock and weather", lib/weather.lua),
# the clock pinned per request (T_NOW: X-Test-Now). The Location box shows the weather and
# the time of day, with a tooltip, in a region of its own; in the tick the weather changes
# the exploring page says what changed, and a live answer brings the weather's regions and
# nothing else. Sourced by tests/run.sh.

t_section "weather: the Location box"
t_jar weather; t_reset_jar
t_register weatheruser weatherpw1 weather@example.com Weatheruser 2
t_login weatheruser weatherpw1
WQ="WHERE username = 'weatheruser'"
we_box() { grep -o '<div class="loc-weather" data-r="weather">.*' "$BODY" | head -n1; }
t_get /; expect_status 200
expect_body '<div class="loc-weather" data-r="weather">'
we_box | grep -qE 'class="wx wx-[a-z]+ wx-(dawn|day|dusk|night)"' && t_ok || t_fail "the sky's icon: $(we_box)"
we_box | grep -qE 'data-tip tabindex="0" title="[^"]+">[A-Z][a-z ]+<template class="tip"><div class="tip-title">' \
	&& t_ok || t_fail "the sky's name with a tooltip: $(we_box)"
we_box | grep -qE '<span class="loc-time">(Dawn|Day|Dusk|Night)</span>' && t_ok || t_fail "the time of day: $(we_box)"
# the same all through the weather's step (a tick: it moves every 10 s)
WS=$((T_NOW - T_NOW % 10)); WB=$(we_box)
T_NOW=$((WS + 9)) t_get /; [ "$(we_box)" = "$WB" ] && t_ok || t_fail "the same all through a tick: $(we_box)"
# the fight page shows it too
t_fight weatheruser 1 10
t_get /fight; expect_body '<div class="loc-weather" data-r="weather">'
t_fight_clear weatheruser

t_section "weather: a change, on the page and live"
# on the storms' road, the first tick the weather changes after one it didn't
t_sql "UPDATE users SET currentaction = 'Exploring', latitude = 100, longitude = -100 $WQ"
WN=; we_before=1
for i in $(seq 0 360); do
	T_NOW=$((WS + 10 * i)) t_get /
	if grep -q 'class="explore-change"' "$BODY"; then
		[ "$we_before" = 0 ] && { WN=$((WS + 10 * i)); break; }
	else
		we_before=0
	fi
done
[ -n "$WN" ] && t_ok || t_fail "no change in an hour on the storms' road"
expect_body '<div class="explore-weather" data-r="explore-weather"><p class="explore-change">'
# live: the page in the tick before, then in the tick of the change: the weather's regions
# alone
T_NOW=$((WN - 1)) t_get /; expect_no_body 'class="explore-change"'
t_live_page
T_NOW=$((WN - 1)) t_live GET /
[ -z "$(w_ops | grep '^region' | grep -v '^region foot-time ')" ] && t_ok || t_fail "before the change: $(w_ops | tr '\n' ';')"
T_NOW=$WN t_live GET /
w_has region weather; w_has region explore-weather
w_lacks region loc; w_lacks region left; w_lacks region main; w_lacks region root
w_payload region explore-weather | grep -q 'class="explore-change"' && t_ok || t_fail "the change line: $(w_payload region explore-weather)"
t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 $WQ"
