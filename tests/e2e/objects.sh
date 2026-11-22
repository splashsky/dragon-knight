# tests/e2e/objects.sh :: the objects of the battlefield and the target picker (docs/APP.md
# "Interactables and targeting"): /help/objects, the fight page's object cards and the radio
# group `target` in the command form (no JavaScript needed), POST /fight's target (kept with
# the fight, a wrong one ignored), an object as the target, a lit fuse burning down on the
# server's tick, and /admin/interactables. Sourced by tests/run.sh.
if ! t_has_sql; then
	t_section "objects (skipped: needs sqlite3 or python3)"
else

t_section "objects: the help page"
t_jar objects; t_reset_jar
t_get /help; expect_body '<a href="/help/objects">Click here</a> for the Objects spoiler page'
expect_body '<li><a href="#objects">Spoilers: Objects</a></li>'
t_get /help/objects; expect_status 200; expect_body 'Help: Objects'
[ "$(grep -c '<tr><td style="width: 40%">' "$BODY")" = "$(ls app/content/interactables | wc -l)" ] && t_ok || t_fail "every object listed"
expect_row 'Beehive<br><span class="small">A skep full of bees in the branches.'
expect_row '<td style="width: 12%">12 HP</td><td style="width: 20%">Weak to Fire (+50%)</td><td style="width: 28%">12%: with Woods, not with Blizzard, Downpour, Night, Rain, Snow or Thunderstorm</td>'
expect_row '<td style="width: 12%">20 HP</td><td style="width: 20%">Resists Fire (90%)</td><td style="width: 28%">7%: in The Diggings, on open ground, not with Blizzard, Downpour, Rain, Shallows or Thunderstorm</td>'

t_section "objects: the fight page and the target picker"
t_register objector objectpw1 objector@example.com Objector 2
t_login objector objectpw1
OQ="WHERE username = 'objector'"
ob_sql() { t_sql "$1 $OQ"; }
ob_is() {  # ob_is EXPR EXPECTED (an SQL expression on the users row)
	local got; got=$(t_sql "SELECT $1 FROM users $OQ")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$1: expected '$2', got '$got'"; fi
}
ob_object() {  # ob_object ID KEY HP [DATA]: an object on the field of objector's fight
	t_sql "INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, hp, maxhp, data, level, over)
		SELECT u.id, $1, 'object', 'object', i.id, $3, $3, '${4:-}', 10, 'player' FROM users u, interactables i
		WHERE u.username = 'objector' AND i.key = '$2'"
}
OB_OBJECT_HP="(SELECT hp FROM fight_combatants c WHERE c.user_id = users.id AND c.id = 3)"
OB_DATA="(SELECT replace(data, char(10), ';') FROM fights f WHERE f.user_id = users.id)"
t_calm objector
ob_sql "UPDATE users SET currenthp = 3000, base_maxhp = 3000, dexterity = 0, base_attack = 30"
# one monster, nothing else: no choice, the page as before (no radio buttons)
t_fight objector 2 500
t_get /fight; expect_status 200
expect_body '<div class="fight-foe">'; expect_no_body 'name="target"'
expect_body '<form class="fight-command" id="fight-command" action="/fight" method="post" data-fight>'
# a beehive on the field: its card (name with its tooltip, HP, the side it hangs over) and
# the radio group in the command form, the monster checked (the default target)
ob_object 3 beehive 12
t_get /fight; expect_status 200
expect_body '<div class="fight-foe fight-targetable fight-chosen" data-target="2">'
expect_body '<input class="fight-target-radio" type="radio" name="target" value="2" form="fight-command" aria-label="Target: Red Slime" checked>'
expect_body '<p class="fight-combatant fight-object fight-targetable" data-fighter="3" data-stat="hp" data-value="12" data-max="12" data-target="3"><input class="fight-target-radio" type="radio" name="target" value="3" form="fight-command" aria-label="Target: Beehive">'
expect_body '<b class="tip-term" data-tip tabindex="0">Beehive<template class="tip"><div class="tip-title">Beehive</div><div class="tip-meta">12 HP</div><ul class="tip-lines"><li>Weak to Fire (+50%)</li><li>Appears by itself 12%: with Woods'
expect_body ': 12 / 12 HP <span class="light">(over you)</span></p>'
# the form without JavaScript: the radio button sends the target, the attack goes at it
t_round "csrf=$(t_csrf)&round=2&fight=Fight&target=3"; expect_status 200
expect_body 'You attack the Beehive for'
ob_is "$OB_DATA LIKE '%target=i:3%'" 1
ob_is "$T_MONSTER_HP" 500
# knocked down (it has 12 HP: one or two blows): hit it until it falls
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ -z "$(t_sql "SELECT $OB_OBJECT_HP FROM users $OQ")" ] && break
	expect_body 'class="fight-combatant fight-object fight-targetable fight-chosen" data-fighter="3"'
	t_round "csrf=$(t_csrf)&round=$(t_sql "SELECT $T_ROUND FROM users $OQ")&fight=Fight"
done
ob_is "coalesce($OB_OBJECT_HP, 'gone')" gone
expect_text 'The bees swarm you!'
ob_is "$T_STATUSES" "player:swarm/5"
# the target is the monster again (the choice stays in the data, for nothing)
expect_no_body 'name="target"'; ob_is "$T_MONSTER_HP < 500" 0
t_round "csrf=$(t_csrf)&round=$(t_sql "SELECT $T_ROUND FROM users $OQ")&fight=Fight"
# (the blow went at the monster: it hurt it, or the monster dodged it, 1 in 200 at armor 1)
{ [ "$(t_sql "SELECT $T_MONSTER_HP < 500 FROM users $OQ")" = 1 ] || grep -q 'The monster is dodging' "$BODY"; } && t_ok \
	|| t_fail "the attack after the hive fell went at the monster"
# a target that isn't one (the player, nobody) is ignored
t_fight objector 2 500
ob_object 3 beehive 12
t_get /fight
t_round "csrf=$(t_csrf)&round=2&guard=Guard&target=1"; ob_is "$OB_DATA LIKE '%target=%'" 0
t_round "csrf=$(t_csrf)&round=3&guard=Guard&target=99"; ob_is "$OB_DATA LIKE '%target=%'" 0
t_round "csrf=$(t_csrf)&round=4&guard=Guard&target=x"; ob_is "$OB_DATA LIKE '%target=%'" 0
# a chosen target stays chosen on the page; a stale form doesn't change it
t_round "csrf=$(t_csrf)&round=5&guard=Guard&target=3"; ob_is "$OB_DATA LIKE '%target=i:3%'" 1
expect_body 'value="3" form="fight-command" aria-label="Target: Beehive" checked>'
t_round "csrf=$(t_csrf)&round=5&guard=Guard&target=2"; expect_body 'fight-stale'; ob_is "$OB_DATA LIKE '%target=i:3%'" 1

t_section "objects: a lit fuse on the server's tick"
# a barrel with a lit fuse (one tick left): the tick plays it down, the barrel goes up,
# everyone takes the blast; the fight's log says it
ob_sql "UPDATE users SET currenthp = 3000"
t_fight objector 2 500
ob_object 3 explosive_barrel 20 'blast=i:30'
t_fight_status objector 3 fuse '' 1
t_tick; t_tick   # (the first puts the fight on the clock, the second plays a tick)
ob_is "coalesce($OB_OBJECT_HP, 'gone')" gone
ob_is "$T_MONSTER_HP BETWEEN 485 AND 488" 1   # (the Red Slime resists fire: 50%)
ob_is "currenthp BETWEEN 2970 AND 2976" 1
t_get /fight; expect_text 'The barrel goes up!'; expect_text 'The blast hits you for'
expect_no_body 'data-fighter="3"'

t_section "objects: the admin page"
t_jar objectsadmin
t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin; expect_body '<a href="/admin/interactables">Objects</a>'
t_get /admin/interactables; expect_status 200; expect_body '<h1 class="admin-heading">Objects</h1>'
HIVE_ID=$(t_sql "SELECT id FROM interactables WHERE key = 'beehive'")
expect_body "<a href=\"/admin/interactables/$HIVE_ID\">Beehive</a>"
t_get "/admin/interactables/$HIVE_ID"; expect_status 200
expect_body 'name="hp"'; expect_body 'name="spawn.1.chance"'; expect_body 'name="resist.fire"'; expect_body 'name="data.pct"'
t_form_submit "/admin/interactables/$HIVE_ID" "spawn.1.chance=20" "hp=15"
expect_redirect "/admin/interactables/$HIVE_ID\\?saved=1"
[ "$(t_sql "SELECT hp || '|' || spawn FROM interactables WHERE key = 'beehive'")" = "15|1.chance=20
1.fields=forest
1.unless=blizzard,downpour,night,rain,snow,thunderstorm" ] && t_ok || t_fail "the overrides apply"
t_get /help/objects; expect_row '<td style="width: 12%">15 HP</td>'; expect_row '20%: with Woods'
t_post "/admin/interactables/$HIVE_ID/reset" "csrf=$(t_csrf)&field=*"
[ "$(t_sql "SELECT hp FROM interactables WHERE key = 'beehive'")" = 12 ] && t_ok || t_fail "reset to the file"

t_section "objects: cleanup"
t_fight_clear objector
t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 $OQ"

fi
