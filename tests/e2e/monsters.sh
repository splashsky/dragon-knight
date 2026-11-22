# tests/e2e/monsters.sh :: monsters as content through HTTP (2.2): the example monsters with
# spells, items, equipment and MP (Goblin Shaman, Bog Witch, Bandit Captain), their stock
# per encounter, uses_mp, elements, resistances, wards and classes, the help page, and
# random encounters never picking monsters that don't roam. The monsters' choices are
# random by weight; the tests make them certain with an attack weight of 0 (an admin
# override) and the fight's state (HP, MP, statuses).
# Sourced by tests/run.sh.
if ! t_has_sql; then
	t_section "monsters (skipped: needs sqlite3 or python3)"
else

t_section "monsters: setup"
t_jar monsters
t_register monsterer monpw1 monsterer@example.com Monsterer 1
t_login monsterer monpw1
MQ="WHERE username = 'monsterer'"
mo_is() {  # mo_is EXPR EXPECTED (an SQL expression on the users row)
	local got; got=$(t_sql "SELECT $1 FROM users $MQ")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$1: expected '$2', got '$got'"; fi
}
mon() { t_sql "SELECT id FROM monsters WHERE key = '$1'"; }
# the outcome of the fight ("", "victory", "death"); with an argument: whether there is one
mo_outcome() {
	if [ -n "${1:-}" ]; then t_sql "SELECT 1 FROM fights WHERE user_id = (SELECT id FROM users $MQ)"
	else t_sql "SELECT coalesce((SELECT outcome FROM fights WHERE user_id = (SELECT id FROM users $MQ)), '')"; fi
}
# the monster (combatant 2) of the fight: a column
MO_ENEMY="(SELECT c.%s FROM fight_combatants c WHERE c.user_id = users.id AND c.id = 2)"
enemy() { printf "$MO_ENEMY" "$1"; }
mo_enemy_set() { t_sql "UPDATE fight_combatants SET $1 WHERE id = 2 AND user_id = (SELECT id FROM users $MQ)"; }
# sturdy and never hit by an attack: dexterity 22500 dodges every one (spells still hurt)
t_sql "UPDATE users SET base_maxhp = 500, currenthp = 500, dexterity = 22500, latitude = 20, longitude = 0 $MQ"
# the example monsters only use spells and items here (the attack: when nothing else is possible)
for key in goblin_shaman bog_witch bandit_captain; do
	t_sql "INSERT INTO content_overrides (kind, key, field, value) VALUES ('monsters', '$key', 'attack_weight', '0')"
done
"$BIN" content sync --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk content sync: $(cat "$T/content.log")"
[ "$(t_sql "SELECT group_concat(attack_weight) FROM monsters WHERE id > 151")" = "0,0,0" ] && t_ok || t_fail "overrides applied"

t_section "monsters: random encounters pick roaming monsters only"
# level band 3-5 at 20N: the Goblin Shaman (level 5) doesn't roam
for _ in $(seq 1 15); do
	t_fight_new monsterer
	t_get /fight; expect_status 200
	[ "$(t_sql "SELECT $T_MONSTER BETWEEN 1 AND 151 FROM users $MQ")" = 1 ] && t_ok || t_fail "picked a monster that doesn't roam"
done

t_section "monsters: the Goblin Shaman's potions (stock 2 per encounter)"
SHAMAN=$(mon goblin_shaman)
t_fight monsterer "$SHAMAN" 10
mo_enemy_set "mp = 0, maxmp = 17"   # no MP for its spells: the potion is all it may use
t_get /fight; CS=$(t_csrf)
expect_body 'You are fighting a <b class="tip-term" data-tip tabindex="0">Goblin Shaman<template class="tip">'; expect_body "Monster's MP: 0"
t_round "csrf=$CS&fight=Fight"
expect_body 'The Goblin Shaman uses the Potion.<br>The Goblin Shaman recovers '   # (it may speak first)
mo_is "$(enemy hp)" 40; mo_is "$(enemy data)" "stock_1=i:1"
mo_enemy_set "hp = 10"
t_round "csrf=$CS&fight=Fight"; expect_body 'The Goblin Shaman uses the Potion.'
mo_is "$(enemy data)" "stock_1=i:0"
mo_enemy_set "hp = 10"
t_round "csrf=$CS&fight=Fight"; expect_no_body 'uses the Potion'
expect_body 'You dodge the monster&#39;s attack.'
# a new encounter: two potions again
t_fight monsterer "$SHAMAN" 10
mo_enemy_set "mp = 0, maxmp = 17"
t_round "csrf=$CS&fight=Fight"; expect_body 'The Goblin Shaman uses the Potion.'
mo_is "$(enemy data)" "stock_1=i:1"

t_section "monsters: the Goblin Shaman casts Hurt (MP)"
t_fight monsterer "$SHAMAN" 40   # full HP: no heal, no potion; 17 MP
t_get /fight; expect_body "Monster's MP: 17"
t_round "csrf=$CS&fight=Fight"
expect_body 'The monster casts Hurt on you for '; expect_body "Monster's MP: 12"
mo_is "$(enemy mp)" 12
hp=$(t_sql "SELECT currenthp FROM users $MQ")
[ "$hp" -ge 485 ] && [ "$hp" -le 488 ] && t_ok || t_fail "Hurt damage: HP $hp"
t_sql "UPDATE users SET currenthp = 500 $MQ"

t_section "monsters: the Bog Witch's spells are free (uses_mp = false)"
WITCH=$(mon bog_witch)
t_fight monsterer "$WITCH" 60
# asleep (for good: a chance of 15 in 15) and poisoned: Pain is all it may cast
t_fight_status monsterer 1 sleep 'chance=i:15'
t_fight_status monsterer 1 poison '' 5
t_get /fight; CS=$(t_csrf); expect_body "Monster's MP: 33"; expect_body 'name="continue"'
# (the blocked turns end at the clock's ticks)
t_round "csrf=$CS&continue=Continue"
for _ in 1 2; do
	t_tick; t_get /fight
	expect_body 'You are still asleep.'; expect_body 'class="fight-monsterturn">The monster casts Pain on you for '
	expect_body "Monster's MP: 33"
done
mo_is "$(enemy mp)" 33
# awake and cured: Sleep or Poison (or Pain), still free
t_sql "DELETE FROM fight_statuses WHERE user_id = (SELECT id FROM users $MQ)"
t_sql "UPDATE users SET currenthp = 500 $MQ"
t_round "csrf=$CS&fight=Fight"
if grep -qF 'The Bog Witch casts Sleep.<br>You fall asleep.' "$BODY"; then mo_is "$T_STATUSES" "player:sleep"
elif grep -qF 'The monster casts Poison. You are poisoned for 30 seconds.' "$BODY"; then mo_is "$T_STATUSES" "player:poison/3"
else expect_body 'The monster casts Pain on you for '; fi
mo_is "$(enemy mp)" 33
t_sql "UPDATE users SET currenthp = 500 $MQ"

t_section "monsters: the Bandit Captain's gear and frenzy"
BANDIT=$(mon bandit_captain)
t_fight monsterer "$BANDIT" 145
mo_enemy_set "maxhp = 145"   # with its Life Stone
t_get /fight; CS=$(t_csrf); expect_body "Monster's MP: 40"
t_round "csrf=$CS&fight=Fight"
expect_body 'The Bandit Captain casts Craze.<br>The Bandit Captain will deal 10% more damage until the end of this fight.'
expect_body '<b>Bandit Captain</b> <span class="fight-statuses">&mdash; <img class="fight-status-icon" src="/static/images/statuses/uber_damage.png" width="16" height="16" alt="">Damage Up</span>'
mo_is "$(enemy mp)" 30
# buffed already, not hurt enough for its herb: the attack
t_round "csrf=$CS&fight=Fight"; expect_body 'You dodge the monster&#39;s attack.'; expect_no_body 'casts Craze'
mo_enemy_set "hp = 40"
t_round "csrf=$CS&fight=Fight"; expect_body 'The Bandit Captain uses the Herb.<br>The Bandit Captain recovers 30 Hit Points.'
t_fight_clear monsterer
t_sql "UPDATE users SET currentaction = 'Exploring' $MQ"

t_section "monsters: speech"
# the Blue Slime gets a line for each point in the test copy of its file, as likely as a
# moment may be (chance 99: nothing is certain) (fight/speech.lua;
# read when the fight runs, no sync): the fight page shows them as speech, the victory
# page its last words, the death page its last word over the player
MO_SLIME="$T/app/content/monsters/blue_slime.lua"
cp "$MO_SLIME" "$T/blue_slime.lua.orig"
sed -i 's/^}$/\tspeech = { start = { "Blub, {player}!", chance = 99 }, turn = { "Blub.", chance = 99 }, hurt = { "Blub?!", chance = 99 }, death = { "Bluuub...", chance = 99 }, victory = { "Blub blub blub!", chance = 99 } },\n}/' "$MO_SLIME"
"$BIN" check --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk check with the slime's speech: $(cat "$T/content.log")"
t_fight monsterer 1 50
t_get /fight; CS=$(t_csrf)
t_round "csrf=$CS&fight=Fight"
expect_body '<span class="fight-speech">Blue Slime: “Blub'
grep -o '<span class="fight-speech">[^<]*</span>' "$BODY" | grep -qvE 'Blub\?!|Blub\.' && t_fail "an unexpected line" || t_ok
WON=
for _ in $(seq 1 20); do
	mo_enemy_set "hp = 1"
	t_round "csrf=$CS&fight=Fight"
	if [ "$(mo_outcome)" = victory ]; then WON=1; break; fi
done
[ -n "$WON" ] && t_ok || t_fail "the slime never fell"
t_get /victory; expect_body '<p class="dk-scene-quote">Blue Slime: &ldquo;Bluuub...&rdquo;</p>'
t_fight_clear monsterer
t_sql "UPDATE users SET currentaction = 'Exploring', dexterity = 5, base_maxhp = 500 $MQ"
# (a slime that hits hard and can't be killed: the player falls at its first blow that lands)
MO_SLIME_DAM=$(t_sql "SELECT maxdam FROM monsters WHERE id = 1")
t_sql "UPDATE monsters SET maxdam = 100000 WHERE id = 1"
t_fight monsterer 1 100000
DIED=
for _ in $(seq 1 30); do
	t_sql "UPDATE users SET currenthp = 1 $MQ"
	t_round "csrf=$CS&fight=Fight"
	if [ "$(mo_outcome)" = death ]; then DIED=1; break; fi
done
t_sql "UPDATE monsters SET maxdam = $MO_SLIME_DAM WHERE id = 1"
[ -n "$DIED" ] && t_ok || t_fail "the slime never won"
t_get /fight; expect_body '<p class="fight-taunt"><span class="fight-speech">Blue Slime: &ldquo;Blub blub blub!&rdquo;</span></p>'
cp "$T/blue_slime.lua.orig" "$MO_SLIME"
t_fight_clear monsterer
t_sql "UPDATE users SET currentaction = 'Exploring', base_maxhp = 500, currenthp = 500, dexterity = 22500, latitude = 20, longitude = 0 $MQ"

t_section "monsters: elements, resistances and wards"
# (overrides) the Red Slime weak to fire, its attack frost; the Dagger a fire weapon that
# resists frost; the player can be hit (dexterity 0: no dodging)
MO_RED=$(mon red_slime)
t_sql "INSERT INTO content_overrides (kind, key, field, value) VALUES ('monsters', 'red_slime', 'resist.fire', '-50'),
	('monsters', 'red_slime', 'attack_element', 'frost'), ('items', 'dagger', 'element', 'fire'),
	('items', 'dagger', 'modifiers.1.element', 'frost'), ('items', 'dagger', 'modifiers.1.amount', '50')"
"$BIN" content sync --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk content sync: $(cat "$T/content.log")"
t_items_clear monsterer; t_give monsterer dagger 1 weapon
t_sql "UPDATE users SET dexterity = 0 $MQ"
t_get /character; expect_body '<span class="charsheet-affinities">Resists Frost (50%)</span>'
t_get /inventory; expect_body 'Deals Fire damage'; expect_body 'Frost Resistance +50%'
t_fight monsterer "$MO_RED" 100000
t_get /fight; CS=$(t_csrf)
expect_body '<div class="tip-meta">Level 1</div><ul class="tip-lines"><li>Weak to Fire (+50%)</li></ul>'
MO_WEAK= MO_RESIST=
for _ in $(seq 1 8); do
	t_round "csrf=$CS&fight=Fight"
	grep -qE 'You attack the monster for [0-9]+ damage\.<br>It is weak to fire!' "$BODY" && MO_WEAK=1
	grep -qE 'The monster attacks you for [0-9]+ damage\.<br>You resist frost\.' "$BODY" && MO_RESIST=1
	[ -n "$MO_WEAK" ] && [ -n "$MO_RESIST" ] && break
done
[ -n "$MO_WEAK" ] && t_ok || t_fail "the fire weapon's hit on a weakness has no line"
[ -n "$MO_RESIST" ] && t_ok || t_fail "the frost attack on a resistance has no line"
# a ward of 100 against sleep (the Silver Slime's, the original immunity 2): Sleep says immune
t_spells monsterer "$(t_sql "SELECT id FROM spells WHERE key = 'sleep'")"
t_sql "UPDATE users SET currentmp = 100 $MQ"
t_fight monsterer "$(mon silver_slime)" 15
t_get /fight; CS=$(t_csrf)
t_round "csrf=$CS&spell=$(t_sql "SELECT id FROM spells WHERE key = 'sleep'")"
expect_body 'You have cast the Sleep spell, but the monster is immune to it.'
mo_is "(SELECT count(*) FROM fight_statuses WHERE user_id = users.id)" "0"
t_fight_clear monsterer; t_items_clear monsterer
t_sql "DELETE FROM content_overrides WHERE key IN ('red_slime', 'dagger'); UPDATE users SET dexterity = 22500, currentaction = 'Exploring' $MQ"
# a class (an override here: no monster file has one yet): the Goblin Shaman (level 5) as a
# Mage casts Magic Bolt too (its own Hurt and Heal stay as they are)
t_sql "INSERT INTO content_overrides (kind, key, field, value) VALUES ('monsters', 'goblin_shaman', 'class', 'mage')"
"$BIN" content sync --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk content sync: $(cat "$T/content.log")"
t_get /character; expect_no_body 'charsheet-affinities'

t_section "monsters: the help page"
t_get /help/monsters; expect_status 200
expect_body '<th>Max MP</th><th>Affinities</th>'
expect_body '>Shadow</td><td style="width: 9%">10</td><td style="width: 9%">9</td><td style="width: 9%">3</td><td style="width: 9%">2</td><td style="width: 9%">6</td><td style="width: 9%">2</td><td style="width: 8%">5</td><td style="width: 12%">Immune to Arcane</td></tr>'
expect_body '<td style="width: 12%">Immune to Arcane<br>Wards off Sleep (100%)</td>'
expect_body 'Spells: Hurt, Heal; Mage spells: Magic Bolt; Items: Potion (2); Equipment: Dagger'
expect_body '>Blue Slime</td><td style="width: 9%">4</td><td style="width: 9%">3</td><td style="width: 9%">1</td><td style="width: 9%">1</td><td style="width: 9%">1</td><td style="width: 9%">1</td><td style="width: 8%">5</td>'
expect_body '>Bandit Captain <span class="light">(not met at random)</span></td><td style="width: 9%">145</td><td style="width: 9%">65</td><td style="width: 9%">52</td>'
expect_body 'Spells: Craze; Items: Herb (1); Equipment: Broadsword, Chain Mail, Small Shield, Life Stone'
expect_body 'Spells: Sleep, Poison, Pain <span class="light">(its spells cost no MP)</span>'

t_section "monsters: cleanup"
t_sql "DELETE FROM content_overrides WHERE kind = 'monsters'"
"$BIN" content sync --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk content sync: $(cat "$T/content.log")"
[ "$(t_sql "SELECT group_concat(attack_weight) FROM monsters WHERE id > 151")" = "4,1,3" ] && t_ok || t_fail "overrides gone"

fi
