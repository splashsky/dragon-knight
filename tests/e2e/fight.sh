# tests/e2e/fight.sh :: fight / victory / drop / dead. Sourced by tests/run.sh.
if t_has_sql; then

t_section "fight: setup + guards"
t_jar fighter
t_register fighter fightpw fighter@example.com Fighter 2   # Warrior
t_login fighter fightpw
FQ="WHERE username = 'fighter'"
f_sql() { t_sql "$1 $FQ"; }
f_col() { t_sql "SELECT $1 FROM users $FQ"; }
f_is() { # f_is COLUMN EXPECTED
	local got; got=$(f_col "$1")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "users.$1: expected '$2', got '$got'"; fi
}
t_get /fight;   expect_status 200; expect_body 'Cheat attempt detected.'
t_get /victory; expect_redirect /
t_get /drop;    expect_redirect /
t_get /dead;    expect_status 200; expect_body 'You have died.'

# a fight in progress: no free victory
t_fight_new fighter
t_get /victory; expect_redirect /fight
f_is "$T_ROUND" 2
t_get /;        expect_redirect /fight

t_section "fight: monster selection"
# the encounter begins where the player stands (POST /move, here t_fight_new): the monster
# is picked by the level band, its first strike (when quicker) played
f_sql "UPDATE users SET latitude = -50, longitude = 7, currenthp = 1000, base_maxhp = 1000"
t_fight_new fighter
t_get /fight;   expect_status 200; expect_body '<h1 class="title page-title">Fighting</h1>'; expect_body 'You are fighting a <b class="tip-term" data-tip tabindex="0">'
expect_body "Monster's HP: "; expect_body 'name="fight"'; expect_body 'name="run"'
expect_no_body 'action="/move"'                       # no compass while fighting
f_is "$T_ROUND" 2
lvl=$(t_sql "SELECT m.level FROM users JOIN monsters m ON m.id = $T_MONSTER $FQ")
[ -n "$lvl" ] && [ "$lvl" -ge 9 ] && [ "$lvl" -le 11 ] && t_ok || t_fail "monster level $lvl not in 9..11"
hp=$(f_col "$T_MONSTER_HP")
[ "$hp" -gt 0 ] && t_ok || t_fail "monster hp $hp"
# the rolled HP is the monster's full health in this encounter: its bar starts full
expect_body "data-value=\"$hp\" data-max=\"$hp\">Monster's HP: $hp</p>"
f_is "(SELECT c.maxhp FROM fight_combatants c WHERE c.user_id = users.id AND c.side = 'enemy')" "$hp"
f_is "(SELECT count(*) FROM fight_combatants c WHERE c.user_id = users.id)" 2
t_round "fight=Fight"; expect_status 403          # CSRF required
f_is "$T_ROUND" 2
t_get /fight; expect_body "Monster's HP: $hp"; f_is "$T_ROUND" 2   # refresh: same monster, nothing counted

t_section "fight: run away"
CS=$(t_csrf)
DEX=$(f_col dexterity)
# (no gear: the effective stats are the base ones; defense power = dexterity + base_defense)
# dexterity 10000: rand(4,10) + 100 beats rand(1,5) + ceil(sqrt(maxdam)) of any level 9-11 monster
f_sql "UPDATE users SET dexterity = 10000"
t_fight_status fighter 1 uber_damage 'pct=i:10'; t_fight_status fighter 1 uber_defense 'pct=i:20'
t_round "csrf=$CS&run=Run"; expect_redirect /
f_is currentaction Exploring; f_is "$T_ROUND" 0; f_is "$T_MONSTER" 0; f_is "$T_MONSTER_HP" 0
f_is "$T_UBER_DAMAGE" 0; f_is "$T_UBER_DEFENSE" 0; f_is "$T_STATUSES" ""
f_is "(SELECT count(*) FROM fight_combatants c WHERE c.user_id = users.id)" 0
t_get /fight; expect_body 'Cheat attempt detected.'
t_get /victory; expect_redirect /

t_section "fight: run away blocked"
# a Colossus (it only attacks; maxdam 300): ceil(sqrt(300)) = 18 beats any run roll with
# dexterity 0 (max 10); no dodge with dexterity 0, and the hit is rand(150,300) - 0 (at the
# calm place: no field changes the monster's attack)
t_calm fighter
t_fight fighter 146 30000
f_sql "UPDATE users SET dexterity = 0, base_defense = 0, currenthp = 5000, base_maxhp = 5000"
t_round "csrf=$CS&run=Run"; expect_status 200
expect_body 'You tried to run away, but were blocked in front!'; expect_body "Monster's HP: 30000"
expect_body 'The monster attacks you for'; expect_body 'name="run"'; expect_no_body 'You have died.'
f_is currentaction Fighting; f_is "$T_ROUND" 3; f_is "$T_MONSTER" 146; f_is "$T_MONSTER_HP" 30000
hp=$(f_col currenthp)
[ "$hp" -ge 4700 ] && [ "$hp" -le 4850 ] && t_ok || t_fail "blocked run: currenthp $hp not in 4700..4850"
t_fight_clear fighter
f_sql "UPDATE users SET currentaction = 'Exploring', dexterity = $DEX"

t_section "fight: victory + level up"
# (from here to the deaths, at the calm place, Midworld's level band: the sleep spell's
# chance and the spells' numbers are what they are without a battlefield)
f_sql "UPDATE users SET base_attack = 495, currenthp = 500, base_maxhp = 500, experience = 17, gold = 100"
t_calm fighter
t_fight_new fighter
t_get /fight; CS=$(t_csrf)
for _ in $(seq 1 30); do
	t_round "csrf=$CS&fight=Fight"
	[ "$STATUS" = 302 ] && break
done
expect_redirect /victory
[ "$(f_col "$T_MONSTER_HP")" -le 0 ] && t_ok || t_fail "the monster is not defeated"
t_get /fight; expect_redirect /victory                # a won fight goes on to the victory
t_get /victory; expect_status 200
expect_body '<h1 class="dk-scene-title">Victory!</h1>'; expect_body 'You have defeated the'; expect_body 'You have gained a level!'
expect_body 'You gain 2 hit points.'; expect_body 'You gain 4 magic points.'; expect_body 'You have learned a new spell.'
expect_body '<title>Courage and Wit have served thee well!</title>'
f_is level 2; f_is base_maxhp 502; f_is base_maxmp 4; f_is base_maxtp 11; f_is strength 7; f_is dexterity 6
f_is "strength + base_attack" 502; f_is "dexterity + base_defense" 6; f_is "$T_KNOWN" 1
expect_stats "502 4 11 7 6 502 6" "level-up stats"
f_is currentaction Exploring; f_is "$T_ROUND" 0; f_is "$T_MONSTER" 0
[ "$(f_col experience)" -ge 18 ] && t_ok || t_fail "experience not awarded"
[ "$(f_col gold)" -gt 100 ] && t_ok || t_fail "gold not awarded"
# paid in the winning round: the page shows it again, nothing more is paid
t_get /victory; expect_status 200; expect_body 'You have gained a level!'; f_is level 2; f_is base_maxhp 502

t_section "fight: victory without level up"
t_fight_new fighter
t_get /fight; CS=$(t_csrf)
t_fight_status fighter 1 uber_damage 'pct=i:10'
for _ in $(seq 1 30); do
	t_round "csrf=$CS&fight=Fight"
	[ "$STATUS" = 302 ] && break
done
expect_redirect /victory
t_get /victory; expect_body '<title>Victory!</title>'; expect_no_body 'gained a level'
f_is level 2; f_is "$T_UBER_DAMAGE" 0; f_is "$T_STATUSES" ""

t_section "fight: spells"
t_fight_new fighter
f_sql "UPDATE users SET currenthp = 100, currentmp = 10, base_maxmp = 50"
t_get /fight; CS=$(t_csrf)
expect_body 'name="spell" value="1" title="Heal (5 MP)"'
t_round "csrf=$CS&spell=Spell&userspell=0"; expect_body 'You must select a spell first.'
t_round "csrf=$CS&spell=Spell";            expect_body 'You must select a spell first.'
t_round "csrf=$CS&spell=Spell&userspell=6"; expect_body 'You have not yet learned this spell.'
t_round "csrf=$CS&spell=Spell&userspell=$(t_enc "1' OR '1'='1")"; expect_body 'You have not yet learned this spell.'
t_round "csrf=$CS&spell=Spell&userspell=999"; expect_body 'You have not yet learned this spell.'
f_is currentmp 10
t_round "csrf=$CS&spell=Spell&userspell=1"
expect_status 200; expect_body 'You have cast the Heal spell, and gained 10 Hit Points.'
f_is currentmp 5
# heal at (or above) full HP: refused, no MP spent, the monster doesn't act
f_sql "UPDATE users SET currenthp = base_maxhp, currentmp = 10"
FIGHT=$(f_col "$T_ROUND")
t_round "csrf=$CS&spell=Spell&userspell=1"; expect_body 'Your Hit Points are already full.'
expect_body '<p class="fight-note error" role="alert">'; expect_body 'name="fight"'
f_is currentmp 10; f_is "$T_ROUND" "$FIGHT"; f_is "currenthp = base_maxhp" 1
f_sql "UPDATE users SET currenthp = base_maxhp + 5"
t_round "csrf=$CS&spell=Spell&userspell=1"; expect_body 'Your Hit Points are already full.'
f_is currentmp 10; f_is "currenthp = base_maxhp + 5" 1
# a retired spell (its file and so its code are gone): refused the same way
t_sql "UPDATE spells SET retired = 1 WHERE id = 1"
f_sql "UPDATE users SET currenthp = 100"
t_round "csrf=$CS&spell=Spell&userspell=1"; expect_body 'This spell cannot be cast.'
f_is currentmp 10; f_is currenthp 100; f_is "$T_ROUND" "$FIGHT"
t_sql "UPDATE spells SET retired = 0 WHERE id = 1"
f_sql "UPDATE users SET currentmp = 4"
t_round "csrf=$CS&spell=Spell&userspell=1"; expect_body 'You do not have enough Magic Points'
f_is currentmp 4
# sleep spell, then a hurt spell that kills
t_spells fighter 1,6,11
t_fight fighter 2 50 "$FIGHT"
f_sql "UPDATE users SET currentmp = 50"
t_round "csrf=$CS&spell=Spell&userspell=11"
expect_body 'You have cast the Sleep spell. The monster is asleep.'
# asleep: its turn is skipped (it rolls to wake on the clock's ticks, not in the rounds)
expect_body 'class="fight-monsterturn">The Red Slime is still asleep.'; f_is "$T_SLEEP" 5; f_is "$T_STATUSES" "enemy:sleep"
expect_body '&mdash; <img class="fight-status-icon" src="/static/images/statuses/sleep.png" width="16" height="16" alt="">Asleep</span>'
f_is currentmp 40
t_sql "UPDATE fight_combatants SET hp = 1 WHERE side = 'enemy' AND user_id = (SELECT id FROM users $FQ)"
t_round "csrf=$CS&spell=Spell&userspell=6"; expect_redirect /victory
[ "$(f_col "$T_MONSTER_HP")" -le 0 ] && t_ok || t_fail "the monster is not defeated"; f_is currentmp 35
t_get /victory; expect_body 'You have defeated the Red Slime.'

t_section "fight: every command comes back to the fight page (Post/Redirect/Get)"
t_spells fighter 1,6
t_fight fighter 2 50000   # (no lucky kill before round 5)
DEX0=$(f_col dexterity)
f_sql "UPDATE users SET currenthp = 100, base_maxhp = 100, currentmp = 50, base_maxmp = 50, dexterity = 22500"
t_get /fight; CS=$(t_csrf)
# a round: a redirect, and the page shows its lines (again on a reload: nothing replayed)
t_post /fight "csrf=$CS&fight=Fight&round=2"; expect_redirect /fight
f_is "$T_ROUND" 3
t_get /fight; expect_body 'class="fight-yourturn">'; expect_no_body 'fight-note'; expect_body 'name="round" value="3"'
LINES=$(grep -o 'class="fight-yourturn">[^<]*' "$BODY")
t_get /fight; [ "$(grep -o 'class="fight-yourturn">[^<]*' "$BODY")" = "$LINES" ] && t_ok || t_fail "a reload shows the same round"
f_is "$T_ROUND" 3
# a refusal: nothing played, the page says why above the commands, the round's lines stay
t_post /fight "csrf=$CS&spell=Spell&userspell=11&round=3"; expect_redirect /fight
t_get /fight; expect_body '<p class="fight-note error" role="alert">You have not yet learned this spell.</p>'
expect_no_body 'Please go back'; expect_body 'name="fight"'; expect_body 'class="fight-yourturn">'
f_is "$T_ROUND" 3
# ... until the next command that plays
t_round "csrf=$CS&fight=Fight&round=3"; expect_no_body 'fight-note'; f_is "$T_ROUND" 4
# a form from an older page: the note at the top
t_round "csrf=$CS&fight=Fight&round=3"; expect_body 'class="fight-stale"'; expect_no_body 'fight-note'
f_is "$T_ROUND" 4
t_round "csrf=$CS&fight=Fight&round=4"; expect_no_body 'class="fight-stale"'; f_is "$T_ROUND" 5
t_fight_clear fighter
f_sql "UPDATE users SET dexterity = $DEX0"
t_spells fighter 1,6,11

t_section "fight: spell buttons"
# one icon button per spell (spell=<id>), the MP cost as a badge, the spell's icon or
# default.png, disabled when the MP don't cover it; the old select and "Spell" are gone.
# They are on the hotbar (lib/hotbar.lua): Attack 1, then the first free keys
t_spells fighter 1,6
t_fight fighter 2 50
f_sql "UPDATE users SET currenthp = 10, currentmp = 6, base_maxmp = 50"
t_get /fight; CS=$(t_csrf)
expect_body '<div class="hotbar" role="group" aria-labelledby="hotbar-label"><span class="hotbar-label" id="hotbar-label">Hotbar</span>'
expect_body '<button class="spell-btn" type="submit" name="spell" value="1" title="Heal (5 MP)" aria-label="Heal (5 MP)" aria-keyshortcuts="2"><img src="/static/images/skills/heal.png" width="44" height="44" alt=""><span class="spell-mp" aria-hidden="true">5</span></button>'
expect_body '<button class="spell-btn" type="submit" name="spell" value="6" title="Hurt (5 MP)" aria-label="Hurt (5 MP)" aria-keyshortcuts="3"><img src="/static/images/skills/hurt.png" width="44" height="44" alt=""><span class="spell-mp" aria-hidden="true">5</span></button>'
expect_no_body 'name="userspell"'; expect_no_body 'value="Spell"'
expect_no_body 'name="useritem"'; expect_no_body 'value="Use Item"'      # items are icon buttons too (2.4)
t_get /static/images/skills/heal.png;    expect_status 200; expect_header '^content-type: image/png'
t_get /static/images/skills/default.png; expect_status 200
# a spell whose icon file is gone shows default.png (restored right after)
mv "$T/public/images/skills/hurt.png" "$T/hurt.png"
t_get /fight; expect_body 'aria-keyshortcuts="3"><img src="/static/images/skills/default.png" width="44" height="44" alt=""><span class="spell-mp" aria-hidden="true">5</span>'
mv "$T/hurt.png" "$T/public/images/skills/hurt.png"
# MP short: greyed out (disabled), and the server refuses a direct POST anyway
f_sql "UPDATE users SET currentmp = 4"
t_get /fight
expect_body 'name="spell" value="1" title="Heal (5 MP)" aria-label="Heal (5 MP)" aria-keyshortcuts="2" disabled><img'
expect_body 'name="spell" value="6" title="Hurt (5 MP)" aria-label="Hurt (5 MP)" aria-keyshortcuts="3" disabled><img'
t_round "csrf=$CS&spell=1"; expect_body 'You do not have enough Magic Points'; f_is currentmp 4
f_sql "UPDATE users SET currentmp = 6"
t_get /fight; expect_no_body ' disabled><img'
# the refusals of the old select hold for the button's value too
FIGHT=$(f_col "$T_ROUND")
t_round "csrf=$CS&spell=0";   expect_body 'You must select a spell first.'
t_round "csrf=$CS&spell=";    expect_body 'You must select a spell first.'
t_round "csrf=$CS&spell=abc"; expect_body 'You must select a spell first.'
t_round "csrf=$CS&spell=11";  expect_body 'You have not yet learned this spell.'
t_round "csrf=$CS&spell=999"; expect_body 'You have not yet learned this spell.'
t_round "csrf=$CS&spell=$(t_enc "1' OR '1'='1")"; expect_body 'You have not yet learned this spell.'
t_round "csrf=$CS&spell=6&userspell=0"; expect_body 'You must select a spell first.'   # the old form's select wins
f_is currentmp 6; f_is "$T_ROUND" "$FIGHT"
# casting with the button: the same as the old select
t_round "csrf=$CS&spell=1"
expect_status 200; expect_body 'You have cast the Heal spell, and gained 10 Hit Points.'
f_is currentmp 1
# after the round the page shows the new MP: both buttons greyed out
expect_body 'name="spell" value="1" title="Heal (5 MP)" aria-label="Heal (5 MP)" aria-keyshortcuts="2" disabled><img'
# no spells: no spell buttons; the keys they had (an earlier fight settled the hotbar) stay,
# greyed
t_spells fighter ""
t_get /fight; expect_no_body 'name="spell"'
expect_body '<li class="hotbar-slot hotbar-gone"><kbd class="hotkey" aria-hidden="true">2</kbd><span class="spell-tip spell-tip-short" data-tip><span class="spell-btn" role="img" title="Heal (not known)" aria-label="Heal (not known)"><img src="/static/images/skills/heal.png" width="44" height="44" alt=""></span><template class="tip"><div class="tip-title">Heal</div>'
t_spells fighter 1,6,11
t_fight_clear fighter

t_section "fight: death"
t_fight fighter 146 30000
f_sql "UPDATE users SET base_attack = 1 - strength, currenthp = 1, base_maxhp = 30,
	dexterity = 0, base_defense = 0, gold = 101, latitude = 40, longitude = -40"
t_get /fight; CS=$(t_csrf)
t_round "csrf=$CS&fight=Fight"
expect_status 200; expect_body 'The monster attacks you for'; expect_body '<b>You have died.</b>'
expect_no_body 'name="fight"'
f_is currentaction 'In Town'; f_is gold 51; f_is currenthp 8; f_is latitude 0; f_is longitude 0
f_is "$T_ROUND" 0; f_is "$T_MONSTER" 0
t_get /; expect_status 200; expect_body 'class="town-banners"'
# the fight as it ended stays on its page (GET /fight) until the player moves on
t_get /fight; expect_status 200; expect_body '<b>You have died.</b>'; expect_body 'The monster attacks you for'
expect_no_body 'name="fight"'; f_is gold 51
t_get /victory; expect_redirect /

t_section "fight: death on a spell turn keeps the MP spent, clears buffs"
t_spells fighter 1,6,11,14
t_fight fighter 146 30000
t_fight_status fighter 1 uber_defense 'pct=i:25'
f_sql "UPDATE users SET currenthp = 1, currentmp = 30, base_maxmp = 50, gold = 100"
t_round "csrf=$CS&spell=Spell&userspell=14"
expect_status 200; expect_body 'You have cast the Craze spell'; expect_body '<b>You have died.</b>'
f_is currentaction 'In Town'; f_is currentmp 20; f_is "$T_UBER_DAMAGE" 0; f_is "$T_UBER_DEFENSE" 0
f_is gold 50; f_is currenthp 8

t_section "fight: run away blocked, fatal"
t_fight fighter 146 30000
t_fight_status fighter 1 uber_damage 'pct=i:10'; t_fight_status fighter 1 uber_defense 'pct=i:10'
f_sql "UPDATE users SET currenthp = 1, currentmp = 7, gold = 101, latitude = 40, longitude = -40"
t_round "csrf=$CS&run=Run"
expect_status 200; expect_body 'You tried to run away, but were blocked in front!'
expect_body 'The monster attacks you for'; expect_body '<b>You have died.</b>'; expect_no_body 'name="run"'
f_is currentaction 'In Town'; f_is gold 51; f_is currenthp 8; f_is latitude 0; f_is longitude 0
f_is "$T_ROUND" 0; f_is "$T_MONSTER" 0; f_is "$T_MONSTER_HP" 0
f_is "$T_UBER_DAMAGE" 0; f_is "$T_UBER_DEFENSE" 0; f_is currentmp 7
t_get /; expect_status 200; expect_body 'class="town-banners"'

t_section "fight: use an item"
# Herbs (heal_hp 30) and an Ether (heal_mp 30) in the bag; Red Slime awake, no immunity. Each
# consumable is an icon button (item=<items id>) with its quantity as a badge, greyed out
# when its can_use refuses now; the form before 2.4 (item=Use Item&useritem=<id>) still works
t_items_clear fighter
t_give fighter herb 3; t_give fighter ether 1; t_give fighter stick 1
t_calm fighter   # (the slime's attack after the herb: its damage without a battlefield)
t_fight fighter 2 50
f_sql "UPDATE users SET currenthp = 10, base_maxhp = 100, currentmp = 0,
	base_maxmp = 50, base_attack = 0, base_defense = 0"
t_get /fight; CS=$(t_csrf)
expect_body '<ol class="hotbar-slots">'
expect_body '<button class="spell-btn" type="submit" name="item" value="66" title="Herb (x3)" aria-label="Herb (x3)" aria-keyshortcuts="6"><img src="/static/images/items/herb.png" width="44" height="44" alt=""><span class="item-badge" aria-hidden="true">3</span></button>'
expect_body '<button class="spell-btn" type="submit" name="item" value="68" title="Ether (x1)" aria-label="Ether (x1)" aria-keyshortcuts="7"><img src="/static/images/items/ether.png" width="44" height="44" alt=""><span class="item-badge" aria-hidden="true">1</span></button>'
expect_body '<template class="tip"><div class="tip-title"><img class="tip-icon" src="/static/images/items/herb.png" width="20" height="20" alt="">Herb</div><div class="tip-meta">Consumable · x3 · In fights and in town</div>'
expect_no_body 'title="Stick'; expect_no_body 'name="use_gear"'; expect_no_body 'class="fight-gear"'
FIGHT=$(f_col "$T_ROUND")
t_round "csrf=$CS&item=Use+Item&useritem=0";  expect_body 'You must select an item first.'
t_round "csrf=$CS&item=Use+Item&useritem=67"; expect_body 'You do not have this item.'
t_round "csrf=$CS&item=Use+Item";             expect_body 'You must select an item first.'
t_round "csrf=$CS&item=Use+Item&useritem=1";  expect_body 'This item cannot be used.'   # a stick
t_round "csrf=$CS&item=Use+Item&useritem=$(t_enc "66 OR 1=1")"; expect_body 'You do not have this item.'
f_is "$T_ROUND" "$FIGHT"; f_is "$T_ITEMS" "herbx3,ether,stick"
t_round "csrf=$CS&item=Use+Item&useritem=66"
expect_status 200; expect_body 'You have used the Herb, and gained 30 Hit Points.'; expect_body 'The monster attacks you for'
f_is "$T_ITEMS" "herbx2,ether,stick"; f_is "$T_ROUND" $((FIGHT + 1))
[ "$(f_col currenthp)" -le 40 ] && [ "$(f_col currenthp)" -ge 30 ] && t_ok || t_fail "herb in a fight: hp $(f_col currenthp)"
expect_body 'name="item" value="66" title="Herb (x2)" aria-label="Herb (x2)" aria-keyshortcuts="6"><img'
# at full HP: greyed out; a POST is refused, nothing used, the monster doesn't act
f_sql "UPDATE users SET currenthp = 100"
t_get /fight; expect_body 'name="item" value="66" title="Herb (x2)" aria-label="Herb (x2)" aria-keyshortcuts="6" disabled><img'
expect_body 'name="item" value="68" title="Ether (x1)" aria-label="Ether (x1)" aria-keyshortcuts="7"><img'
FIGHT=$(f_col "$T_ROUND")
t_round "csrf=$CS&item=Use+Item&useritem=66"; expect_body 'Your Hit Points are already full.'
expect_body '<p class="fight-note error" role="alert">'; expect_body 'name="fight"'; f_is "$T_ITEMS" "herbx2,ether,stick"; f_is "$T_ROUND" "$FIGHT"
t_round "csrf=$CS&item=66"; expect_body 'Your Hit Points are already full.'; f_is "$T_ROUND" "$FIGHT"
# the icon button's contract: item=<id>; the last one of a stack: the row goes
t_round "csrf=$CS&item=68"; expect_body 'You have used the Ether, and gained 30 Magic Points.'
f_is currentmp 30; f_is "$T_ITEMS" "herbx2,stick"
expect_no_body 'title="Ether'
t_round "csrf=$CS&item=0";  expect_body 'You must select an item first.'
t_round "csrf=$CS&item=68"; expect_body 'You do not have this item.'
t_items_clear fighter
t_get /fight; expect_no_body 'name="item"'   # no usable items: no item buttons
t_items_clear fighter

t_section "fight: item drop (the drop card, 3.1)"
t_fight_clear fighter
f_sql "UPDATE users SET currentaction = 'Exploring',
	dropcode = 34, base_maxhp = 30, currenthp = 30, base_maxmp = 50, base_maxtp = 20, strength = 7, base_attack = 3,
	dexterity = 4, base_defense = 0"
# without its victory page: the card on a page of its own, the purchase's look: the picture,
# the name with its tooltip, what it gives, the choices
t_get /drop; expect_status 200; expect_body 'class="buy drop-offer"'
expect_body 'src="/static/images/items/life_pebble.png"'; expect_body '>Life Pebble<template class="tip">'
expect_body '<li>Max HP <b>+10</b></li>'
# an accessory: into the first empty accessory slot, no slot to choose
expect_body 'name="equip" value="accessory1">Equip it</button> <span class="drop-why">It goes into accessory slot 1.</span>'
expect_no_body 'value="accessory2"'
expect_body 'name="take" value="Take">Put it in your bag</button>'; expect_body 'name="leave" value="Leave">Leave it</button>'
CS=$(t_csrf)
t_post /drop "take=Take"; expect_status 403
f_is dropcode 34
t_post /drop "csrf=$CS&take=Take"; expect_body 'The Life Pebble is in your bag.'
f_is dropcode 0; f_is "$T_ITEMS" "life_pebble"
expect_stats "30 50 20 7 4 10 4" "a drop in the bag adds nothing"
t_get /drop; expect_redirect /
# equipped at once: an accessory into the first empty slot
f_sql "UPDATE users SET dropcode = 46"
t_post /drop "csrf=$CS&equip=accessory1"; expect_body 'You equipped the Demon&#39;s Sin.'
f_is dropcode 0; f_is "$T_ITEMS" "life_pebble,demons_sin@accessory1"
# all three taken: a choice per slot, in place of what is there (into the bag)
t_give fighter ruby 1 accessory2; t_give fighter pearl 1 accessory3
f_sql "UPDATE users SET dropcode = 37"
t_get /drop; expect_body 'name="equip" value="accessory2">Equip it in place of your Ruby</button> <span class="drop-why">Your Ruby goes into your bag.</span>'
expect_body 'value="accessory1"'; expect_body 'value="accessory3"'
t_post /drop "csrf=$CS&equip=accessory2"; expect_body 'You equipped the Magic Pebble. Your Ruby is in your bag.'
f_is "$T_ITEMS" "life_pebble,demons_sin@accessory1,ruby,pearl@accessory3,magic_pebble@accessory2"
# a weapon in place of the one worn, compared with it
t_items_clear fighter; t_give fighter stick 1 weapon
f_sql "UPDATE users SET dropcode = 2"
t_get /drop; expect_body '<th scope="col">Your Stick</th><th scope="col">The Branch</th>'
expect_body 'name="equip" value="weapon">Equip it</button> <span class="drop-why">Your Stick goes into your bag.</span>'
# a slot that isn't the item's: refused, the drop still there
t_post /drop "csrf=$CS&equip=armor"; expect_body 'Choose where to equip the Branch.'; f_is dropcode 2
t_post /drop "csrf=$CS&equip=weapon"; expect_body 'You equipped the Branch. Your Stick is in your bag.'
f_is "$T_ITEMS" "stick,branch@weapon"
# leave it
f_sql "UPDATE users SET dropcode = 46"
t_get /drop; expect_body '<li>Max HP <b>-50</b></li>'; expect_body '<li>Strength <b>+50</b></li>'
t_post /drop "csrf=$CS&leave=Leave"; expect_body 'You left the Demon&#39;s Sin behind.'
f_is dropcode 0; f_is "$T_ITEMS" "stick,branch@weapon"
t_items_clear fighter
# a full bag: equipping into an empty slot needs no room; into the bag, "Make room" opens
# the bag (a dialog) to discard something (not a quest item, not someone else's)
for k in stick branch club dagger hatchet axe brand poleaxe broadsword battle_axe claymore life_pebble; do t_give fighter "$k"; done
f_sql "UPDATE users SET dropcode = 46"
t_get /drop; expect_body '<a class="drop-room-link" href="/drop/room" data-modal>Make room</a>'; expect_no_body 'name="take"'
expect_body 'name="equip" value="accessory1"'
t_get /drop/room -H 'X-DK-Modal: 1'; expect_header '^x-dk-modal: 1'
expect_body 'Your bag is full. Discard something to take the <b>Demon&#39;s Sin</b>'; expect_body 'name="discard" value="'
t_post /drop "csrf=$CS&take=x"; expect_body 'Your bag is full. Make room in it first, or leave the Demon&#39;s Sin.'
OTHER=$(t_sql "SELECT min(id) FROM user_items WHERE user_id <> (SELECT id FROM users WHERE username = 'fighter')")
[ -n "$OTHER" ] && { t_post /drop "csrf=$CS&take=x&discard=$OTHER"; expect_body 'Choose an item from your bag to discard.'; }
STICK=$(t_sql "SELECT ui.id FROM user_items ui JOIN items i ON i.id = ui.item_id WHERE i.key = 'stick' AND ui.user_id = (SELECT id FROM users WHERE username = 'fighter')")
t_post /drop "csrf=$CS&take=x&discard=$STICK"; expect_body 'You discarded the Stick. The Demon&#39;s Sin is in your bag.'
f_is dropcode 0
[ "$(t_sql "SELECT count(*) FROM user_items WHERE equipped IS NULL AND user_id = (SELECT id FROM users WHERE username = 'fighter')")" = 12 ] \
	&& t_ok || t_fail "bag not full after the swap"
f_is "(SELECT count(*) FROM user_items ui JOIN items i ON i.id = ui.item_id WHERE ui.user_id = users.id AND i.key IN ('stick', 'demons_sin'))" 1
# with the bag full, a worn piece can't be replaced (it would have nowhere to go)
t_sql "UPDATE user_items SET equipped = 'weapon' WHERE id = (SELECT min(ui.id) FROM user_items ui JOIN items i ON i.id = ui.item_id
	WHERE i.key = 'club' AND ui.user_id = (SELECT id FROM users WHERE username = 'fighter'))"
t_give fighter herb 1
f_sql "UPDATE users SET dropcode = 2"
t_get /drop; expect_body '<button type="button" disabled>Equip it</button> <span class="drop-why">No room in your bag for your Club.</span>'
t_post /drop "csrf=$CS&equip=weapon"; expect_body 'Your bag is full: there is no room for your Club.'; f_is dropcode 2
f_sql "UPDATE users SET dropcode = 0"
t_items_clear fighter

t_section "fight: victory drops come from the items with a drop level"
# Blue Slime (level 1): only the Life Pebble and the Magic Pebble can drop
for _ in $(seq 1 60); do
	t_fight fighter 1 0
	f_sql "UPDATE users SET dropcode = 0, level = 100, experience = 0"
	t_fight_win
	[ "$(f_col dropcode)" != 0 ] && break
done
case $(f_col dropcode) in
	34|37) t_ok
		# the drop on the victory page: its card; taken there, the page says what became of it
		expect_body '<p class="victory-drop-head">It left something behind:</p>'; expect_body 'class="buy drop-offer"'
		t_post /drop "csrf=$(t_csrf)&take=Take"; expect_redirect /victory
		t_get /victory; expect_body 'is in your bag.</p>'; expect_no_body 'class="buy drop-offer"'
		t_get /drop; expect_redirect / ;;
	0) t_ok ;;   # 1 in 30 per victory: no drop in 60 tries is possible (~13%)
	*) t_fail "dropped item $(f_col dropcode) is not a level-1 drop" ;;
esac
f_sql "UPDATE users SET dropcode = 0, level = 3"

t_section "fight: victory stores negative experience as 0 (MySQL UNSIGNED)"
# Blue Slime: exp rand(0,1) -> at least 1; -500% bonus: 1 + ceil(-5) = -4; gold 1
t_fight fighter 1 0
f_sql "UPDATE users SET experience = 0, gold = 0, base_exp_bonus = -500, base_gold_bonus = 0, level = 2"
t_fight_win; expect_status 200; expect_body 'You gain -4 experience.'; expect_body 'You gain 1 gold.'
f_is experience 0; f_is gold 1; f_is level 2

t_section "fight: gold bonus is a percentage of the gold"
# Blue Slime: exp 1 + ceil(5 * 1) = 6; gold 1 + ceil(1 * 1) = 2 (legacy: of the exp, 7)
t_fight fighter 1 0
f_sql "UPDATE users SET experience = 0, gold = 0, base_exp_bonus = 500, base_gold_bonus = 100"
t_fight_win; expect_body 'You gain 6 experience.'; expect_body 'You gain 2 gold.'
f_is experience 6; f_is gold 2

t_section "fight: several levels at once"
# Blue Slime gives exactly 1 exp: 53 + 1 = 54 reaches Warrior levels 2 (18) and 3 (54)
t_fight fighter 1 0
f_sql "UPDATE users SET experience = 53, level = 1, base_maxhp = 15, base_maxmp = 0, base_maxtp = 10,
	strength = 5, dexterity = 5, base_attack = 0, base_defense = 0,
	base_exp_bonus = 0, base_gold_bonus = 0"
t_spells fighter ""
t_fight_win; expect_body '<title>Courage and Wit have served thee well!</title>'
expect_body 'You have gained 2 levels!'; expect_no_body 'gained a level'
expect_body 'You gain 4 hit points.'; expect_body 'You gain 7 magic points.'
expect_body 'You gain 3 travel points.'; expect_body 'You gain 5 strength.'
expect_body 'You gain 3 dexterity.'
[ "$(t_sql "SELECT count(*) FROM class_spells WHERE class_id = 2 AND level IN (2, 3)")" -ge 1 ] && expect_body 'You have learned ' || expect_no_body 'learned a new spell'
f_is level 3; f_is base_maxhp 19; f_is base_maxmp 7; f_is base_maxtp 13; f_is strength 10; f_is dexterity 8
f_is "strength + base_attack" 10; f_is "dexterity + base_defense" 8; f_is experience 54
# what the Warrior learns at levels 2 and 3
f_is "$T_KNOWN" "$(t_sql "SELECT group_concat(spell_id) FROM (SELECT spell_id FROM class_spells WHERE class_id = 2 AND level IN (2, 3) ORDER BY spell_id)")"

t_section "fight: milestone level (formula experience, TP and HP bonus)"
# Warrior level 10 needs 2368 (lib/leveling.lua; the original table said 2369): 2367 + 1.
# Gains: HP 0 + milestone 10, MP 2, TP floor(10/30) + 2, strength 6, dexterity 3.
t_fight fighter 1 0
f_sql "UPDATE users SET experience = 2366, level = 9, base_maxhp = 50, base_maxmp = 20, base_maxtp = 20,
	strength = 30, dexterity = 30, base_attack = 0, base_defense = 0,
	base_exp_bonus = 0, base_gold_bonus = 0"
t_spells fighter 1
t_fight_win; expect_body 'You gain 1 experience.'; expect_no_body 'gained a level'
f_is level 9; f_is experience 2367
t_fight fighter 1 0
t_fight_win; expect_body 'You have gained a level!'
expect_body 'You gain 10 hit points.'; expect_body 'You gain 2 magic points.'
expect_body 'You gain 2 travel points.'; expect_body 'You gain 6 strength.'
expect_body 'You gain 3 dexterity.'
# a spell at level 10 is announced, none is not
if [ "$(t_sql "SELECT count(*) FROM class_spells WHERE class_id = 2 AND level = 10")" = 0 ]; then expect_no_body 'learned a new spell'; else expect_body 'You have learned '; fi
f_is level 10; f_is base_maxhp 60; f_is base_maxmp 22; f_is base_maxtp 22; f_is strength 36; f_is dexterity 33

fi
