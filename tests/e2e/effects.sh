# tests/e2e/effects.sh :: the fight engine through HTTP (2.2): the example spells and
# items with statuses (Poison, Regen, Hyper Beam, Solar Beam, Call Wolf, Antidote, Regen
# Potion), the fight page's statuses, allies and locked "Continue" turn, world statuses
# on map moves and on the character page, and the allies setting. No class learns the new
# spells: the test character is given them. Sourced by tests/run.sh.
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
# sturdy and never hit: dexterity 22500 dodges every attack (rand(1,150) <= 150)
ef_sql "UPDATE users SET base_maxhp = 500, currenthp = 500, base_maxmp = 200, currentmp = 200, dexterity = 22500,
	latitude = 3, longitude = 3"
t_get /character; expect_no_body 'Statuses:'

t_section "effects: Poison"
t_fight effector 149 30000   # a Titan with 30000 HP, no immunity
t_get /fight; CS=$(t_csrf); expect_body "name=\"spell\" value=\"$(sp poison)\" title=\"Poison ("
t_round "csrf=$CS&spell=Spell&userspell=$(sp poison)"
expect_body 'You have cast the Poison spell. The monster is poisoned for 3 turns.'
expect_body 'class="fight-roundend">The Titan takes '
expect_body '<b>Titan</b> <span class="fight-statuses">&mdash; Poisoned <span class="light">(2 turns)</span></span>'
ef_is "$T_STATUSES" "enemy:poison/2"
hp=$(t_sql "SELECT $T_MONSTER_HP FROM users $EQ")
[ "$hp" -ge 29994 ] && [ "$hp" -le 29998 ] && t_ok || t_fail "poison damage: monster HP $hp"
t_round "csrf=$CS&fight=Fight"; t_round "csrf=$CS&fight=Fight"
ef_is "$T_STATUSES" ""; expect_no_body 'Poisoned'

t_section "effects: Hyper Beam locks the next turn"
t_round "csrf=$CS&spell=Spell&userspell=$(sp hyper_beam)"
expect_body 'You have cast the Hyper Beam spell for'; expect_body 'You must recharge next turn.'
expect_body "You can't act this turn."; expect_body 'name="continue" value="Continue"'
expect_no_body 'name="fight"'; expect_no_body 'name="run"'
expect_body '<b>You</b> <span class="fight-statuses">&mdash; Recharging <span class="light">(1 turn)</span></span>'
MP=$(t_sql "SELECT currentmp FROM users $EQ")
# any command while locked is the turn's "Continue" (no attack, no spell, no escape)
t_round "csrf=$CS&spell=Spell&userspell=$(sp heal)"
expect_body 'You must recharge this turn.'; expect_no_body 'You have cast'; expect_body 'name="fight"'
ef_is currentmp "$MP"; ef_is "$T_STATUSES" ""

t_section "effects: Solar Beam charges, then fires"
t_round "csrf=$CS&spell=Spell&userspell=$(sp solar_beam)"
expect_body 'You have cast the Solar Beam spell, and gather sunlight.'; expect_body 'name="continue"'
ef_is "$T_STATUSES" "player:charging/1"
ef_is "(SELECT data FROM fight_statuses fs WHERE fs.user_id = users.id)" "entity=s:solar_beam
from=s:spell
release=s:release"
hp=$(t_sql "SELECT $T_MONSTER_HP FROM users $EQ")
t_round "csrf=$CS&continue=Continue"
expect_body 'The Solar Beam fires for'; expect_body 'name="fight"'
dmg=$((hp - $(t_sql "SELECT $T_MONSTER_HP FROM users $EQ")))
[ "$dmg" -ge 75 ] && [ "$dmg" -le 90 ] && t_ok || t_fail "solar beam damage $dmg"
# Continue when nothing locks the turn does nothing (the page shows the last round again)
FIGHT=$(t_sql "SELECT $T_ROUND || '|' || currenthp || '|' || $T_MONSTER_HP FROM users $EQ")
t_round "csrf=$CS&continue=Continue"; expect_body 'The Solar Beam fires for'
ef_is "$T_ROUND || '|' || currenthp || '|' || $T_MONSTER_HP" "$FIGHT"

t_section "effects: Call Wolf"
# the monster sleeps through this part (a chance of 15 in 15 to stay asleep)
t_fight_status effector 2 sleep 'chance=i:15'
t_round "csrf=$CS&spell=Spell&userspell=$(sp call_wolf)"
expect_body 'You have cast the Call Wolf spell. A wolf joins the fight for 5 rounds.'
expect_body 'class="fight-allyturn">Your Wolf bites the monster for'
expect_body 'class="fight-monsterturn">The monster is still asleep.'
expect_body 'Your <b>Wolf</b>: 30 / 30 HP <span class="light">(4 rounds left)</span>'
ef_is "(SELECT group_concat(side || ':' || kind) FROM fight_combatants c WHERE c.user_id = users.id)" "player:player,enemy:monster,ally:summon"
MP=$(t_sql "SELECT currentmp FROM users $EQ")
t_round "csrf=$CS&spell=Spell&userspell=$(sp call_wolf)"; expect_body 'You can&#39;t call another ally now.'
ef_is currentmp "$MP"
for _ in 1 2 3; do t_round "csrf=$CS&fight=Fight"; done
expect_body '(1 round left)'
t_round "csrf=$CS&fight=Fight"; expect_body 'Your Wolf runs off into the wild.'; expect_no_body 'Your <b>Wolf</b>'
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
t_get /fight; CS=$(t_csrf); expect_body '<b>You</b> <span class="fight-statuses">&mdash; Poisoned'
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
t_get /victory; expect_body 'You have defeated the Titan.'
ef_is "$T_ROUND" 0; ef_is "$T_STATUSES" ""
# (the finished fight is kept for its page, statuses and all, until the next encounter)
ef_is "(SELECT outcome FROM fights f WHERE f.user_id = users.id)" victory
ef_sql "UPDATE users SET base_attack = 0"

t_section "effects: world statuses (Regen in town, the Regen Potion)"
ef_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0, currenthp = 100, currentmp = 100"
t_get /; expect_body "action=\"/spell/$(sp regen)\""
t_post "/spell/$(sp regen)" "csrf=$(t_csrf)"
expect_body 'You have cast the Regen spell, and will regenerate 6 Hit Points for the next 5 moves.'
ef_is "$T_WORLD" "regen/5"; ef_is currentmp 92
t_get /character; expect_body 'Statuses: Regenerating <span class="light">(5 moves)</span>'
# moves tick (before the roll for a fight)
t_get /; ECS=$(t_csrf)
for _ in 1 2; do
	ef_sql "UPDATE users SET currentaction = 'Exploring', latitude = 3, longitude = 3"; t_fight_clear effector
	t_post /move "csrf=$ECS&north=North"
done
ef_is "$T_WORLD" "regen/3"; ef_is currenthp 112
# a fight doesn't end them, nor tick them
ef_sql "UPDATE users SET currentaction = 'Exploring'"; t_fight effector 149 30000
t_get /fight; t_round "csrf=$(t_csrf)&fight=Fight"
ef_is "$T_WORLD" "regen/3"; ef_is "$T_STATUSES" ""
t_fight_clear effector
# the Regen Potion from the bag: replaces the spell's regen (5 for the next 10 moves)
t_give effector regen_potion 1
ef_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0"
t_get /inventory; RP=$(t_sql "SELECT min(ui.id) FROM user_items ui JOIN items i ON i.id = ui.item_id WHERE i.key = 'regen_potion' AND ui.user_id = (SELECT id FROM users $EQ)")
t_post "/inventory/use/$RP" "csrf=$(t_csrf)"
expect_body 'You have used the Regen Potion, and will regenerate 5 Hit Points for the next 10 moves.'
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
expect_body 'statuses: 7 files, 7 in the database (0 retired), 0 overrides.'
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
t_get /admin/summons; expect_body '<a href="/admin/summons/1">Wolf</a>'
t_get /admin/summons/1; expect_body 'Edit Summon: Wolf'; expect_body 'name="hp" size="6" value="30"'
t_get /admin/summons/99; expect_status 404
t_jar effects
t_sql "DELETE FROM user_statuses WHERE user_id = (SELECT id FROM users $EQ)"
fi
