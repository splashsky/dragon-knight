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

# an encounter just began (monster not picked yet): no free victory
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 1, currentmonster = 0, currentmonsterhp = 0"
t_get /victory; expect_redirect /
f_is currentfight 1
t_get /;        expect_redirect /fight

t_section "fight: monster selection"
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 1, latitude = -50, longitude = 7,
	currenthp = 1000, base_maxhp = 1000"
t_get /fight;   expect_status 200; expect_body 'title_fighting.gif'; expect_body 'You are fighting a <b>'
expect_body "Monster's HP: "; expect_body 'name="fight"'; expect_body 'name="run"'
f_is currentfight 2
lvl=$(t_sql "SELECT m.level FROM users u JOIN monsters m ON m.id = u.currentmonster $FQ")
[ -n "$lvl" ] && [ "$lvl" -ge 9 ] && [ "$lvl" -le 11 ] && t_ok || t_fail "monster level $lvl not in 9..11"
hp=$(f_col currentmonsterhp)
[ "$hp" -gt 0 ] && t_ok || t_fail "monster hp $hp"
t_post /fight "fight=Fight"; expect_status 403          # CSRF required
f_is currentfight 2
t_get /fight; expect_body "Monster's HP: $hp"; f_is currentfight 3   # refresh: same monster

t_section "fight: run away"
CS=$(t_csrf)
DEX=$(f_col dexterity)
# (no gear: the effective stats are the base ones; defense power = dexterity + base_defense)
# dexterity 10000: rand(4,10) + 100 beats rand(1,5) + ceil(sqrt(maxdam)) of any level 9-11 monster
f_sql "UPDATE users SET dexterity = 10000, currentuberdamage = 10, currentuberdefense = 20"
t_post /fight "csrf=$CS&run=Run"; expect_redirect /
f_is currentaction Exploring; f_is currentfight 0; f_is currentmonster 0; f_is currentmonsterhp 0
f_is currentuberdamage 0; f_is currentuberdefense 0
t_get /fight; expect_body 'Cheat attempt detected.'
t_get /victory; expect_redirect /

t_section "fight: run away blocked"
# Lucifuge (maxdam 600): ceil(sqrt(600)) = 25 beats any run roll with dexterity 0 (max 10);
# no dodge with dexterity 0, and the hit is rand(300,600) - 0
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 151,
	currentmonsterhp = 30000, currentmonstersleep = 0, currentmonsterimmune = 2, dexterity = 0,
	base_defense = 0, currenthp = 5000, base_maxhp = 5000, currentuberdefense = 0"
t_post /fight "csrf=$CS&run=Run"; expect_status 200
expect_body 'You tried to run away, but were blocked in front!'; expect_body "Monster's HP: 30000"
expect_body 'The monster attacks you for'; expect_body 'name="run"'; expect_no_body 'You have died.'
f_is currentaction Fighting; f_is currentfight 3; f_is currentmonster 151; f_is currentmonsterhp 30000
hp=$(f_col currenthp)
[ "$hp" -ge 4400 ] && [ "$hp" -le 4700 ] && t_ok || t_fail "blocked run: currenthp $hp not in 4400..4700"
f_sql "UPDATE users SET currentaction = 'Exploring', currentfight = 0, currentmonster = 0,
	currentmonsterhp = 0, currentmonsterimmune = 0, dexterity = $DEX"

t_section "fight: victory + level up"
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 1, latitude = 0, longitude = 0,
	base_attack = 495, currenthp = 500, base_maxhp = 500, experience = 17, gold = 100"
t_get /fight; CS=$(t_csrf)
for _ in $(seq 1 30); do
	t_post /fight "csrf=$CS&fight=Fight"
	[ "$STATUS" = 302 ] && break
done
expect_redirect /victory
f_is currentmonsterhp 0
t_get /victory; expect_status 200
expect_body 'Congratulations. You have defeated the'; expect_body 'You have gained a level!'
expect_body 'You gain 2 hit points.'; expect_body 'You gain 4 magic points.'; expect_body 'You have learned a new spell.'
expect_body '<title>Courage and Wit have served thee well!</title>'
f_is level 2; f_is base_maxhp 502; f_is base_maxmp 4; f_is base_maxtp 11; f_is strength 7; f_is dexterity 6
f_is "strength + base_attack" 502; f_is "dexterity + base_defense" 6; f_is "$T_KNOWN" 1
expect_stats "502 4 11 7 6 502 6" "level-up stats"
f_is currentaction Exploring; f_is currentfight 0; f_is currentmonster 0
[ "$(f_col experience)" -ge 18 ] && t_ok || t_fail "experience not awarded"
[ "$(f_col gold)" -gt 100 ] && t_ok || t_fail "gold not awarded"
t_get /victory; expect_redirect /                     # only once

t_section "fight: victory without level up"
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 1, currentuberdamage = 10"
t_get /fight; CS=$(t_csrf)
for _ in $(seq 1 30); do
	t_post /fight "csrf=$CS&fight=Fight"
	[ "$STATUS" = 302 ] && break
done
expect_redirect /victory
t_get /victory; expect_body '<title>Victory!</title>'; expect_no_body 'gained a level'
f_is level 2; f_is currentuberdamage 0

t_section "fight: spells"
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 1, currenthp = 100, currentmp = 10, base_maxmp = 50"
t_get /fight; CS=$(t_csrf)
expect_body '<option value="1">Heal</option>'
t_post /fight "csrf=$CS&spell=Spell&userspell=0"; expect_body 'You must select a spell first.'
t_post /fight "csrf=$CS&spell=Spell";            expect_body 'You must select a spell first.'
t_post /fight "csrf=$CS&spell=Spell&userspell=6"; expect_body 'You have not yet learned this spell.'
t_post /fight "csrf=$CS&spell=Spell&userspell=$(t_enc "1' OR '1'='1")"; expect_body 'You have not yet learned this spell.'
t_post /fight "csrf=$CS&spell=Spell&userspell=999"; expect_body 'You have not yet learned this spell.'
f_is currentmp 10
t_post /fight "csrf=$CS&spell=Spell&userspell=1"
expect_status 200; expect_body 'You have cast the Heal spell, and gained 10 Hit Points.'
f_is currentmp 5
# heal at (or above) full HP: refused, no MP spent, the monster doesn't act
f_sql "UPDATE users SET currenthp = base_maxhp, currentmp = 10"
FIGHT=$(f_col currentfight)
t_post /fight "csrf=$CS&spell=Spell&userspell=1"; expect_body 'Your Hit Points are already full.'
expect_no_body 'The monster attacks'
f_is currentmp 10; f_is currentfight "$FIGHT"; f_is "currenthp = base_maxhp" 1
f_sql "UPDATE users SET currenthp = base_maxhp + 5"
t_post /fight "csrf=$CS&spell=Spell&userspell=1"; expect_body 'Your Hit Points are already full.'
f_is currentmp 10; f_is "currenthp = base_maxhp + 5" 1
# a spell of an unknown type: refused the same way
t_sql "UPDATE spells SET effects = 'fireball power=9' WHERE id = 1"
f_sql "UPDATE users SET currenthp = 100"
t_post /fight "csrf=$CS&spell=Spell&userspell=1"; expect_body 'This spell cannot be cast.'
f_is currentmp 10; f_is currenthp 100; f_is currentfight "$FIGHT"
t_sql "UPDATE spells SET effects = 'heal_hp amount=10' WHERE id = 1"
f_sql "UPDATE users SET currentmp = 4"
t_post /fight "csrf=$CS&spell=Spell&userspell=1"; expect_body 'You do not have enough Magic Points'
f_is currentmp 4
# sleep spell, then a hurt spell that kills
t_spells fighter 1,6,11
f_sql "UPDATE users SET currentmp = 50, currentmonster = 2, currentmonsterhp = 50, currentmonsterimmune = 0"
t_post /fight "csrf=$CS&spell=Spell&userspell=11"
expect_body 'You have cast the Sleep spell. The monster is asleep.'
if grep -qF 'The monster is still asleep.' "$BODY"; then f_is currentmonstersleep 5
else expect_body 'The monster has woken up.'; f_is currentmonstersleep 0; fi
f_is currentmp 40
f_sql "UPDATE users SET currentmonsterhp = 1"
t_post /fight "csrf=$CS&spell=Spell&userspell=6"; expect_redirect /victory
f_is currentmonsterhp 0; f_is currentmp 35
t_get /victory; expect_body 'You have defeated the Red Slime.'

t_section "fight: death"
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 151,
	currentmonsterhp = 30000, currentmonstersleep = 0, base_attack = 1 - strength, currenthp = 1, base_maxhp = 30,
	dexterity = 0, base_defense = 0, gold = 101, latitude = 40, longitude = -40"
t_get /fight; CS=$(t_csrf)
t_post /fight "csrf=$CS&fight=Fight"
expect_status 200; expect_body 'The monster attacks you for'; expect_body '<b>You have died.</b>'
expect_no_body 'name="fight"'
f_is currentaction 'In Town'; f_is gold 51; f_is currenthp 8; f_is latitude 0; f_is longitude 0
f_is currentfight 0; f_is currentmonster 0
t_get /; expect_status 200; expect_body 'Town Options'

t_section "fight: death on a spell turn keeps the MP spent, clears buffs"
t_spells fighter 1,6,11,14
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 151,
	currentmonsterhp = 30000, currentmonstersleep = 0, currenthp = 1, currentmp = 30, base_maxmp = 50,
	currentuberdamage = 0, currentuberdefense = 25, gold = 100"
t_post /fight "csrf=$CS&spell=Spell&userspell=14"
expect_status 200; expect_body 'You have cast the Craze spell'; expect_body '<b>You have died.</b>'
f_is currentaction 'In Town'; f_is currentmp 20; f_is currentuberdamage 0; f_is currentuberdefense 0
f_is gold 50; f_is currenthp 8

t_section "fight: run away blocked, fatal"
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 151,
	currentmonsterhp = 30000, currentmonstersleep = 0, currenthp = 1, currentmp = 7,
	currentuberdamage = 10, currentuberdefense = 10, gold = 101, latitude = 40, longitude = -40"
t_post /fight "csrf=$CS&run=Run"
expect_status 200; expect_body 'You tried to run away, but were blocked in front!'
expect_body 'The monster attacks you for'; expect_body '<b>You have died.</b>'; expect_no_body 'name="run"'
f_is currentaction 'In Town'; f_is gold 51; f_is currenthp 8; f_is latitude 0; f_is longitude 0
f_is currentfight 0; f_is currentmonster 0; f_is currentmonsterhp 0
f_is currentuberdamage 0; f_is currentuberdefense 0; f_is currentmp 7
t_get /; expect_status 200; expect_body 'Town Options'

t_section "fight: use an item"
# Herbs (heal_hp 30) and an Ether (heal_mp 30) in the bag; Red Slime awake, no immunity
t_items_clear fighter
t_give fighter herb 3; t_give fighter ether 1; t_give fighter stick 1
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 2, currentmonsterhp = 50,
	currentmonstersleep = 0, currentmonsterimmune = 0, currenthp = 10, base_maxhp = 100, currentmp = 0,
	base_maxmp = 50, base_attack = 0, base_defense = 0"
t_get /fight; CS=$(t_csrf)
expect_body '<option value="66">Herb (x3)</option>'; expect_body '<option value="68">Ether (x1)</option>'
expect_no_body '>Stick ('; expect_body 'name="item" value="Use Item"'
FIGHT=$(f_col currentfight)
t_post /fight "csrf=$CS&item=Use+Item&useritem=0";  expect_body 'You must select an item first.'
t_post /fight "csrf=$CS&item=Use+Item&useritem=67"; expect_body 'You do not have this item.'
t_post /fight "csrf=$CS&item=Use+Item";             expect_body 'You must select an item first.'
t_post /fight "csrf=$CS&item=Use+Item&useritem=1";  expect_body 'This item cannot be used.'   # a stick
t_post /fight "csrf=$CS&item=Use+Item&useritem=$(t_enc "66 OR 1=1")"; expect_body 'You do not have this item.'
f_is currentfight "$FIGHT"; f_is "$T_ITEMS" "herbx3,ether,stick"
t_post /fight "csrf=$CS&item=Use+Item&useritem=66"
expect_status 200; expect_body 'You have used the Herb, and gained 30 Hit Points.'; expect_body 'The monster attacks you for'
f_is "$T_ITEMS" "herbx2,ether,stick"; f_is currentfight $((FIGHT + 1))
[ "$(f_col currenthp)" -le 40 ] && [ "$(f_col currenthp)" -ge 30 ] && t_ok || t_fail "herb in a fight: hp $(f_col currenthp)"
expect_body '<option value="66">Herb (x2)</option>'
# at full HP: refused, nothing used, the monster doesn't act
f_sql "UPDATE users SET currenthp = 100"
t_post /fight "csrf=$CS&item=Use+Item&useritem=66"; expect_body 'Your Hit Points are already full.'
expect_no_body 'The monster attacks'; f_is "$T_ITEMS" "herbx2,ether,stick"; f_is currentfight $((FIGHT + 1))
# the last one of a stack: the row goes
t_post /fight "csrf=$CS&item=Use+Item&useritem=68"; expect_body 'You have used the Ether, and gained 30 Magic Points.'
f_is currentmp 30; f_is "$T_ITEMS" "herbx2,stick"
expect_no_body '>Ether ('
t_items_clear fighter

t_section "fight: item drop"
f_sql "UPDATE users SET currentaction = 'Exploring', currentfight = 0, currentmonster = 0, currentmonsterhp = 0,
	dropcode = 34, base_maxhp = 30, currenthp = 30, base_maxmp = 50, base_maxtp = 20, strength = 7, base_attack = 3,
	dexterity = 4, base_defense = 0"
t_get /drop; expect_status 200; expect_body '<b>Life Pebble</b>'; expect_body 'Max HP +10'
expect_body 'name="take" value="Take it"'; expect_body 'name="leave" value="Leave it"'; CS=$(t_csrf)
t_post /drop "take=Take+it"; expect_status 403
f_is dropcode 34
t_post /drop "csrf=$CS&take=Take+it"; expect_body 'The Life Pebble is in your bag.'
f_is dropcode 0; f_is "$T_ITEMS" "life_pebble"
expect_stats "30 50 20 7 4 10 4" "a drop in the bag adds nothing"
t_get /drop; expect_redirect /
# leave it
f_sql "UPDATE users SET dropcode = 46"
t_get /drop; expect_body 'Max HP -50'; expect_body 'Strength +50'
t_post /drop "csrf=$CS&leave=Leave+it"; expect_redirect /
f_is dropcode 0; f_is "$T_ITEMS" "life_pebble"
# a full bag: discard something first (not a quest item, not someone else's), or leave it
for k in stick branch club dagger hatchet axe brand poleaxe broadsword battle_axe claymore; do t_give fighter "$k"; done
f_sql "UPDATE users SET dropcode = 46"
t_get /drop; expect_body 'Your bag is full.'; expect_body 'name="discard"'
expect_body 'name="take" value="Discard it and take the Demon&#39;s Sin"'
t_post /drop "csrf=$CS&take=x"; expect_body 'Your bag is full. Choose an item to discard first'
OTHER=$(t_sql "SELECT min(id) FROM user_items WHERE user_id <> (SELECT id FROM users WHERE username = 'fighter')")
[ -n "$OTHER" ] && { t_post /drop "csrf=$CS&take=x&discard=$OTHER"; expect_body 'Please go back and select an item from your bag'; }
STICK=$(t_sql "SELECT ui.id FROM user_items ui JOIN items i ON i.id = ui.item_id WHERE i.key = 'stick' AND ui.user_id = (SELECT id FROM users WHERE username = 'fighter')")
t_post /drop "csrf=$CS&take=x&discard=$STICK"; expect_body 'You discarded the Stick. The Demon&#39;s Sin is in your bag.'
f_is dropcode 0
[ "$(t_sql "SELECT count(*) FROM user_items WHERE equipped IS NULL AND user_id = (SELECT id FROM users WHERE username = 'fighter')")" = 12 ] \
	&& t_ok || t_fail "bag not full after the swap"
f_is "(SELECT count(*) FROM user_items ui JOIN items i ON i.id = ui.item_id WHERE ui.user_id = users.id AND i.key IN ('stick', 'demons_sin'))" 1
t_items_clear fighter

t_section "fight: victory drops come from the items with a drop level"
# Blue Slime (level 1): only the Life Pebble and the Magic Pebble can drop
for _ in $(seq 1 60); do
	f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 1, currentmonsterhp = 0,
		dropcode = 0, level = 100, experience = 0"
	t_get /victory
	[ "$(f_col dropcode)" != 0 ] && break
done
case $(f_col dropcode) in
	34|37) t_ok; expect_body 'This monster has dropped an item. <a href="/drop">Click here</a> to reveal and take the item' ;;
	0) t_ok ;;   # 1 in 30 per victory: no drop in 60 tries is possible (~13%)
	*) t_fail "dropped item $(f_col dropcode) is not a level-1 drop" ;;
esac
f_sql "UPDATE users SET dropcode = 0, level = 3"

t_section "fight: victory stores negative experience as 0 (MySQL UNSIGNED)"
# Blue Slime: exp rand(0,1) -> at least 1; -500% bonus: 1 + ceil(-5) = -4; gold 1
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 1,
	currentmonsterhp = 0, experience = 0, gold = 0, base_exp_bonus = -500, base_gold_bonus = 0, level = 2"
t_get /victory; expect_status 200; expect_body 'You gain -4 experience.'; expect_body 'You gain 1 gold.'
f_is experience 0; f_is gold 1; f_is level 2

t_section "fight: gold bonus is a percentage of the gold"
# Blue Slime: exp 1 + ceil(5 * 1) = 6; gold 1 + ceil(1 * 1) = 2 (legacy: of the exp, 7)
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 1,
	currentmonsterhp = 0, experience = 0, gold = 0, base_exp_bonus = 500, base_gold_bonus = 100"
t_get /victory; expect_body 'You gain 6 experience.'; expect_body 'You gain 2 gold.'
f_is experience 6; f_is gold 2

t_section "fight: several levels at once"
# Blue Slime gives exactly 1 exp: 53 + 1 = 54 reaches Warrior levels 2 (18) and 3 (54)
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 1,
	currentmonsterhp = 0, experience = 53, level = 1, base_maxhp = 15, base_maxmp = 0, base_maxtp = 10,
	strength = 5, dexterity = 5, base_attack = 0, base_defense = 0,
	base_exp_bonus = 0, base_gold_bonus = 0"
t_spells fighter ""
t_get /victory; expect_body '<title>Courage and Wit have served thee well!</title>'
expect_body 'You have gained 2 levels!'; expect_no_body 'gained a level'
expect_body 'You gain 4 hit points.'; expect_body 'You gain 7 magic points.'
expect_body 'You gain 3 travel points.'; expect_body 'You gain 5 strength.'
expect_body 'You gain 3 dexterity.'; expect_body 'You have learned a new spell.'
f_is level 3; f_is base_maxhp 19; f_is base_maxmp 7; f_is base_maxtp 13; f_is strength 10; f_is dexterity 8
f_is "strength + base_attack" 10; f_is "dexterity + base_defense" 8; f_is "$T_KNOWN" 1; f_is experience 54

t_section "fight: milestone level (formula experience, TP and HP bonus)"
# Warrior level 10 needs 2368 (lib/leveling.lua; the original table said 2369): 2367 + 1.
# Gains: HP 0 + milestone 10, MP 2, TP floor(10/30) + 2, strength 6, dexterity 3.
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 1,
	currentmonsterhp = 0, experience = 2366, level = 9, base_maxhp = 50, base_maxmp = 20, base_maxtp = 20,
	strength = 30, dexterity = 30, base_attack = 0, base_defense = 0,
	base_exp_bonus = 0, base_gold_bonus = 0"
t_spells fighter 1
t_get /victory; expect_body 'You gain 1 experience.'; expect_no_body 'gained a level'
f_is level 9; f_is experience 2367
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 1, currentmonsterhp = 0"
t_get /victory; expect_body 'You have gained a level!'
expect_body 'You gain 10 hit points.'; expect_body 'You gain 2 magic points.'
expect_body 'You gain 2 travel points.'; expect_body 'You gain 6 strength.'
expect_body 'You gain 3 dexterity.'; expect_no_body 'learned a new spell'
f_is level 10; f_is base_maxhp 60; f_is base_maxmp 22; f_is base_maxtp 22; f_is strength 36; f_is dexterity 33

fi
