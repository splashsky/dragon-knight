# tests/e2e/fields.sh :: the battlefield's fields (docs/APP.md "Fields", fight/fields.lua):
# /help/fields, the fight page's Battlefield line (its region, the tooltips), the weather's
# fields following the clock in a fight (t_tick across nightfall), a live round's field
# events, and the admin page. Sourced by tests/run.sh.
if ! t_has_sql || ! command -v python3 >/dev/null; then
	t_section "fields (skipped: needs sqlite3 or python3, and python3)"
else

t_section "fields: the help page"
t_jar fields; t_reset_jar
t_get /help; expect_body '<a href="/help/fields">Click here</a> for the Fields spoiler page'
t_get /help/fields; expect_status 200; expect_body 'Help: Fields'
FI_COUNT=$(ls app/content/fields | wc -l)
[ "$(grep -c '<tr><td style="width: 45%">' "$BODY")" = "$FI_COUNT" ] && t_ok || t_fail "every field listed"
expect_row '<img class="help-icon" src="/static/images/fields/rain.png" width="24" height="24" alt="">Rain<br>'
expect_row '<td style="width: 15%">Sky</td><td style="width: 40%">Fire damage -40%<br>Lightning damage +25%<br>Water damage +15%<br>Burning can&#39;t take hold<br>Dexterity -10%</td>'
expect_row 'Night<br><span class="small">Darkness over the field: shadow is stronger, holy light weaker, and sleep comes deeper.</span></td><td style="width: 15%">Time of day</td>'
expect_row '<td style="width: 15%">Aura</td><td style="width: 40%">Holy damage +25%<br>Shadow damage -25%</td>'

t_section "fields: the battlefield on the fight page"
t_register fielder fieldpw1 fielder@example.com Fielder 2
t_login fielder fieldpw1
FQ="WHERE username = 'fielder'"
fi_data() { t_sql "SELECT replace(data, char(10), ';') FROM fights WHERE user_id = (SELECT id FROM users $FQ)"; }
t_sql "UPDATE users SET currenthp = 5000, base_maxhp = 5000, dexterity = 0, latitude = 3, longitude = 3 $FQ"
# by day: no night; at night (the day's last 30 minutes: lib/clock.lua) the night's field
FI_DAY=$((T_START - T_START % 7200))
T_NOW=$((FI_DAY + 2000)) t_fight_new fielder
expect_body 'data-r="battlefield" data-battlefield'; expect_no_body 'data-field="night"'
case "$(fi_data)" in *field_time=*) t_fail "no night by day: $(fi_data)" ;; *) t_ok ;; esac
T_NOW=$((FI_DAY + 6000)) t_fight_new fielder
case "$(fi_data)" in *"field_time=s:night"*) t_ok ;; *) t_fail "the night's field kept with the fight: $(fi_data)" ;; esac
T_NOW=$((FI_DAY + 6000)) t_get /fight
expect_body '<p class="fight-battlefield" data-r="battlefield" data-battlefield><span class="fight-battlefield-label">Battlefield:</span>'
expect_body '<span class="fight-field tip-term" data-field="night" data-tip tabindex="0">Night<template class="tip"><div class="tip-title">Night</div><div class="tip-meta">Time of day</div><ul class="tip-lines"><li>Holy damage -15%</li><li>Shadow damage +25%</li><li>Sleep chance +30%</li></ul><div class="tip-body"><p>Darkness over the field'
# a field with an icon has it on the line and in its tooltip
t_sql "UPDATE fights SET data = data || char(10) || 'field_aura=s:consecrated' WHERE user_id = (SELECT id FROM users $FQ)"
T_NOW=$((FI_DAY + 6000)) t_get /fight
expect_body 'data-field="consecrated" data-tip tabindex="0"><img class="fight-field-icon" src="/static/images/fields/consecrated.png" width="18" height="18" alt="">Consecrated Ground<template class="tip"><div class="tip-title"><img class="tip-icon" src="/static/images/fields/consecrated.png"'

t_section "fields: the weather moves them in a fight"
# at dusk, 20 seconds before nightfall; the clock's ticks bring the night, with its line
FI_DUSK=$((FI_DAY + 5400 - 20))
T_NOW=$FI_DUSK
t_fight_new fielder
case "$(fi_data)" in *field_time=*) t_fail "no night at dusk: $(fi_data)" ;; *) t_ok ;; esac
expect_no_body 'data-field="night"'
t_tick 30
case "$(fi_data)" in *"field_time=s:night"*) t_ok ;; *) t_fail "nightfall in the fight: $(fi_data)" ;; esac
t_get /fight; expect_body 'data-field="night"'
grep -qE 'class="fight-roundend">[^<]+' "$BODY" && t_ok || t_fail "nightfall said in the fight's log"
# a GET shows the fight as the tick left it: it changes nothing
FI_BEFORE=$(fi_data); T_NOW=$((T_NOW + 600)) t_get /fight; [ "$(fi_data)" = "$FI_BEFORE" ] && t_ok || t_fail "a GET moved the fields"

t_section "fields: a live round's events"
# a command just after nightfall catches the fight up first: its events say the night came
T_NOW=$FI_DUSK
t_fight_new fielder
ROUND=$(t_sql "SELECT $T_ROUND FROM users $FQ")
T_NOW=$((FI_DUSK + 25))
t_live_forget; t_live POST /fight "fight=Fight&round=$ROUND"
expect_status 200
FI_EV=$(python3 - "$BODY" "$ROOT/tests" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[2])
from wire import frames
for op, args, payload in frames(sys.argv[1]):
	if op == "events" and args == ["fight"]:
		for e in json.loads(payload.decode("utf-8")):
			for x in e.get("field", []):
				print("%s:%s:%s:%s:%s" % (e["type"], e["part"], x["change"], x["key"], x["name"]))
PY
)
case "$FI_EV" in *"field:ending:add:night:Night"*) t_ok ;; *) t_fail "the night's field event: [$FI_EV]" ;; esac
t_get /static/js/fight.js; expect_body 'fight-field-new'
t_fight_clear fielder; t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 $FQ"
T_NOW=$T_START

t_section "fields: the admin page"
t_jar admin; t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin; expect_body '<a href="/admin/fields">Fields</a>'
RAIN=$(t_sql "SELECT id FROM fields WHERE key = 'rain'")
t_get /admin/fields; expect_status 200; expect_body "<a href=\"/admin/fields/$RAIN\">Rain</a>"
expect_body "fields: $FI_COUNT files, $FI_COUNT in the database (0 retired), 0 overrides."
t_get "/admin/fields/$RAIN"; expect_body 'Edit Field: Rain'; expect_body 'app/content/fields/rain.lua'
expect_body 'name="damage.fire" size="6" value="-25"'; expect_body 'name="damage.holy" size="6" value="0"'
expect_body 'name="statuses.burning.ticks" size="6" value="-1"'; expect_body 'name="messages.begins" size="70"'
t_form_submit "/admin/fields/$RAIN" "description=$(t_sql "SELECT description FROM fields WHERE key = 'rain'")" \
	damage.fire=-50 stats.dexterity=-5
expect_redirect "/admin/fields/$RAIN\\?saved=1"
[ "$(t_sql "SELECT damage || '|' || stats FROM fields WHERE key = 'rain'")" = "fire=-50,lightning=15,water=15|dexterity=-5" ] \
	&& t_ok || t_fail "field override not applied: $(t_sql "SELECT damage || '|' || stats FROM fields WHERE key = 'rain'")"
t_get /help/fields; expect_body 'Fire damage -50%<br>Lightning damage +15%<br>Water damage +15%<br>Burning lasts 10s less<br>Dexterity -5%'
t_get "/admin/fields/$RAIN"; t_post "/admin/fields/$RAIN/reset" "csrf=$(t_csrf)&field=*"
expect_redirect "/admin/fields/$RAIN\\?saved=1"
[ "$(t_sql "SELECT count(*) FROM content_overrides WHERE kind = 'fields'")" = 0 ] && t_ok || t_fail "field overrides not reset"
[ "$(t_sql "SELECT damage FROM fields WHERE key = 'rain'")" = "fire=-25,lightning=15,water=15" ] && t_ok || t_fail "the file's again"
t_get /admin/fields/999; expect_status 404
fi
