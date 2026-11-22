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
expect_row '<td style="width: 12%">12 HP</td><td style="width: 20%">Weak to Fire (+50%)</td><td style="width: 28%">18%: in The Hambry Weald, on open ground, with Scorching Heat or Sunshine, not with Blizzard, Downpour, Night, Rain, Snow or Thunderstorm<br>9%: in The Hambry Weald, on Hills, Lake or Pond, with Scorching Heat or Sunshine, not with Blizzard, Downpour, Night, Rain, Snow or Thunderstorm<br>12%: with Woods, not with Blizzard, Downpour, Night, Rain, Snow or Thunderstorm<br>6%: in The Hambry Weald, on Hills, Lake or Pond, not with Blizzard, Downpour, Night, Rain, Snow or Thunderstorm</td>'
expect_row 'Steam Vent<br><span class="small">A crack in the cinders spitting steam.'
expect_row '<td style="width: 12%">20 HP + 3 per level</td><td style="width: 20%">Resists Physical (50%)<br>Immune to Fire<br>Resists Water (90%)<br>Weak to Earth (+50%)</td><td style="width: 28%">15%: with Cinders</td>'
expect_row '<td style="width: 28%">14%: in The Greymoor, with Fog<br>8%: in The Greymoor</td>'
expect_row '<td style="width: 28%">25%: in The Storm Barrens, The Thornbog, The Greymoor or The Hambry Weald, in wind 3 or more<br>6%: in The Storm Barrens or The Greymoor</td>'
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
ob_object() {  # ob_object ID KEY HP [DATA [OVER]]: an object on the field of objector's fight
	t_sql "INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, hp, maxhp, data, level, over)
		SELECT u.id, $1, 'object', 'object', i.id, $3, $3, '${4:-}', 10, '${5:-player}' FROM users u, interactables i
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
expect_body '<b class="tip-term" data-tip tabindex="0">Beehive<template class="tip"><div class="tip-title"><img class="tip-icon" src="/static/images/interactables/beehive.png" width="20" height="20" alt="">Beehive</div><div class="tip-meta">12 HP</div><ul class="tip-lines"><li>Weak to Fire (+50%)</li><li>Appears by itself 18%: in The Hambry Weald'
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

t_section "objects: the Explosive Barrel item, lit by a fire's blow, to its blast"
# the item (a level 21 player: a blast of 3 + 5 * 21 // 4 = 29, rolled from 23 to 29, fire) rolls a barrel onto the
# field; a fire blade's blow lights it; two ticks later it blasts everyone, the player too. Monsters here are a
# Red Slime with 1000 HP (it resists fire by half) that never lands a bite: dexterity 22500 dodges everything.
ob_slime() { t_sql "UPDATE fight_combatants SET maxhp = 1000 WHERE id = 2 AND user_id = (SELECT id FROM users $OQ)"; }
ob_new() {  # ob_new [HP]: a fresh fight against the big Red Slime, the player strong (HP, 3000 by default) and without gear
	ob_sql "UPDATE users SET currenthp = ${1:-3000}, base_maxhp = 3000, currentmp = 500, base_maxmp = 500, dexterity = 22500, base_attack = 30"
	t_items_clear objector; t_calm objector
	t_fight objector 2 1000; ob_slime
}
ob_round() { t_sql "SELECT $T_ROUND FROM users $OQ"; }
ob_attack() {  # ob_attack ID: the player attacks combatant ID
	t_get /fight; t_round "csrf=$(t_csrf)&round=$(ob_round)&fight=Fight&target=$1"
}
ob_cast() {  # ob_cast SPELL_KEY ID
	t_get /fight; t_round "csrf=$(t_csrf)&round=$(ob_round)&spell=Spell&userspell=$(t_sql "SELECT id FROM spells WHERE key = '$1'")&target=$2"
}
ob_ticks() {  # ob_ticks N: N ticks of the clock, what the fight page said after each kept in OB_LOG
	OB_LOG=; local i
	for i in $(seq 1 "$1"); do t_tick; t_get /fight; OB_LOG="$OB_LOG $(t_text | tr -s " \n\t" " ")"; done
}
ob_logged() { case "$OB_LOG" in *"$1"*) t_ok ;; *) t_fail "the ticks said no '$1': $OB_LOG" ;; esac; }
ob_has() {  # ob_has TEXT: the statuses (every combatant's) have it
	case "$(t_sql "SELECT $T_STATUSES FROM users $OQ")" in *"$1"*) t_ok ;; *) t_fail "statuses: no '$1' in '$(t_sql "SELECT $T_STATUSES FROM users $OQ")'" ;; esac
}
ob_hasnt() {
	case "$(t_sql "SELECT $T_STATUSES FROM users $OQ")" in *"$1"*) t_fail "statuses: '$1' in '$(t_sql "SELECT $T_STATUSES FROM users $OQ")'" ;; *) t_ok ;; esac
}
OB_SLIME_HP="(SELECT hp FROM fight_combatants c WHERE c.user_id = users.id AND c.id = 2)"
ob_new
ob_sql "UPDATE users SET level = 21"
t_give objector explosive_barrel 2; t_give objector cinder_blade 1 weapon
t_get /fight
OB_BARREL=$(t_sql "SELECT id FROM items WHERE key = 'explosive_barrel'")
t_round "csrf=$(t_csrf)&round=2&item=Use+Item&useritem=$OB_BARREL"
expect_text 'You roll the Explosive Barrel onto the field.'; expect_text 'A barrel of blasting powder stands on the field'
ob_is "(SELECT replace(data, char(10), ';') FROM fight_combatants c WHERE c.user_id = users.id AND c.id = 3)" 'blast=i:29'
ob_is "$T_ITEMS" "explosive_barrel,cinder_blade@weapon"
expect_body 'data-fighter="3"'
ob_attack 3
expect_text "The barrel&#39;s fuse sputters alight!"; ob_has "object:fuse/2"
t_tick; ob_has "object:fuse"   # (the first tick puts the fight on the clock)
t_tick; t_tick
ob_is "coalesce($OB_OBJECT_HP, 'gone')" gone
ob_is "$OB_SLIME_HP BETWEEN 986 AND 989" 1   # a blast of 23 to 29, 11 to 14 through the slime's fire resistance
ob_is "currenthp BETWEEN 2971 AND 2977" 1
t_get /fight; expect_text 'The barrel goes up!'; expect_text 'The blast hits you for'
# no room: three objects on the field and the item is refused, and not used up
ob_new
t_give objector explosive_barrel 1
ob_object 3 beehive 12; ob_object 4 beehive 12; ob_object 5 beehive 12
t_get /fight
t_round "csrf=$(t_csrf)&round=2&item=Use+Item&useritem=$OB_BARREL"
expect_text 'There is no room for another object on the field.'
ob_is "$T_ITEMS" "explosive_barrel"

t_section "objects: the gas pocket bursts or flashes"
# a blow that isn't fire: it bursts, everyone is poisoned and the miasma comes over the field
ob_new
ob_object 3 gas_pocket 1 'age=i:0'
ob_attack 3
expect_text 'The pocket bursts in a green stink!'; expect_text 'The stink poisons you.'; expect_text 'The stink poisons the Red Slime.'
ob_has "player:poison/3,enemy:poison/3"
ob_is "$OB_DATA LIKE '%field_aura=s:miasma%'" 1
# a fire's blow: it flashes, the player burns (the slime wards burning off) and the barrel beside it catches
ob_new
t_give objector cinder_blade 1 weapon
ob_object 3 gas_pocket 1 'age=i:0'; ob_object 4 explosive_barrel 20 'blast=i:5'
ob_attack 3
expect_text 'The gas catches with a soft whump'; expect_text 'The flash sets you alight.'
ob_has "player:burning/4"; ob_has "object:fuse/2"; ob_hasnt "enemy:burning"
ob_is "$OB_DATA LIKE '%field_aura%'" 0

t_section "objects: the steam vent scalds, and a water spell quenches it"
ob_new
t_spells objector "$(t_sql "SELECT id FROM spells WHERE key = 'torrent'")"
ob_object 3 steam_vent 35 't=i:0'
ob_cast torrent 3
expect_text 'The vent roars, quenched into one great eruption!'
ob_is "$OB_SLIME_HP" 700          # 30% of its 1000, as water
ob_is "currenthp" 2100              # 30% of 3000
ob_ticks 4
ob_logged 'The vent hisses and spits steam.'; ob_logged 'The vent scalds'

t_section "objects: the standing stone topples"
ob_new
ob_object 3 standing_stone 1 '' player
ob_attack 3
expect_text 'The standing stone topples with a groan'; expect_text 'It crushes you for 1200 damage.'; expect_text 'You are stunned.'
ob_is "currenthp" 1800; ob_has "player:sleep"
ob_new
ob_object 3 standing_stone 1 '' enemy
ob_attack 3
expect_text 'It crushes the Red Slime for 400 damage.'; ob_is "$OB_SLIME_HP" 600; ob_has "enemy:sleep"

t_section "objects: the dead tree falls on the one it is felled away from, and in a gale by itself"
ob_new
ob_object 3 dead_tree 1
ob_attack 3
expect_text 'The dead tree crashes down on the Red Slime for 250 damage.'
ob_is "$OB_SLIME_HP" 750; ob_hasnt "burning"
# the gale (a spell's blizzard: wind 3), the tree falling every tick (its `gale` roll 1 in 1), and a banner torn down
ob_new
t_sql "UPDATE fights SET data = data || char(10) || 'field_sky=s:blizzard' || char(10) || 'field_sky_ticks=i:30' || char(10) || 'field_sky_tick=i:0' WHERE user_id = (SELECT id FROM users $OQ)"
ob_object 3 dead_tree 20 'gale=i:1' player
ob_object 4 war_banner 15 '' enemy
ob_ticks 2
ob_logged 'The gale wrenches the dead tree over!'; ob_logged 'The dead tree crashes down on'
ob_logged 'The wind tears the banner down.'
ob_is "(SELECT count(*) FROM fight_combatants c WHERE c.user_id = users.id AND c.side = 'object')" 0

t_section "objects: the tide pool soaks everyone and puts the fires out"
ob_new
ob_object 3 tide_pool 1; ob_object 4 explosive_barrel 20 'blast=i:5'
t_fight_status objector 4 fuse '' 2
t_fight_status objector 1 burning 'amount=i:3' 3
ob_has "player:burning/3"; ob_has "object:fuse/2"
ob_attack 3
expect_text 'The pool splashes over the field'; expect_text 'The water puts the fire out on you.'
ob_is "$T_STATUSES" "player:soaked/3,enemy:soaked/3,object:soaked/3"

t_section "objects: the war banner rallies its side until it falls"
ob_new
ob_object 3 war_banner 1 '' enemy
t_tick; t_tick
ob_has "enemy:rallied/2"; ob_hasnt "player:rallied"
ob_attack 3
expect_text 'The banner falls.'
ob_is "coalesce($OB_OBJECT_HP, 'gone')" gone

t_section "objects: the campfire sparks a barrel into a blast"
ob_new
ob_object 3 campfire 8 'chance=i:1'; ob_object 4 explosive_barrel 20 'blast=i:30'
ob_ticks 2
ob_logged 'A spark from the campfire lands on the Explosive Barrel.'; ob_logged "The barrel&#39;s fuse sputters alight!"
ob_ticks 3
ob_is "(SELECT count(*) FROM fight_combatants c WHERE c.user_id = users.id AND c.id = 4)" 0
ob_logged 'The barrel goes up!'

t_section "objects: the water cactus heals the lowest share"
ob_new 1000
ob_object 3 water_cactus 1
ob_attack 3
expect_text 'The cactus splits and the cold water runs over you: you recover 750 hit points.'
ob_is "currenthp" 1750

t_section "objects: the admin page"
t_jar objectsadmin
t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin; expect_body '<a href="/admin/interactables">Objects</a>'
t_get /admin/interactables; expect_status 200; expect_body '<h1 class="admin-heading">Objects</h1>'
HIVE_ID=$(t_sql "SELECT id FROM interactables WHERE key = 'beehive'")
expect_body "<a href=\"/admin/interactables/$HIVE_ID\">Beehive</a>"
t_get "/admin/interactables/$HIVE_ID"; expect_status 200
expect_body 'name="hp"'; expect_body 'name="spawn.1.chance"'; expect_body 'name="resist.fire"'; expect_body 'name="data.pct"'
expect_body 'name="spawn.3.chance"'
t_form_submit "/admin/interactables/$HIVE_ID" "spawn.3.chance=20" "hp=15"
expect_redirect "/admin/interactables/$HIVE_ID\\?saved=1"
[ "$(t_sql "SELECT hp || '|' || (spawn LIKE '%3.chance=20%3.fields=forest%') || '|' || (spawn LIKE '%1.chance=18%') FROM interactables WHERE key = 'beehive'")" = "15|1|1" ] \
	&& t_ok || t_fail "the overrides apply: $(t_sql "SELECT hp || '|' || replace(spawn, char(10), ';') FROM interactables WHERE key = 'beehive'")"
t_get /help/objects; expect_row '<td style="width: 12%">15 HP</td>'; expect_row '20%: with Woods'
t_post "/admin/interactables/$HIVE_ID/reset" "csrf=$(t_csrf)&field=*"
[ "$(t_sql "SELECT hp FROM interactables WHERE key = 'beehive'")" = 12 ] && t_ok || t_fail "reset to the file"

t_section "objects: cleanup"
t_fight_clear objector
t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 $OQ"

fi
