# tests/e2e/inventory.sh :: the inventory (/inventory): equipped slots and the bag, equip
# (accessories in three slots), unequip, use, discard, the bag size (stacks, quest items),
# derived stats after equipment changes, and consumables in fights. Two test-only items
# are added to the test server's copy of app/content/items/ (a quest item and a fight-only
# consumable) and retired again at the end. Sourced by tests/run.sh.

if ! t_has_sql; then
	t_section "inventory (skipped: needs sqlite3 or python3)"
else

IQ="WHERE username = 'invhero'"
iv_sql() { t_sql "$1 $IQ"; }
iv_is() {  # iv_is EXPR EXPECTED (an SQL expression on the users row)
	local got; got=$(t_sql "SELECT $1 FROM users $IQ")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$1: expected '$2', got '$got'"; fi
}
iv_entry() {  # iv_entry ITEM_KEY: the user's first user_items id of that item
	t_sql "SELECT min(ui.id) FROM user_items ui JOIN items i ON i.id = ui.item_id JOIN users u ON u.id = ui.user_id
		WHERE u.username = 'invhero' AND i.key = '$1'"
}
IV_ITEMS="$T/app/content/items"

t_section "inventory: test items"
cat > "$IV_ITEMS/test_key.lua" <<'EOF'
return { name = "Old Key", description = "Opens something, somewhere.", category = "quest" }
EOF
cat > "$IV_ITEMS/test_bomb.lua" <<'EOF'
return { name = "Bomb", category = "consumable", price = 5, max_stack = 5, use_effects = { { kind = "damage", max = 12 } } }
EOF
cat > "$IV_ITEMS/test_bad.lua" <<'EOF'
return { name = "Bad Sword", category = "weapon", slot = "shield", max_stack = 3, use_effects = { { kind = "heal_hp", amount = 1 } } }
EOF
"$BIN" check --config "$CONFIG" >"$T/inv.log" 2>&1 && t_fail "dk check passed with an invalid item" || t_ok
for msg in "test_bad.lua: field 'slot' must be \"weapon\" for category weapon" "test_bad.lua: max_stack must be 1 for gear (weapon)" \
	"test_bad.lua: use_effects are for consumables; gear has modifiers"; do
	grep -qF "$msg" "$T/inv.log" && t_ok || t_fail "dk check: no '$msg' in $(cat "$T/inv.log")"
done
rm -f "$IV_ITEMS/test_bad.lua"
t_jar invanon; t_reset_jar
t_wait_for /help/items '>Old Key<br>' && t_ok || t_fail "test items not synced"
expect_body 'Quest Items'; expect_body '>Bomb</td><td style="width: 20%">5 Gold</td><td style="width: 45%">Hurt 12</td>'
t_get /inventory;                 expect_redirect /login

t_section "inventory: the page"
t_jar invhero; t_reset_jar
t_register invhero invpw1 invhero@example.com InvHero 1
t_login invhero invpw1
t_get /;                          expect_body 'href="/inventory">Inventory</a>'; expect_body 'Bag: 0 / 12</a>'
TC=$(t_csrf)
t_get /inventory;                 expect_status 200; expect_body 'Bag (0 / 12)'; expect_body 'Attack Power: <b>5</b>'
[ "$(grep -c 'inv-cell inv-free' "$BODY")" = 12 ] && t_ok || t_fail "12 free slots expected"
for s in Weapon Armor Shield 'Slot 1' 'Slot 2' 'Slot 3'; do expect_body "<td class=\"inv-slot\">$s:</td>"; done
iv_sql "UPDATE users SET currentaction = 'Fighting'"
t_get /inventory;                 expect_redirect /fight
t_post /inventory/use/1 "csrf=$TC"; expect_redirect /fight
iv_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0"

t_section "inventory: equip and unequip"
t_give invhero stick 1 weapon; t_give invhero branch; t_give invhero herb 3
t_get /inventory;                 expect_body 'Bag (2 / 12)'; expect_body '<b>Herb</b> x3'
expect_body '<b>Stick</b> <span class="small">(Attack Power +2)</span>'
BRANCH=$(iv_entry branch); HERB=$(iv_entry herb)
t_post "/inventory/equip/$BRANCH" "";  expect_status 403
t_post "/inventory/equip/$BRANCH" "csrf=$TC"; expect_body 'You equipped the Branch. The Stick is in your bag now.'
iv_is "$T_ITEMS" "stick,branch@weapon,herbx3"
expect_stats "15 0 10 5 5 9 5" "branch"
t_post "/inventory/equip/$HERB" "csrf=$TC"; expect_body 'Cheat attempt detected.'          # not gear
t_post "/inventory/equip/99999" "csrf=$TC"; expect_body 'Cheat attempt detected.'
t_post "/inventory/unequip/weapon" "csrf=$TC"; expect_body 'You took off the Branch. It is in your bag now.'
iv_is "$T_ITEMS" "stick,branch,herbx3"
expect_stats "15 0 10 5 5 5 5" "no weapon"
t_post "/inventory/unequip/weapon" "csrf=$TC"; expect_body 'There is nothing to take off there.'
t_post "/inventory/unequip/weaponid" "csrf=$TC"; expect_body 'Cheat attempt detected.'
t_post "/inventory/equip/$BRANCH" "csrf=$TC"; expect_body 'You equipped the Branch.'
expect_no_body 'is in your bag now'

t_section "inventory: accessories in three slots"
for k in life_pebble magic_pebble dragons_claw dragons_tear; do t_give invhero "$k"; done
for k in life_pebble magic_pebble dragons_claw; do
	t_post "/inventory/equip/$(iv_entry "$k")" "csrf=$TC&slot=0"; expect_body 'You equipped the'
done
iv_is "(SELECT group_concat(e) FROM (SELECT ui.equipped || '=' || i.key AS e FROM user_items ui JOIN items i ON i.id = ui.item_id
	WHERE ui.user_id = users.id AND ui.equipped LIKE 'accessory%' ORDER BY ui.equipped))" \
	"accessory1=life_pebble,accessory2=magic_pebble,accessory3=dragons_claw"
# max HP +10, max MP +10, attack +25 (branch 4 + strength 5)
expect_stats "25 10 10 5 5 34 5" "three accessories"
t_get /;                          expect_body 'Slot 1: Life Pebble'; expect_body 'Slot 3: Dragon&#39;s Claw'
TEAR=$(iv_entry dragons_tear)
t_post "/inventory/equip/$TEAR" "csrf=$TC&slot=0"; expect_body 'All three accessory slots are in use.'
t_post "/inventory/equip/$TEAR" "csrf=$TC&slot=4"; expect_body 'Cheat attempt detected.'
t_post "/inventory/equip/$TEAR" "csrf=$TC&slot=2"
expect_body 'You equipped the Dragon&#39;s Tear. The Magic Pebble is in your bag now.'
# strength +50 counts toward attack: 5 + 50 + 4 + 25
expect_stats "25 0 10 55 5 84 5" "tear in slot 2"
t_get /character;                 expect_body 'Slot 2: Dragon&#39;s Tear'

t_section "inventory: current HP/MP/TP follow the maxima"
iv_sql "UPDATE users SET currenthp = 25, currentmp = 0"
t_post /inventory/unequip/accessory1 "csrf=$TC"; expect_body 'You took off the Life Pebble.'
iv_is currenthp 15                                        # clamped to the new max HP
t_give invhero demons_sin
iv_sql "UPDATE users SET base_maxhp = 60, currenthp = 60"
t_post "/inventory/equip/$(iv_entry demons_sin)" "csrf=$TC&slot=1"
iv_is currenthp 10; expect_stats "10 0 10 105 5 134 5" "demon's sin"
t_get /;                          expect_body 'HP: 10<br>'
t_post /inventory/unequip/accessory1 "csrf=$TC"
iv_is currenthp 10                                        # never raised
iv_sql "UPDATE users SET base_maxhp = 15"

t_section "inventory: use"
iv_sql "UPDATE users SET currenthp = 5, currentmp = 0, base_maxmp = 20"
t_post "/inventory/use/$HERB" "csrf=$TC"; expect_body 'You have used the Herb, and gained 10 Hit Points.'
iv_is "currenthp || '|' || (SELECT qty FROM user_items WHERE id = $HERB)" "15|2"
t_post "/inventory/use/$HERB" "csrf=$TC"; expect_body 'Your Hit Points are already full. You don&#39;t need to use the Herb now.'
iv_is "(SELECT qty FROM user_items WHERE id = $HERB)" "2"
t_give invhero ether
t_post "/inventory/use/$(iv_entry ether)" "csrf=$TC"; expect_body 'You have used the Ether, and gained 20 Magic Points.'
iv_is "currentmp || '|' || (SELECT count(*) FROM user_items ui JOIN items i ON i.id = ui.item_id WHERE ui.user_id = users.id AND i.key = 'ether')" "20|0"
t_give invhero test_bomb 2
BOMB=$(iv_entry test_bomb)
t_get /inventory;                 expect_no_body "action=\"/inventory/use/$BOMB\""
t_post "/inventory/use/$BOMB" "csrf=$TC"; expect_body 'The Bomb can only be used in a fight.'
t_post "/inventory/use/$BRANCH" "csrf=$TC"; expect_body 'Cheat attempt detected.'      # equipped
t_post "/inventory/use/$(iv_entry stick)" "csrf=$TC"; expect_body 'The Stick can&#39;t be used.'
iv_is "(SELECT qty FROM user_items WHERE id = $BOMB)" "2"

t_section "inventory: a fight-only item in a fight"
iv_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 2, currentmonsterhp = 1,
	currentmonstersleep = 0, currentmonsterimmune = 0"
t_get /fight;                     expect_body '<option value="'"$(t_sql "SELECT id FROM items WHERE key = 'test_bomb'")"'">Bomb (x2)</option>'
t_post /fight "csrf=$TC&item=Use+Item&useritem=$(t_sql "SELECT id FROM items WHERE key = 'test_bomb'")"
expect_redirect /victory
iv_is "currentmonsterhp || '|' || (SELECT qty FROM user_items WHERE id = $BOMB)" "0|1"
t_get /victory;                   expect_body 'You have defeated the Red Slime.'

t_section "inventory: discard"
t_get "/inventory/discard/$HERB"; expect_body 'You have 2 x Herb. How many do you want to throw away?'
t_post "/inventory/discard/$HERB" "csrf=$TC&cancel=Cancel"; expect_redirect /inventory
t_post "/inventory/discard/$HERB" "qty=1"; expect_status 403
t_post "/inventory/discard/$HERB" "csrf=$TC&submit=Discard&qty=3"; expect_body 'Please enter a number from 1 to 2.'
t_post "/inventory/discard/$HERB" "csrf=$TC&submit=Discard&qty=1"; expect_body 'You discarded the Herb.'
iv_is "(SELECT qty FROM user_items WHERE id = $HERB)" "1"
t_get "/inventory/discard/$(iv_entry stick)"; expect_body 'Do you really want to throw away the Stick?'
t_post "/inventory/discard/$(iv_entry stick)" "csrf=$TC&submit=Discard"; expect_body 'You discarded the Stick.'
iv_is "(SELECT count(*) FROM user_items ui JOIN items i ON i.id = ui.item_id WHERE ui.user_id = users.id AND i.key = 'stick')" "0"
t_post "/inventory/discard/$BRANCH" "csrf=$TC&submit=Discard"; expect_body 'Cheat attempt detected.'   # equipped

t_section "inventory: the bag size"
t_items_clear invhero
for k in stick branch club dagger hatchet axe brand poleaxe broadsword battle_axe claymore; do t_give invhero "$k"; done
t_give invhero herb 9
t_give invhero dragons_wing 1 accessory1          # equipped: doesn't count
t_give invhero test_key                           # quest: doesn't count
t_get /inventory;                 expect_body 'Bag (12 / 12)'; expect_no_body 'inv-free'
expect_body "Quest item (doesn't take a slot)"
KEY=$(iv_entry test_key)
expect_no_body "/inventory/discard/$KEY\""
t_get "/inventory/discard/$KEY";  expect_body 'Quest items can&#39;t be discarded.'
t_post "/inventory/discard/$KEY" "csrf=$TC&submit=Discard"; expect_body 'Quest items can&#39;t be discarded.'
t_post /inventory/unequip/accessory1 "csrf=$TC"; expect_body 'Your bag is full. Make room in it before you take off the Dragon&#39;s Wing.'
iv_is "(SELECT equipped FROM user_items ui JOIN items i ON i.id = ui.item_id WHERE ui.user_id = users.id AND i.key = 'dragons_wing')" "accessory1"
# topping up a stack works in a full bag (a Herb from the shop), a new stack doesn't
t_get /shop/buy/66;               expect_body 'You are buying the Herb for 15 gold. It goes into your bag.'
grep -qF 'name="qty"' "$BODY" && t_fail "a stack with room for 1 offers a quantity" || t_ok
t_post /shop/buy/66 "csrf=$TC&submit=Buy"; expect_body 'Thank you for purchasing this item.'
t_get /shop/buy/66;               expect_body 'Your bag is full.'
# quest items always fit, even in a full bag (a quest can't be blocked)
iv_sql "UPDATE users SET dropcode = (SELECT id FROM items WHERE key = 'test_key')"
t_get /drop;                      expect_body 'name="take" value="Take it"'; expect_no_body 'Your bag is full'
t_post /drop "csrf=$TC&take=x";   expect_body 'The Old Key is in your bag.'
# a gear drop into a full bag: discard first; quest items are not offered
iv_sql "UPDATE users SET dropcode = (SELECT id FROM items WHERE key = 'ruby')"
t_get /drop;                      expect_body 'Your bag is full.'; expect_no_body "value=\"$KEY\""
t_post /drop "csrf=$TC&take=x&discard=$KEY"; expect_body 'Please go back and select an item from your bag to discard.'
iv_is dropcode "$(t_sql "SELECT id FROM items WHERE key = 'ruby'")"
t_post /drop "csrf=$TC&leave=x";  expect_redirect /
# the admin setting
t_jar invadmin; t_reset_jar
t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin/settings;            expect_body 'name="inventory_size" size="3" maxlength="3" value="12"'
t_form_submit /admin/settings inventory_size=0; expect_body 'Bag size must be a number from 1 to 100.'
t_get /admin/settings
t_form_submit /admin/settings inventory_size=14; expect_redirect '/admin/settings\?saved=1'
t_jar invhero
t_get /inventory;                 expect_body 'Bag (12 / 14)'
[ "$(grep -c 'inv-cell inv-free' "$BODY")" = 2 ] && t_ok || t_fail "2 free slots expected"
t_post /inventory/unequip/accessory1 "csrf=$TC"; expect_body 'You took off the Dragon&#39;s Wing.'
t_jar invadmin
t_get /admin/settings
t_form_submit /admin/settings inventory_size=12; expect_redirect '/admin/settings\?saved=1'
t_get "/admin/users/$(t_sql "SELECT id FROM users $IQ")"
expect_body 'Effective Stats:'; expect_body 'stick, branch,'; expect_body 'test_key'

t_section "inventory: cleanup"
t_items_clear invhero
t_sql "DELETE FROM user_spells WHERE user_id = (SELECT id FROM users $IQ); DELETE FROM users $IQ"
rm -f "$IV_ITEMS/test_key.lua" "$IV_ITEMS/test_bomb.lua"
t_jar invanon
for _ in $(seq 1 50); do
	[ "$(t_sql "SELECT count(*) FROM items WHERE key LIKE 'test_%' AND retired = 0")" = 0 ] && break
	t_get /login; sleep 0.1
done
[ "$(t_sql "SELECT group_concat(retired) FROM items WHERE key LIKE 'test_%'")" = "1,1" ] && t_ok || t_fail "test items not retired"
t_jar default
fi
