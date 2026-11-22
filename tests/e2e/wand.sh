# tests/e2e/wand.sh :: the first item with an effect (2.4): Magic Bolt, the Mage's starting
# spell and MP, the Wand (bought in Midworld, equipped, cast from its fight button with a
# charge instead of MP, refused at 0 charges or from the bag), the inn recharging equipped
# items only, charged items obtained full (shop, drop, t_give), buying copies up to the
# bag's room, and the help pages. The JSON path of the buttons is in fight_api.sh.
# Sourced by tests/run.sh.

if ! t_has_sql; then
	t_section "wand (skipped: needs sqlite3 or python3)"
else

WQ="WHERE username = 'wizard'"
wd_sql() { t_sql "$1 $WQ"; }
wd_is() {  # wd_is EXPR EXPECTED (an SQL expression on the users row)
	local got; got=$(t_sql "SELECT $1 FROM users $WQ")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$1: expected '$2', got '$got'"; fi
}
wd_wand() {  # wd_wand [bag]: the user's (equipped, or with "bag" the bag's) Wand entry id
	local where="ui.equipped = 'weapon'"
	[ "${1:-}" = bag ] && where="ui.equipped IS NULL"
	t_sql "SELECT min(ui.id) FROM user_items ui JOIN items i ON i.id = ui.item_id JOIN users u ON u.id = ui.user_id
		WHERE u.username = 'wizard' AND i.key = 'wand' AND $where"
}
WD_CHARGES="(SELECT group_concat(k) FROM (SELECT coalesce(ui.equipped, 'bag') || '=' || ui.charges AS k FROM user_items ui
	JOIN items i ON i.id = ui.item_id WHERE ui.user_id = users.id AND i.key = 'wand' ORDER BY ui.id))"
WD_BOLT=$(t_sql "SELECT id FROM spells WHERE key = 'magic_bolt'")
WD_WAND_ITEM=$(t_sql "SELECT id FROM items WHERE key = 'wand'")

t_section "wand: new characters (Magic Bolt, the Mage's 5 MP)"
[ "$WD_BOLT" = 25 ] && t_ok || t_fail "Magic Bolt is spell 25 (got $WD_BOLT)"
[ "$WD_WAND_ITEM" = 71 ] && t_ok || t_fail "the Wand is item 71 (got $WD_WAND_ITEM)"
t_jar wandw; t_reset_jar
t_register wwarrior wpw1 wwarrior@example.com WWarrior 2
t_register wpaladin wpw1 wpaladin@example.com WPaladin 3
t_jar wand; t_reset_jar
t_register wizard wizpw1 wizard@example.com Wizard 1
t_login wizard wizpw1; expect_redirect /
wd_is "currentmp || '|' || base_maxmp || '|' || $T_KNOWN" "5|5|25"
wd_is "(SELECT learned_level FROM user_spells WHERE user_id = users.id AND spell_id = 25)" "1"
[ "$(t_sql "SELECT username || ':' || currentmp || '|' || base_maxmp || '|' || coalesce($T_KNOWN, '') FROM users
	WHERE username IN ('wwarrior', 'wpaladin') ORDER BY username")" = "wpaladin:0|0|
wwarrior:0|0|" ] && t_ok || t_fail "the Warrior and the Paladin start with no MP and no spell"
t_get /; expect_body 'data-meter="mp" data-max="5"><b>5</b>/5</span>'
expect_no_body "action=\"/spell/$WD_BOLT\""   # fight-only: not a Fast Spell
t_get /help/levels; expect_body '<tr><td>1</td><td>0</td><td>15</td><td>5</td><td>5</td><td>5</td><td>5</td><td>Magic Bolt</td></tr>'
expect_body '<tr><td>1</td><td>0</td><td>15</td><td>0</td><td>5</td><td>5</td><td>5</td><td><span class="light">None</span></td></tr>'
t_get /help/spells; expect_body '>Magic Bolt<br>'
t_get /help; expect_body 'hurt spells (Magic Bolt from the start)</li>'
# level 2: the same +5 MP as before 2.4 (and Heal)
wd_sql "UPDATE users SET experience = 14"
t_fight wizard 1 1
wd_sql "UPDATE users SET base_attack = 100"
t_round "csrf=$(t_csrf)&fight=Fight"; expect_redirect /victory
t_get /victory; expect_body 'You have gained a level!'
wd_is "level || '|' || base_maxmp || '|' || $T_KNOWN" "2|10|1,25"
wd_sql "UPDATE users SET base_attack = 0, currentaction = 'In Town', latitude = 0, longitude = 0, currenthp = base_maxhp"

t_section "wand: Magic Bolt in a fight"
# Red Slime (no immunity): 1 MP, 3-4 damage
t_fight wizard 2 50
wd_sql "UPDATE users SET currentmp = 5, currenthp = 100, base_maxhp = 100"
t_get /fight; CS=$(t_csrf)
expect_body "<button class=\"spell-btn\" type=\"submit\" name=\"spell\" value=\"$WD_BOLT\" title=\"Magic Bolt (1 MP)\" aria-label=\"Magic Bolt (1 MP)\" aria-keyshortcuts=\"3\"><img src=\"/static/images/skills/magic_bolt.png\" width=\"44\" height=\"44\" alt=\"\"><span class=\"spell-mp\" aria-hidden=\"true\">1</span></button>"
t_round "csrf=$CS&spell=$WD_BOLT"; expect_body 'You have cast the Magic Bolt spell for '
HP=$(t_sql "SELECT $T_MONSTER_HP FROM users $WQ")
{ [ "$HP" = 46 ] || [ "$HP" = 47 ]; } && t_ok || t_fail "Magic Bolt: 3-4 damage (monster HP $HP)"
wd_is currentmp 4
# Silver Slime: immune
t_fight wizard 9 5
wd_sql "UPDATE users SET currenthp = 1000, base_maxhp = 1000"   # (it hits up to 100)
t_round "csrf=$CS&spell=$WD_BOLT"; expect_body 'You have cast the Magic Bolt spell, but the monster is immune to it.'
wd_is "$T_MONSTER_HP || '|' || currentmp" "5|3"
wd_sql "UPDATE users SET currentmp = 0"
t_get /fight; expect_body "value=\"$WD_BOLT\" title=\"Magic Bolt (1 MP)\" aria-label=\"Magic Bolt (1 MP)\" aria-keyshortcuts=\"3\" disabled>"
t_fight_clear wizard
wd_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0"

t_section "wand: bought in Midworld"
t_items_clear wizard
wd_sql "UPDATE users SET gold = 200, base_maxhp = 17, currenthp = 17"
t_get /shop; TC=$(t_csrf)
expect_body "<a class=\"spell-btn\" href=\"/shop/buy/$WD_WAND_ITEM\" data-modal title=\"Wand (75 gold)\" aria-label=\"Wand (75 gold)\"><img src=\"/static/images/items/wand.png\" width=\"44\" height=\"44\" alt=\"\"></a><template class=\"tip\">"
expect_body '<b class="shop-tip-gold">75 gold</b></div><div class="shop-tip-note">You have 200 gold</div><table class="shop-tip-stats"><tr><th scope="row">Attack Power</th><td class="shop-tip-value">+2</td><td class="shop-tip-delta"></td></tr></table><ul class="shop-tip-effects"><li>Casts Magic Bolt</li><li>5 Charges</li></ul>'
t_get "/shop/buy/$WD_WAND_ITEM"; expect_body '<b>Buy and equip</b>'
expect_body '<span class="buy-tile"><img src="/static/images/items/wand.png" width="48" height="48" alt=""></span>'
expect_body '<ul class="buy-effects">'; expect_body '<li>Casts Magic Bolt</li>'; expect_body '<li>5 Charges</li>'
t_post "/shop/buy/$WD_WAND_ITEM" "csrf=$TC&submit=Yes"; expect_body 'Thank you for purchasing this item.'
wd_is "gold || '|' || $T_ITEMS || '|' || $WD_CHARGES" "125|wand@weapon|weapon=5"
expect_stats "17 10 11 5 6 7 6" "a level 2 Mage: the wand adds 2 attack power"
t_get /inventory
expect_text 'Wand (Attack Power +2, Casts Magic Bolt, 5/5 Charges)'
expect_body '<img class="item-icon" src="/static/images/items/wand.png" width="22" height="22" alt=""> <b class="tip-term"'
# not sold elsewhere
t_sql "UPDATE users SET latitude = 30, longitude = 30 $WQ"
t_get "/shop/buy/$WD_WAND_ITEM"; expect_body 'Cheat attempt detected.'
wd_sql "UPDATE users SET latitude = 0, longitude = 0"

t_section "wand: cast from its fight button"
t_fight wizard 2 50
wd_sql "UPDATE users SET currentmp = 0, currenthp = 100, base_maxhp = 100"
WAND=$(wd_wand)
t_get /fight; CS=$(t_csrf)
# the wand's button comes first after Attack (the equipped gear before the spells): key 2
ORDER=$(grep -o 'name="fight"\|name="use_gear"\|name="spell"\|name="run"' "$BODY" | uniq | tr '\n' ' ')
[ "$ORDER" = 'name="fight" name="use_gear" name="spell" name="run" ' ] && t_ok || t_fail "fight menu order: $ORDER"
expect_body "<span class=\"spell-tip\" data-tip><button class=\"spell-btn\" type=\"submit\" name=\"use_gear\" value=\"$WAND\" title=\"Wand (5/5 charges)\" aria-label=\"Wand (5/5 charges)\" aria-keyshortcuts=\"2\"><img src=\"/static/images/items/wand.png\" width=\"44\" height=\"44\" alt=\"\"><span class=\"item-badge item-badge-charges\" aria-hidden=\"true\">5/5</span></button>"
ROUND=$(t_sql "SELECT $T_ROUND FROM users $WQ")
t_round "csrf=$CS&use_gear=$WAND"; expect_body 'You have cast the Magic Bolt spell for '
HP=$(t_sql "SELECT $T_MONSTER_HP FROM users $WQ")
{ [ "$HP" = 46 ] || [ "$HP" = 47 ]; } && t_ok || t_fail "the wand: 3-4 damage (monster HP $HP)"
wd_is "currentmp || '|' || $WD_CHARGES || '|' || $T_ROUND" "0|weapon=4|$((ROUND + 1))"
expect_body "title=\"Wand (4/5 charges)\" aria-label=\"Wand (4/5 charges)\" aria-keyshortcuts=\"2\"><img"
# at 0 charges: greyed out, and refused without spending the turn
t_sql "UPDATE user_items SET charges = 0 WHERE id = $WAND"
t_get /fight
expect_body "name=\"use_gear\" value=\"$WAND\" title=\"Wand (0/5 charges)\" aria-label=\"Wand (0/5 charges)\" aria-keyshortcuts=\"2\" disabled><img"
ROUND=$(t_sql "SELECT $T_ROUND FROM users $WQ"); HP=$(t_sql "SELECT $T_MONSTER_HP FROM users $WQ")
t_round "csrf=$CS&use_gear=$WAND"; expect_body 'The Wand has no charges left. Rest at an inn to recharge it.'
expect_body '<p class="fight-note error" role="alert">'; expect_body 'name="fight"'
wd_is "$T_MONSTER_HP || '|' || $T_ROUND || '|' || $WD_CHARGES" "$HP|$ROUND|weapon=0"
# a wand in the bag can't be used (and has no button)
t_give wizard wand 1
BAGWAND=$(wd_wand bag)
t_get /fight; expect_no_body "name=\"use_gear\" value=\"$BAGWAND\""
t_round "csrf=$CS&use_gear=$BAGWAND"; expect_body 'You do not have this item equipped.'
wd_is "$T_ROUND || '|' || $WD_CHARGES" "$ROUND|weapon=0,bag=5"
t_fight_clear wizard
wd_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0"

t_section "wand: the inn recharges what is equipped"
wd_sql "UPDATE users SET gold = 100"
t_sql "UPDATE user_items SET charges = 1 WHERE id = $WAND; UPDATE user_items SET charges = 2 WHERE id = $BAGWAND"
t_get /inn; expect_body 'Resting at the inn will refill your current HP, MP, and TP to their maximum levels, and recharge your equipped Wand (1/5 charges).'
t_post /inn "csrf=$TC&submit=Yes"
expect_body 'You wake up feeling refreshed and ready for action. Your Wand is fully charged again.'
wd_is "$WD_CHARGES" "weapon=5,bag=2"
t_post /inn "csrf=$TC&submit=Yes"; expect_no_body 'fully charged again'
t_post "/inventory/unequip/weapon" "csrf=$TC"
t_get /inn; expect_no_body 'recharge'

t_section "wand: obtained full (drop, shop), copies up to the bag's room"
t_items_clear wizard
wd_sql "UPDATE users SET dropcode = $WD_WAND_ITEM, currentaction = 'Exploring'"
t_get /drop; expect_body '<b>Wand</b>'
t_post /drop "csrf=$TC&take=Take+it"; expect_body 'The Wand is in your bag.'
wd_is "$WD_CHARGES" "bag=5"
wd_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0, gold = 1000"
t_items_clear wizard
t_give wizard wand 1 weapon
t_sql "UPDATE user_items SET charges = 3 WHERE id = $(wd_wand)"
# a copy of the wand you wear: the old one into the bag (with its charges), the new one full
t_get "/shop/buy/$WD_WAND_ITEM"; expect_body 'name="keep" value="Keep"><b>Buy and equip</b><span>Your Wand goes into the bag.'
t_post "/shop/buy/$WD_WAND_ITEM" "csrf=$TC&keep=x"; expect_body 'Thank you for purchasing this item.'
wd_is "gold || '|' || $WD_CHARGES" "925|bag=3,weapon=5"
# fill the bag (12 slots: 11 more wands kept), then only "sell" is offered
for _ in $(seq 1 11); do t_post "/shop/buy/$WD_WAND_ITEM" "csrf=$TC&keep=x"; done
wd_is "(SELECT count(*) FROM user_items WHERE user_id = users.id AND equipped IS NULL) || '|' || gold" "12|100"
t_get /; expect_body '<span class="invpanel-count"><b>12</b>/12</span>'
t_get "/shop/buy/$WD_WAND_ITEM"; expect_body '<b>Buy and equip</b><span>No room in your bag for your Wand.</span>'
expect_body 'name="sell" value="Sell"><b>Buy and sell my Wand</b><span>You wear the Wand; the shop pays 38 gold'
t_post "/shop/buy/$WD_WAND_ITEM" "csrf=$TC&keep=x"; expect_body 'Your bag is full.'
t_post "/shop/buy/$WD_WAND_ITEM" "csrf=$TC&sell=x"; expect_body 'Thank you for purchasing this item.'
wd_is "gold || '|' || (SELECT count(*) FROM user_items WHERE user_id = users.id)" "63|13"
# consumables: as many as the bag's room (a new stack needs a free slot)
t_get /shop/buy/66; expect_body 'Your bag is full.'
t_items_clear wizard
wd_sql "UPDATE users SET gold = 10000"
t_get /shop/buy/66; expect_body 'max="10"'
t_post /shop/buy/66 "csrf=$TC&submit=Buy&qty=10"; expect_body 'Thank you for purchasing this item.'
t_post /shop/buy/66 "csrf=$TC&submit=Buy&qty=10"; expect_body 'Thank you for purchasing this item.'
wd_is "$T_ITEMS" "herbx10,herbx10"
t_items_clear wizard

t_section "wand: single use (not rechargeable)"
# an admin turns the Wand's recharging off (an override; reset below): its lines say
# "Single use", the inn doesn't recharge it, and its last charge uses it up (gone from its
# slot, the round says so)
t_jar wandadmin; t_reset_jar; t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin/items/71; expect_body '<select name="rechargeable">'
t_form_submit /admin/items/71 rechargeable=0
wd_is "(SELECT rechargeable FROM items WHERE key = 'wand')" "0"
t_get /admin/items/1; expect_no_body 'name="rechargeable"'   # only for items that cast
t_jar wand
t_items_clear wizard; t_give wizard wand 1 weapon
WAND=$(wd_wand); t_sql "UPDATE user_items SET charges = 2 WHERE id = $WAND"
wd_sql "UPDATE users SET gold = 100, currentaction = 'In Town', latitude = 0, longitude = 0"
t_get /inventory; expect_text 'Wand (Attack Power +2, Casts Magic Bolt, 2/5 Charges, Single use)'
t_get /shop; expect_body '<ul class="shop-tip-effects"><li>Casts Magic Bolt</li><li>5 Charges</li><li>Single use</li></ul>'
t_get /inn; expect_no_body 'recharge'
t_post /inn "csrf=$TC&submit=Yes"; expect_no_body 'fully charged again'
wd_is "$WD_CHARGES" "weapon=2"
t_fight wizard 2 50
wd_sql "UPDATE users SET currentmp = 0, currenthp = 100, base_maxhp = 100"
t_get /fight; CS=$(t_csrf); expect_body '<div class="tip-meta">Casts Magic Bolt · 2/5 Charges · No MP · Single use</div>'
t_round "csrf=$CS&use_gear=$WAND"; expect_body 'You have cast the Magic Bolt spell for '; expect_no_body 'is used up'
wd_is "$WD_CHARGES" "weapon=1"
t_round "csrf=$CS&use_gear=$WAND"; expect_body 'You have cast the Magic Bolt spell for '; expect_body 'Your Wand is used up.'
wd_is "coalesce($WD_CHARGES, '-') || '|' || coalesce($T_ITEMS, '')" "-|"
t_get /fight; expect_no_body 'name="use_gear"'
t_fight_clear wizard
wd_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0"
t_jar wandadmin; t_get /admin/items/71
t_post /admin/items/71/reset "csrf=$(t_csrf)&field=*"
wd_is "(SELECT rechargeable FROM items WHERE key = 'wand')" "1"
t_jar wand

t_section "wand: help"
t_get /help/items
expect_body '<td style="width: 30%"><img class="help-icon" src="/static/images/items/wand.png" width="24" height="24" alt="">Wand<div class="help-lore">'
expect_body '<td style="width: 20%">75 Gold</td><td style="width: 20%">2 Attack Power</td><td style="width: 25%">Casts Magic Bolt, 5 Charges</td>'

fi
