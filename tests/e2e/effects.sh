# tests/e2e/effects.sh :: the fight engine through HTTP (2.2): the example spells and
# items with statuses (Poison, Regen, Hyper Beam, Solar Beam, Call Wolf, Antidote, Regen
# Potion), the fight page's statuses, allies and locked "Continue" turn, world statuses
# and the character page, and the allies setting; since 3.2 on the clock (t_tick: the
# server's tick, the clock moved on a tick). No class learns the new spells: the test
# character is given them. Sourced by tests/run.sh.
if ! t_has_sql; then
	t_section "effects (skipped: needs sqlite3 or python3)"
else

t_section "effects: setup"
t_jar effects
t_register effector effpw1 effector@example.com Effector 1
t_login effector effpw1
EQ="WHERE username = 'effector'"
ef_sql() { t_sql "$1 $EQ"; }
ef_is() {  # ef_is EXPR EXPECTED (an SQL expression on the users row)
	local got; got=$(t_sql "SELECT $1 FROM users $EQ")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$1: expected '$2', got '$got'"; fi
}
sp() { t_sql "SELECT id FROM spells WHERE key = '$1'"; }
it() { t_sql "SELECT id FROM items WHERE key = '$1'"; }
t_spells effector "$(sp heal),$(sp poison),$(sp regen),$(sp hyper_beam),$(sp solar_beam),$(sp call_wolf)"
# sturdy and never hit: dexterity 22500 dodges every attack (rand(1,150) <= 150); at the
# calm place (t_calm: no field changes the damage, the statuses or the dodging)
ef_sql "UPDATE users SET base_maxhp = 500, currenthp = 500, base_maxmp = 200, currentmp = 200, dexterity = 22500"
t_calm effector
t_get /character; expect_no_body 'Statuses:'

t_section "effects: Poison"
# a Creature with 30000 HP: it only attacks, with no affinities (not the Goblin: it rolls a keg onto the field on its second turn)
CREATURE=$(t_sql "SELECT id FROM monsters WHERE key = 'creature'")
t_fight effector "$CREATURE" 30000
t_get /fight; CS=$(t_csrf); expect_body "name=\"spell\" value=\"$(sp poison)\" title=\"Poison ("
t_round "csrf=$CS&spell=Spell&userspell=$(sp poison)"
expect_body 'You have cast the Poison spell. The monster is poisoned for 30 seconds.'
expect_no_body 'class="fight-roundend"'
expect_body '<b>Creature</b> <span class="fight-statuses">&mdash; <img class="fight-status-icon" src="/static/images/statuses/poison.png" width="16" height="16" alt="">Poisoned <span class="light">(30s)</span></span>'
ef_is "$T_STATUSES" "enemy:poison/3"
# the clock's next tick: it ticks (its line in the fight's log, after the round's), and counts down
t_tick; expect_body 'tick 400000001: '
t_get /fight; expect_body 'You have cast the Poison spell.'; expect_body 'class="fight-roundend">The Creature takes '
expect_body 'Poisoned <span class="light">(20s)</span>'
ef_is "$T_STATUSES" "enemy:poison/2"
hp=$(t_sql "SELECT $T_MONSTER_HP FROM users $EQ")
[ "$hp" -ge 29994 ] && [ "$hp" -le 29998 ] && t_ok || t_fail "poison damage: monster HP $hp"
t_tick; t_tick
ef_is "$T_STATUSES" ""; t_get /fight; expect_no_body 'Poisoned'; CS=$(t_csrf)

t_section "effects: Hyper Beam locks the next turn"
t_round "csrf=$CS&spell=Spell&userspell=$(sp hyper_beam)"
expect_body 'You have cast the Hyper Beam spell for'; expect_body 'You must recharge next turn.'
expect_body "You can't act this turn."; expect_body 'name="continue" value="Continue"'
expect_no_body 'name="fight"'; expect_no_body 'name="run"'
expect_body '<b>You</b> <span class="fight-statuses">&mdash; <img class="fight-status-icon" src="/static/images/statuses/recharging.png" width="16" height="16" alt="">Recharging <span class="light">(10s)</span></span>'
MP=$(t_sql "SELECT currentmp FROM users $EQ"); FIGHT=$(t_sql "SELECT $T_ROUND FROM users $EQ")
# the turn ends at the clock's next tick: a command now plays nothing (no attack, no spell)
t_round "csrf=$CS&spell=Spell&userspell=$(sp heal)"
expect_body "You can't act this turn."; ef_is currentmp "$MP"; ef_is "$T_ROUND" "$FIGHT"
t_tick
t_get /fight; expect_body 'You must recharge this turn.'; expect_body 'name="fight"'
ef_is currentmp "$MP"; ef_is "$T_STATUSES" ""; CS=$(t_csrf)

t_section "effects: Solar Beam charges, then fires"
t_round "csrf=$CS&spell=Spell&userspell=$(sp solar_beam)"
expect_body 'You have cast the Solar Beam spell, and gather sunlight.'; expect_body 'name="continue"'
ef_is "$T_STATUSES" "player:charging/1"
ef_is "(SELECT data FROM fight_statuses fs WHERE fs.user_id = users.id)" "entity=s:solar_beam
from=s:spell
release=s:release"
hp=$(t_sql "SELECT $T_MONSTER_HP FROM users $EQ")
# at the next tick: the blocked turn ends, then the charge runs out and the beam fires
t_tick
t_get /fight; expect_body 'You are gathering power.'; expect_body 'The Solar Beam fires for'; expect_body 'name="fight"'
CS=$(t_csrf)
dmg=$((hp - $(t_sql "SELECT $T_MONSTER_HP FROM users $EQ")))
[ "$dmg" -ge 75 ] && [ "$dmg" -le 90 ] && t_ok || t_fail "solar beam damage $dmg"
ef_is "(SELECT instr(data, 'field_') FROM fights f WHERE f.user_id = users.id)" 0   # (the calm place: no field)
# Continue when nothing locks the turn does nothing (the page shows the last round again)
FIGHT=$(t_sql "SELECT $T_ROUND || '|' || currenthp || '|' || $T_MONSTER_HP FROM users $EQ")
t_round "csrf=$CS&continue=Continue"; expect_body 'The Solar Beam fires for'
ef_is "$T_ROUND || '|' || currenthp || '|' || $T_MONSTER_HP" "$FIGHT"

t_section "effects: Call Wolf"
# the monster sleeps through this part (a chance of 15 in 15 to stay asleep)
t_fight_status effector 2 sleep 'chance=i:15'
t_round "csrf=$CS&spell=Spell&userspell=$(sp call_wolf)"
expect_body 'You have cast the Call Wolf spell. A wolf joins the fight for 50 seconds.'
expect_body 'class="fight-allyturn">Your Wolf bites the monster for'
expect_body 'class="fight-monsterturn">The Creature is still asleep.'
expect_body 'Your <b>Wolf</b>: 30 / 30 HP <span class="light">(50s left)</span>'
ef_is "(SELECT group_concat(side || ':' || kind) FROM fight_combatants c WHERE c.user_id = users.id)" "player:player,enemy:monster,ally:summon"
MP=$(t_sql "SELECT currentmp FROM users $EQ")
t_round "csrf=$CS&spell=Spell&userspell=$(sp call_wolf)"; expect_body 'You can&#39;t call another ally now.'
ef_is currentmp "$MP"
# it stays its ticks of the clock (rounds or not)
for _ in 1 2 3 4; do t_tick; done
t_get /fight; expect_body '(10s left)'
t_tick; t_get /fight; expect_body 'Your Wolf runs off into the wild.'; expect_no_body 'Your <b>Wolf</b>'; CS=$(t_csrf)
ef_is "(SELECT count(*) FROM fight_combatants c WHERE c.user_id = users.id AND side = 'ally')" 0
# no allies allowed: refused
t_sql "UPDATE control SET max_allies = 0"
t_round "csrf=$CS&spell=Spell&userspell=$(sp call_wolf)"; expect_body 'You can&#39;t call another ally now.'
t_sql "UPDATE control SET max_allies = 1"
t_sql "DELETE FROM fight_statuses WHERE user_id = (SELECT id FROM users $EQ)"

t_section "effects: Antidote in a fight"
t_give effector antidote 2
t_fight_status effector 1 poison 'max=i:3
min=i:1' 3
t_get /fight; CS=$(t_csrf); expect_body '<b>You</b> <span class="fight-statuses">&mdash; <img class="fight-status-icon" src="/static/images/statuses/poison.png" width="16" height="16" alt="">Poisoned'
t_round "csrf=$CS&item=Use+Item&useritem=$(it antidote)"; expect_body 'You have used the Antidote, and feel better.'
ef_is "$T_STATUSES" ""; ef_is "$T_ITEMS" "antidote"
t_round "csrf=$CS&item=Use+Item&useritem=$(it antidote)"; expect_body 'You don&#39;t need the Antidote now.'
ef_is "$T_ITEMS" "antidote"

t_section "effects: the fight's statuses end with it"
t_fight_status effector 1 regen 'amount=i:5' 4
t_sql "UPDATE fight_combatants SET hp = 1 WHERE side = 'enemy' AND user_id = (SELECT id FROM users $EQ)"
ef_sql "UPDATE users SET base_attack = 1000"
for _ in $(seq 1 20); do   # until the monster doesn't dodge
	t_round "csrf=$CS&fight=Fight"
	[ "$STATUS" = 302 ] && break
done
expect_redirect /victory
t_get /victory; expect_body 'You have defeated the Creature.'
ef_is "$T_ROUND" 0; ef_is "$T_STATUSES" ""
# (the finished fight is kept for its page, statuses and all, until the next encounter)
ef_is "(SELECT outcome FROM fights f WHERE f.user_id = users.id)" victory
ef_sql "UPDATE users SET base_attack = 0"

t_section "effects: world statuses (Regen in town, the Regen Potion)"
ef_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0, currenthp = 100, currentmp = 100"
t_get /; expect_body "action=\"/spell/$(sp regen)\""
t_post "/spell/$(sp regen)" "csrf=$(t_csrf)"
expect_body 'You have cast the Regen spell, and will regenerate 6 Hit Points for 50 seconds.'
ef_is "$T_WORLD" "regen/5"; ef_is currentmp 92
t_get /character; expect_body 'Statuses: Regenerating <span class="light">(50s)</span>'
# the clock's ticks count them (moves don't). The move may begin an encounter (1 in 5):
# its fight goes, and the character is back to exploring (a fighting one's world statuses
# let the ticks pass them by).
t_get /; ECS=$(t_csrf)
ef_sql "UPDATE users SET currentaction = 'Exploring', latitude = 3, longitude = 3"; t_fight_clear effector
t_post /move "csrf=$ECS&north=North"; t_fight_clear effector
ef_sql "UPDATE users SET currentaction = 'Exploring'"
ef_is "$T_WORLD" "regen/5"; ef_is currenthp 100
t_tick; t_tick
ef_is "$T_WORLD" "regen/3"; ef_is currenthp 112
# a fight doesn't end them, nor tick them
ef_sql "UPDATE users SET currentaction = 'Exploring'"; t_fight effector "$CREATURE" 30000
t_get /fight; t_round "csrf=$(t_csrf)&fight=Fight"; t_tick
ef_is "$T_WORLD" "regen/3"; ef_is "$T_STATUSES" ""
t_fight_clear effector
# the Regen Potion from the bag: replaces the spell's regen (5 for the next 10 moves)
t_give effector regen_potion 1
ef_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0"
t_get /inventory; RP=$(t_sql "SELECT min(ui.id) FROM user_items ui JOIN items i ON i.id = ui.item_id WHERE i.key = 'regen_potion' AND ui.user_id = (SELECT id FROM users $EQ)")
t_post "/inventory/use/$RP" "csrf=$(t_csrf)"
expect_body 'You have used the Regen Potion, and will regenerate 5 Hit Points for 100 seconds.'
ef_is "$T_WORLD" "regen/10"
# the Antidote in town: nothing harmful to cure
AN=$(t_sql "SELECT min(ui.id) FROM user_items ui JOIN items i ON i.id = ui.item_id WHERE i.key = 'antidote' AND ui.user_id = (SELECT id FROM users $EQ)")
t_post "/inventory/use/$AN" "csrf=$(t_csrf)"; expect_body 'You don&#39;t need to use the Antidote now.'

t_section "effects: help pages"
t_get /help/spells; expect_body '>Hyper Beam<br>'; expect_body 'id="statuses"'; expect_body '>Poisoned<br>'
expect_body 'id="summons"'; expect_body '>Wolf<br>'

t_section "effects: settings"
t_jar admin; t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin/settings; expect_body 'name="max_allies" size="3" maxlength="2" value="1"'
t_form_submit /admin/settings max_allies=11; expect_body 'Allies must be a number from 0 to 10.'

t_section "effects: admin pages for statuses and summons"
t_get /admin/statuses; expect_status 200; expect_body '<a href="/admin/statuses/1">Asleep</a>'
expect_body "statuses: $(ls app/content/statuses | wc -l) files, $(t_sql 'SELECT count(*) FROM statuses') in the database (0 retired), 0 overrides."
POISON=$(t_sql "SELECT id FROM statuses WHERE key = 'poison'")
t_get "/admin/statuses/$POISON"; expect_body 'Edit Status: Poisoned'; expect_body 'app/content/statuses/poison.lua'
expect_body 'name="data.max" size="6" value="5"'
t_form_submit "/admin/statuses/$POISON" "description=Loses hit points at the end of every turn." name=Envenomed data.max=9
expect_redirect "/admin/statuses/$POISON\\?saved=1"
[ "$(t_sql "SELECT name || '|' || replace(data, char(10), ',') FROM statuses WHERE key = 'poison'")" = "Envenomed|max=9,min=2" ] \
	&& t_ok || t_fail "status override not applied"
t_get "/admin/statuses/$POISON"; t_post "/admin/statuses/$POISON/reset" "csrf=$(t_csrf)&field=*"
expect_redirect "/admin/statuses/$POISON\\?saved=1"
[ "$(t_sql "SELECT count(*) FROM content_overrides WHERE kind = 'statuses'")" = 0 ] && t_ok || t_fail "status overrides not reset"
WOLF=$(t_sql "SELECT id FROM summons WHERE key = 'wolf'")
t_get /admin/summons; expect_body "<a href=\"/admin/summons/$WOLF\">Wolf</a>"
t_get /admin/summons/$WOLF; expect_body 'Edit Summon: Wolf'; expect_body 'name="hp" size="6" value="30"'
t_get /admin/summons/99; expect_status 404
t_jar effects
t_sql "DELETE FROM user_statuses WHERE user_id = (SELECT id FROM users $EQ)"
fi
