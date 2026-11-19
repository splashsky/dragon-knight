# tests/e2e/monsters.sh :: monsters as content through HTTP (2.2): the example monsters with
# spells, items, equipment and MP (Goblin Shaman, Bog Witch, Bandit Captain), their stock
# per encounter, uses_mp, the help page, and random encounters never picking monsters that
# don't roam. The monsters' choices are random by weight; the tests make them certain with
# an attack weight of 0 (an admin override) and the fight's state (HP, MP, statuses).
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
expect_body 'You are fighting a <b>Goblin Shaman</b>'; expect_body "Monster's MP: 0"
t_post /fight "csrf=$CS&fight=Fight"
expect_body 'class="fight-monsterturn">The Goblin Shaman uses the Potion.<br>The Goblin Shaman recovers '
mo_is "$(enemy hp)" 40; mo_is "$(enemy data)" "immune=i:0
stock_1=i:1"
mo_enemy_set "hp = 10"
t_post /fight "csrf=$CS&fight=Fight"; expect_body 'The Goblin Shaman uses the Potion.'
mo_is "$(enemy data)" "immune=i:0
stock_1=i:0"
mo_enemy_set "hp = 10"
t_post /fight "csrf=$CS&fight=Fight"; expect_no_body 'uses the Potion'
expect_body 'You dodge the monster&#39;s attack.'
# a new encounter: two potions again
t_fight monsterer "$SHAMAN" 10
mo_enemy_set "mp = 0, maxmp = 17"
t_post /fight "csrf=$CS&fight=Fight"; expect_body 'The Goblin Shaman uses the Potion.'
mo_is "$(enemy data)" "immune=i:0
stock_1=i:1"

t_section "monsters: the Goblin Shaman casts Hurt (MP)"
t_fight monsterer "$SHAMAN" 40   # full HP: no heal, no potion; 17 MP
t_get /fight; expect_body "Monster's MP: 17"
t_post /fight "csrf=$CS&fight=Fight"
expect_body 'class="fight-monsterturn">The monster casts Hurt on you for '; expect_body "Monster's MP: 12"
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
for _ in 1 2; do
	t_post /fight "csrf=$CS&continue=Continue"
	expect_body 'You are still asleep.'; expect_body 'class="fight-monsterturn">The monster casts Pain on you for '
	expect_body "Monster's MP: 33"
done
mo_is "$(enemy mp)" 33
# awake and cured: Sleep or Poison (or Pain), still free
t_sql "DELETE FROM fight_statuses WHERE user_id = (SELECT id FROM users $MQ)"
t_sql "UPDATE users SET currenthp = 500 $MQ"
t_post /fight "csrf=$CS&fight=Fight"
if grep -qF 'The Bog Witch casts Sleep.<br>You fall asleep.' "$BODY"; then mo_is "$T_STATUSES" "player:sleep"
elif grep -qF 'The monster casts Poison. You are poisoned for 3 turns.' "$BODY"; then mo_is "$T_STATUSES" "player:poison/3"
else expect_body 'The monster casts Pain on you for '; fi
mo_is "$(enemy mp)" 33
t_sql "UPDATE users SET currenthp = 500 $MQ"

t_section "monsters: the Bandit Captain's gear and frenzy"
BANDIT=$(mon bandit_captain)
t_fight monsterer "$BANDIT" 145
mo_enemy_set "maxhp = 145"   # with its Life Stone
t_get /fight; CS=$(t_csrf); expect_body "Monster's MP: 40"
t_post /fight "csrf=$CS&fight=Fight"
expect_body 'The Bandit Captain casts Craze.<br>The Bandit Captain will deal 10% more damage until the end of this fight.'
expect_body '<b>Bandit Captain</b> <span class="fight-statuses">&mdash; Damage Up</span>'
mo_is "$(enemy mp)" 30
# buffed already, not hurt enough for its herb: the attack
t_post /fight "csrf=$CS&fight=Fight"; expect_body 'You dodge the monster&#39;s attack.'; expect_no_body 'casts Craze'
mo_enemy_set "hp = 40"
t_post /fight "csrf=$CS&fight=Fight"; expect_body 'The Bandit Captain uses the Herb.<br>The Bandit Captain recovers 30 Hit Points.'
t_fight_clear monsterer
t_sql "UPDATE users SET currentaction = 'Exploring' $MQ"

t_section "monsters: the help page"
t_get /help/monsters; expect_status 200
expect_body '<th>Max MP</th>'
expect_body '>Blue Slime</td><td style="width: 9%">4</td><td style="width: 9%">3</td><td style="width: 9%">1</td><td style="width: 9%">1</td><td style="width: 9%">1</td><td style="width: 9%">1</td><td style="width: 8%">5</td>'
expect_body '>Bandit Captain <span class="light">(not met at random)</span></td><td style="width: 9%">145</td><td style="width: 9%">65</td><td style="width: 9%">52</td>'
expect_body 'Spells: Craze; Items: Herb (1); Equipment: Broadsword, Chain Mail, Small Shield, Life Stone'
expect_body 'Spells: Hurt, Heal; Items: Potion (2); Equipment: Dagger'
expect_body 'Spells: Sleep, Poison, Pain <span class="light">(its spells cost no MP)</span>'

t_section "monsters: cleanup"
t_sql "DELETE FROM content_overrides WHERE kind = 'monsters'"
"$BIN" content sync --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk content sync: $(cat "$T/content.log")"
[ "$(t_sql "SELECT group_concat(attack_weight) FROM monsters WHERE id > 151")" = "4,1,3" ] && t_ok || t_fail "overrides gone"

fi
