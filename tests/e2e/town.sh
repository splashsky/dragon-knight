# tests/e2e/town.sh :: F1 town / explore / heal / character / map / babble.
# Sourced by tests/run.sh (helpers documented in docs/APP.md).

if ! t_has_sql; then
	t_section "town (skipped: needs sqlite3 or python3)"
else

tu() { t_sql "UPDATE users SET $1 WHERE username = 'townie'"; }
tq() { t_sql "SELECT $1 FROM users WHERE username = 'townie'"; }
expect_db() { # expect_db "col,col" "v|v" label
	local got; got=$(tq "$1")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$3: $1 = '$got', expected '$2'"; fi
}
TOWN_HOME="currentaction='In Town', latitude=0, longitude=0"

t_section "town: setup"
t_jar town
t_get /inn;                       expect_redirect /login
t_register townie townpw1 townie@example.com Townie 1
t_login townie townpw1;           expect_redirect /
t_get /;                          expect_body 'Welcome to Midworld'
TC=$(t_csrf)
[ -n "$TC" ] && t_ok || t_fail "no csrf token on the town page"

t_section "town: the map and the character sheet (floating windows)"
# their links open windows (windows.js), which ask for the page as a dialog's: the content
# alone; without JavaScript, the pages in a new tab
expect_body '<a href="/map" target="_blank" data-window="map">View Map</a>'
expect_body '<a class="charpanel-more" href="/character" target="_blank" data-window="stats">Extended Stats</a>'
t_get /map -H 'X-DK-Modal: 1';       expect_header '^x-dk-modal: 1'
# where it can, the page draws the weather with WebGL from data (worldgl.js; the test
# routes let the browser test do it in software)
expect_body '<div class="world-map" data-sky-data="/map/sky/data" data-sky-relief="/static/images/world-relief.bin" data-sky-test>'
expect_no_body '<html'
# the land's picture, the weather over it as of the render, then the towns and the player on
# top (in town at Midworld: the map's centre), with legends of the land and the weather; the
# picture is a static file
expect_body '<svg class="world-map-svg" viewBox="0 0 101 101"'; expect_body '<image href="/static/images/world.svg" width="101" height="101"/>'
expect_body "<g class=\"world-sky\" data-sky=\"$((T_NOW / 10))\">"
expect_body '<g class="world-map-town"><circle cx="50.5" cy="50.5" r="0.9"/><text x="52.1" y="51.5" text-anchor="start">Midworld</text></g>'
# Endworld is on the map's corner: its mark nudged inside the frame, its name above it
expect_body '<g class="world-map-town"><circle cx="1.4" cy="99.6" r="0.9"/><text x="3.0" y="98.0" text-anchor="start">Endworld</text></g>'
expect_body '<circle class="world-map-you" cx="50.5" cy="50.5" r="1.7"><title>You are here (0N, 0E)</title></circle>'
# in that order: the picture, the sky, the towns, the player
[ "$(grep -o '<image href="/static/images/world.svg"\|<g class="world-sky"\|<g class="world-map-town"\|<circle class="world-map-you"' "$BODY" | uniq | tr '\n' '|')" \
	= '<image href="/static/images/world.svg"|<g class="world-sky"|<g class="world-map-town"|<circle class="world-map-you"|' ] \
	&& t_ok || t_fail "the map's layers in order"
# the legend folds under the map: open on the page (the window folds it: windows.js)
tr -d '\n' < "$BODY" | grep -qF '</svg><details class="world-map-key" open><summary>Legend</summary><ul class="world-map-legend">' \
	&& t_ok || t_fail "the legend folding under the map"
tr -d '\n' < "$BODY" | grep -qF 'Night</li></ul></details></div>' && t_ok || t_fail "the weather's legend in it"
expect_body 'The Thornbog</li>'; expect_body 'Lakes and ponds</li>'; expect_body 'Peaks</li>'; expect_body 'Thunderstorm</li>'; expect_body 'Night</li>'
tu "latitude=-3, longitude=3"
t_get /map; expect_body '<circle class="world-map-you" cx="51.1" cy="51.1" r="1.7"><title>You are here (3S, 3E)</title></circle>'
tu "latitude=0, longitude=0"
t_get /static/images/world-relief.bin; expect_status 200; [ "$(wc -c < "$BODY")" = 10201 ] && t_ok || t_fail "the relief: a byte a cell"
t_get /static/images/world.svg; expect_status 200; expect_header '^content-type: image/svg\+xml'
expect_body '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 101 101"'
t_get /character -H 'X-DK-Modal: 1'; expect_header '^x-dk-modal: 1'; expect_body '<div class="charsheet">'; expect_body 'Travel Points:'
expect_no_body '<html'

t_section "town: the way back (the header's button to /)"
# named for where / leads, and not on that page itself
t_get /;                          expect_no_body 'class="dk-home"'
t_get /inventory;                 expect_body '<a class="dk-home" href="/">Back to Midworld</a>'
tu "currentaction='Exploring', latitude=5, longitude=5, currenthp=100000, base_maxhp=100000"
t_get /;                          expect_no_body 'class="dk-home"'
t_get /inventory;                 expect_body '<a class="dk-home" href="/">Back to exploring</a>'
t_post /__test/encounter "csrf=$TC"; expect_redirect /fight
t_get /fight;                     expect_no_body 'class="dk-home"'
t_get /news;                      expect_body '<a class="dk-home" href="/">Back to the fight</a>'
t_fight_clear townie; tu "$TOWN_HOME, currenthp=15, base_maxhp=15"

t_section "town: inn"
tu "$TOWN_HOME, gold=100, currenthp=1, currentmp=0, currenttp=0, base_maxhp=20, base_maxmp=10, base_maxtp=12"
t_get /inn;                       expect_status 200; expect_body 'Resting at the inn'; expect_body '<b>5 gold</b>'
t_post /inn "submit=Yes";         expect_status 403
expect_db "gold,currenthp" "100|1" "inn without csrf"
t_post /inn "csrf=$TC&cancel=No"; expect_redirect /
expect_db "gold,currenthp" "100|1" "inn cancel"
t_post /inn "csrf=$TC&submit=Yes"; expect_body 'You wake up feeling refreshed and ready for action.'
expect_db "gold,currenthp,currentmp,currenttp" "95|20|10|12" "inn stay"
tu "gold=4"
t_get /inn;                       expect_body 'You do not have enough gold to stay at this Inn tonight.'
t_post /inn "csrf=$TC&submit=Yes"; expect_body 'You do not have enough gold'
expect_db "gold" "4" "inn too poor"
tu "gold=100, currentaction='Exploring', latitude=5, longitude=5"
t_get /inn;                       expect_body 'Cheat attempt detected.'
# the Location panel says where (its heading in the default theme) and the coordinates
expect_body '<h2 class="title">Exploring</h2>'; expect_body '>5N, 5E</span>'
tu "latitude=-3, longitude=-7"; t_get /; expect_body '>3S, 7W</span>'
tu "latitude=5, longitude=5"
tu "currentaction='Fighting'"
t_get /inn;                       expect_redirect /fight
t_get /fight;                     expect_body '<h2 class="title">Fighting</h2>'
t_get /shop;                      expect_redirect /fight
t_get /maps;                      expect_redirect /fight

t_section "town: shop list"
# (no gear yet: the effective stats are the base ones; expect_stats reads /character:
# max HP, max MP, max TP, strength, dexterity, attack power, defense power)
TOWN_BASE="base_maxhp=15, currenthp=15, base_maxmp=0, currentmp=0, base_maxtp=10, currenttp=10, strength=5,
	dexterity=5, base_attack=0, base_defense=0, base_exp_bonus=0, base_gold_bonus=0"
t_items_clear townie
tu "$TOWN_HOME, gold=1000, $TOWN_BASE"
t_get /shop;                      expect_status 200
# icon buttons in groups (weapons, armor, shields, items), each with its tooltip (the
# price, the gold, what it adds; nothing worn here, so nothing to compare), then the maps
SHOP_GROUPS=$(grep -o 'class="shop-group-label" id="shop-[a-z]*-label">[A-Za-z]*' "$BODY" | sed 's/.*>//' | tr '\n' ' ')
[ "$SHOP_GROUPS" = "Weapons Armor Shields Items Maps " ] && t_ok || t_fail "shop groups: $SHOP_GROUPS"
expect_body '<span class="spell-tip" data-tip><a class="spell-btn" href="/shop/buy/1" data-modal title="Stick (10 gold)" aria-label="Stick (10 gold)"><img src="/static/images/items/stick.png" width="44" height="44" alt=""></a><template class="tip">'
expect_body '<b class="shop-tip-gold">10 gold</b></div><div class="shop-tip-note">You have 1,000 gold</div><table class="shop-tip-stats"><tr><th scope="row">Attack Power</th><td class="shop-tip-value">+2</td><td class="shop-tip-delta"></td></tr></table>'
expect_body 'href="/shop/buy/17" data-modal title="Skivvies (25 gold)"'
expect_body '<tr><th scope="row">Defense Power</th><td class="shop-tip-value">+2</td><td class="shop-tip-delta"></td></tr><tr><th scope="row">Gold Bonus</th><td class="shop-tip-value">+10%</td><td class="shop-tip-delta"></td></tr></table>'
expect_no_body 'Dagger'
expect_body 'href="/shop/buy/66" data-modal title="Herb (15 gold)"'; expect_no_body 'Potion'
expect_no_body 'shop-short'                       # 1000 gold covers everything here
expect_no_body 'I will buy these from your bag'
t_get /shop/buy/4;                expect_body 'Cheat attempt detected.'
t_post /shop/buy/4 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_post /shop/buy/999 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_post /shop/buy/67 "csrf=$TC&submit=Buy"; expect_body 'Cheat attempt detected.'      # Potions: not in Midworld
expect_db "gold,coalesce($T_ITEMS, '')" "1000|" "cheat buy"

t_section "town: the purchase in the shop's dialog (X-DK-Modal)"
# the shop's links open the purchase page in a dialog (data-modal: public/js/modal.js):
# with X-DK-Modal: 1 the page's title and content alone (no layout); a redirect comes
# back as X-DK-Go (the dialog closes, the page goes there); the result and errors are the
# dialog's content, the result with a button back to the shop. Without the header: pages.
t_get /shop/buy/1 -H 'X-DK-Modal: 1'; expect_status 200
expect_header '^x-dk-modal: 1'; expect_header '^vary: X-DK-Live, X-DK-Modal'
expect_body '<h2 class="dk-modal-title" id="dk-modal-title">Buy Items</h2>'
expect_body '<div class="dk-modal-content"><div class="town-message buy">'
expect_body '<span class="buy-name"><b>Stick</b><span class="buy-kind">Weapon</span></span>'
expect_body '<span class="buy-tag">10 gold</span>'; expect_body '<li>Attack Power <b>+2</b></li>'   # nothing worn: what it gives
# nothing worn: into the bag, or worn
expect_body '<button class="buy-choice" type="submit" name="bag" value="Bag"><b>Buy to bag</b><span>You'"'"'ll have 990 gold left.</span></button>'
expect_body '<button class="buy-choice" type="submit" name="submit" value="Yes"><b>Buy and equip</b><span>You'"'"'ll have 990 gold left.</span></button>'
expect_no_body 'name="sell"'
expect_body '<button class="buy-cancel" type="submit" name="cancel" value="No" data-modal-close>Not now</button>'
expect_no_body '<html'; expect_no_body 'compass'; expect_no_body 'Babble'
t_post /shop/buy/1 "csrf=$TC&cancel=No" -H 'X-DK-Modal: 1'
expect_status 200; expect_header '^x-dk-go: /'$'\r''?$'; [ -s "$BODY" ] && t_fail "X-DK-Go has a body" || t_ok
t_post /shop/buy/4 "csrf=$TC&submit=Yes" -H 'X-DK-Modal: 1'; expect_header '^x-dk-modal: 1'; expect_body 'Cheat attempt detected.'
t_post /shop/buy/66 "csrf=$TC&submit=Buy&qty=2" -H 'X-DK-Modal: 1'; expect_header '^x-dk-modal: 1'
expect_body 'Thank you for purchasing this item.<div class="dk-modal-actions"><button type="button" data-modal-close autofocus>Back to the market</button></div>'
expect_no_body 'direction buttons'
expect_db "gold,$T_ITEMS" "970|herbx2" "bought in the dialog"
t_get /shop/buy/1; expect_body '<html'; expect_body 'compass'
grep -qi '^x-dk-modal' "$HEADERS" && t_fail "a page says X-DK-Modal" || t_ok
t_get /shop; expect_body 'href="/shop/buy/1" data-modal title="Stick (10 gold)"'
t_items_clear townie; tu "gold=1000"

t_section "town: shop weapon, keep or sell the old one"
t_get /shop/buy/1;                expect_body '<b>Buy and equip</b>'; expect_body 'action="/shop/buy/1"'
t_post /shop/buy/1 "submit=Yes";  expect_status 403
t_post /shop/buy/1 "csrf=$TC&cancel=No"; expect_redirect /
expect_db "gold,coalesce($T_ITEMS, '')" "1000|" "shop cancel"
t_post /shop/buy/1 "csrf=$TC&submit=Yes"; expect_body 'Thank you for purchasing this item.'
expect_db "gold,$T_ITEMS" "990|stick@weapon" "buy stick"
expect_stats "15 0 10 5 5 7 5" "stick"
t_get /;                          expect_body 'Weapon: Stick'
# a copy of the weapon you wear can be bought too (2.4: no more "Already purchased"): the
# old one is kept in the bag or sold, as with any other
t_get /shop;                      expect_no_body 'Already purchased'; expect_body 'href="/shop/buy/1" data-modal title="Stick (10 gold)"'
t_get /shop/buy/1;                expect_body '<b>Buy and sell my Stick</b>'
t_post /shop/buy/1 "csrf=$TC&keep=x"; expect_body 'Thank you for purchasing this item.'
expect_db "gold,$T_ITEMS" "980|stick,stick@weapon" "a second stick, the first kept"
t_post /shop/buy/1 "csrf=$TC&sell=x"  # 980 - 10 + 5
expect_db "gold,$T_ITEMS" "975|stick,stick@weapon" "a third stick, the second sold"
t_sql "DELETE FROM user_items WHERE equipped IS NULL AND user_id = (SELECT id FROM users WHERE username = 'townie')"
tu "gold=990"
t_get /shop/buy/2
# side by side with what is worn; three choices, each saying what it leaves: into the bag
# (the Stick stays on), worn (the Stick into the bag), worn with the Stick sold
expect_body '<thead><tr><td></td><th scope="col">Your Stick</th><th scope="col">The Branch</th></tr></thead>'
expect_body '<tr><th scope="row">Attack Power</th><td>+2</td><td>+4 <span class="buy-up">(+2)</span></td></tr>'
expect_body 'name="bag" value="Bag"><b>Buy to bag</b><span>You keep wearing your Stick. You'"'"'ll have 960 gold left.</span>'
expect_body 'name="keep" value="Keep"><b>Buy and equip</b><span>Your Stick goes into the bag. You'"'"'ll have 960 gold left.</span>'
expect_body 'name="sell" value="Sell"><b>Buy and sell my Stick</b><span>You wear the Branch; the shop pays 5 gold for your Stick. You'"'"'ll have 965 gold left.</span>'
t_post /shop/buy/2 "csrf=$TC&bag=x"; expect_body 'Thank you for purchasing this item.'
expect_db "gold,$T_ITEMS" "960|stick@weapon,branch" "branch into the bag, the stick still worn"
expect_stats "15 0 10 5 5 7 5" "still the stick"
t_post /shop/buy/2 "csrf=$TC&bag=x" -H 'X-DK-Modal: 1'; expect_body 'Thank you for purchasing this item.'   # (in the dialog too)
expect_db "gold,$T_ITEMS" "930|stick@weapon,branch,branch" "another branch into the bag"
t_sql "DELETE FROM user_items WHERE equipped IS NULL AND user_id = (SELECT id FROM users WHERE username = 'townie')"
tu "gold=990"
t_post /shop/buy/2 "csrf=$TC&keep=x"
expect_db "gold,$T_ITEMS" "960|stick,branch@weapon" "branch, stick kept"
expect_stats "15 0 10 5 5 9 5" "branch"
t_post /shop/buy/3 "csrf=$TC&sell=x"   # Club 40/5; sells the Branch: 960 + ceil(30/2) - 40
expect_db "gold,$T_ITEMS" "935|stick,club@weapon" "club, branch sold"
expect_stats "15 0 10 5 5 10 5" "club"
# the original form's plain Yes sells the old item, as the original did
t_post /shop/buy/2 "csrf=$TC&submit=Yes"   # 935 + 20 - 30
expect_db "gold,$T_ITEMS" "925|stick,branch@weapon" "yes sells"

t_section "town: shop sell section"
STICK_E=$(t_sql "SELECT ui.id FROM user_items ui JOIN users u ON u.id = ui.user_id WHERE u.username = 'townie' AND ui.item_id = 1")
WEAPON_E=$(t_sql "SELECT ui.id FROM user_items ui JOIN users u ON u.id = ui.user_id WHERE u.username = 'townie' AND ui.equipped = 'weapon'")
t_get /shop;                      expect_body 'I will buy these from your bag'; expect_body "action=\"/shop/sell/$STICK_E\""
expect_body 'aria-label="Sell Stick for 5 gold"><img src="/static/images/items/stick.png"'; expect_no_body "action=\"/shop/sell/$WEAPON_E\""
t_post "/shop/sell/$STICK_E" "qty=1"; expect_status 403
t_post "/shop/sell/$STICK_E" "csrf=$TC&submit=Sell"; expect_body 'You sold the Stick for 5 gold.'
expect_db "gold,$T_ITEMS" "930|branch@weapon" "stick sold"
t_post "/shop/sell/$STICK_E" "csrf=$TC&submit=Sell"; expect_body 'Cheat attempt detected.'
t_post "/shop/sell/$WEAPON_E" "csrf=$TC&submit=Sell"; expect_body 'Cheat attempt detected.'   # equipped
expect_db "gold" "930" "no double sale"

t_section "town: shop armor specials"
t_post /shop/buy/17 "csrf=$TC&submit=Yes"     # Skivvies: 25 gold, def 2, gold bonus +10%
expect_db "gold,$T_ITEMS" "905|branch@weapon,skivvies@armor" "skivvies"
expect_stats "15 0 10 5 5 9 7" "skivvies"
t_get /character;                 expect_body 'Gold: 905 <span class="light">(+10%)</span>'
t_get /shop/buy/18;               expect_body 'the shop pays 13 gold for your Skivvies'
t_post /shop/buy/18 "csrf=$TC&sell=x"         # Clothes: 905 + ceil(25/2) - 50
expect_db "gold,$T_ITEMS" "868|branch@weapon,clothes@armor" "clothes sells skivvies"
expect_stats "15 0 10 5 5 9 10" "clothes"
t_get /character;                 expect_no_body '(+10%)'

t_section "town: shop shield maxhp special + clamping"
t_give townie destiny_aegis 1 shield
tu "gold=1000, base_maxhp=20, currenthp=70, base_maxmp=10, currentmp=10"
expect_stats "70 10 10 5 5 9 110" "aegis (maxhp +50, defense 100)"
t_post /shop/buy/28 "csrf=$TC&sell=x"         # Reed Shield 50/2; sells the Aegis (25000, 100, max HP +50)
# gold 1000 + 12500 - 50 ; def 110 + 2 - 100 ; max HP 70 - 50 ; current HP clamped to 20
expect_db "gold,currenthp,currentmp" "13450|20|10" "reed shield sells aegis"
expect_stats "20 10 10 5 5 9 12" "reed shield"
# keeping the old item needs a free bag slot
for k in dagger hatchet axe brand poleaxe broadsword battle_axe claymore dark_axe dark_sword bright_sword magic_sword; do
	t_give townie "$k"
done
t_get /shop/buy/29;               expect_body '<div class="buy-choice buy-choice-off"><b>Buy to bag</b><span>Your bag is full.</span></div>'
expect_body '<div class="buy-choice buy-choice-off"><b>Buy and equip</b><span>No room in your bag for your Reed Shield.</span></div>'
expect_no_body 'name="keep"'; expect_no_body 'name="bag"'; expect_body '<b>Buy and sell my Reed Shield</b><span>You wear the Buckler; the shop pays 25 gold'
t_post /shop/buy/29 "csrf=$TC&keep=x"; expect_body 'Your bag is full.'
expect_db "gold" "13450" "keep refused"
t_post /shop/buy/29 "csrf=$TC&sell=x"   # Buckler 100/4: 13450 + 25 - 100
expect_db "gold" "13375" "buckler sells reed shield"
t_sql "DELETE FROM user_items WHERE equipped IS NULL AND user_id = (SELECT id FROM users WHERE username = 'townie')"

t_section "town: shop strength special"
t_sql "DELETE FROM user_items WHERE equipped = 'weapon' AND user_id = (SELECT id FROM users WHERE username = 'townie')"
t_give townie destiny_blade 1 weapon
tu "gold=100, strength=5"
expect_stats "20 10 10 55 5 305 14" "destiny blade (strength +50 counts toward attack)"
t_post /shop/buy/3 "csrf=$TC&sell=x"      # Club 40/5; sells the Destiny Blade (50000, 250, strength +50)
expect_db "gold" "25060" "club sells destiny blade"
expect_stats "20 10 10 5 5 10 14" "club"
tu "gold=5"
# what the gold doesn't cover is greyed out (with what the worn piece sells back for):
# 5 + 25 for the Clothes buys the Skivvies, not the Clothes again; nothing else but the Stick
# (Midworld's 3.1 wares, the Antidote, Copper Ring, Trail Snack and Travel Tea, are short too)
t_get /shop
expect_body '<span class="spell-tip" data-tip><a class="spell-btn" href="/shop/buy/17"'
expect_body '<span class="spell-tip shop-short" data-tip><a class="spell-btn" href="/shop/buy/18"'
expect_body '<span class="spell-tip" data-tip><a class="spell-btn" href="/shop/buy/1"'
[ "$(grep -o 'spell-tip shop-short' "$BODY" | wc -l)" = 11 ] && t_ok || t_fail "short items: $(grep -o 'spell-tip shop-short' "$BODY" | wc -l)"
# the tooltips say what is missing (the Clothes: 50 - 5 - 25), and what a swap loses
expect_body 'title="Clothes (50 gold)"'; expect_body '<div class="shop-tip-note shop-tip-short">You need 20 more gold</div>'
expect_body '<tr><td></td><td></td><td class="shop-tip-vs">vs Clothes</td></tr>'
t_get /shop/buy/18;               expect_body 'You do not have enough gold to buy this item.'   # Clothes again: 5 + 25 < 50
t_get /shop/buy/19;               expect_body 'You do not have enough gold to buy this item.'
t_post /shop/buy/19 "csrf=$TC&sell=x"; expect_body 'You do not have enough gold to buy this item.'
expect_db "gold" "5" "shop too poor"
# sell-back counts toward the price: 50 gold + 25 for the Clothes covers Leather Armor (75)
tu "gold=50"
t_get /shop/buy/19;               expect_body '<b>Buy and sell my Clothes</b><span>You wear the Leather Armor; the shop pays 25 gold'
expect_body '<b>Buy and equip</b><span>Not enough gold without selling your Clothes.</span>'; expect_no_body 'name="keep"'
expect_body '<b>Buy to bag</b><span>Not enough gold without selling your Clothes.</span>'; expect_no_body 'name="bag"'
t_post /shop/buy/19 "csrf=$TC&keep=x"; expect_body 'You do not have enough gold to buy this item.'
t_post /shop/buy/19 "csrf=$TC&sell=x"
expect_db "gold,$T_ITEMS" "0|buckler@shield,club@weapon,leather_armor@armor" "sell-back covers price"
t_sql "UPDATE user_items SET item_id = 18 WHERE equipped = 'armor' AND user_id = (SELECT id FROM users WHERE username = 'townie')"
t_post /shop/buy/19 "csrf=$TC&sell=x"; expect_body 'You do not have enough gold to buy this item.'
expect_db "gold" "0" "sell-back alone too little"

t_section "town: shop at Endworld + Bris"
t_sql "DELETE FROM user_items WHERE equipped = 'shield' AND user_id = (SELECT id FROM users WHERE username = 'townie')"
tu "currentaction='In Town', latitude=-250, longitude=-250, gold=30000, base_maxhp=20, currenthp=20"
t_get /shop;                      expect_body 'title="Destiny Aegis (25000 gold)"'; expect_body 'title="Potion (60 gold)"'; expect_body 'title="Ether (80 gold)"'
t_post /shop/buy/33 "csrf=$TC&submit=Yes"
expect_db "gold,currenthp" "5000|20" "buy aegis"
expect_stats "70 10 10 5 5 10 110" "aegis"
tu "latitude=70, longitude=-70, gold=1000"
t_get /shop;                      expect_body 'Hard Leather Armor'; expect_body 'Buckler'; expect_body 'Small Shield'
t_post /shop/buy/29 "csrf=$TC&sell=x"     # Buckler 100/4; sells the Aegis (25000, 100, max HP +50)
expect_db "gold,currenthp" "13400|20" "bris sells buckler"
expect_stats "20 10 10 5 5 10 14" "buckler"
tu "latitude=5, longitude=5, currentaction='Exploring'"
t_get /shop;                      expect_body 'Cheat attempt detected.'
t_post /shop/buy/1 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_give townie herb 2
HERB_E=$(t_sql "SELECT ui.id FROM user_items ui JOIN users u ON u.id = ui.user_id WHERE u.username = 'townie' AND ui.item_id = 66")
t_post "/shop/sell/$HERB_E" "csrf=$TC&submit=Sell"; expect_body 'Cheat attempt detected.'   # no shop out here

t_section "town: consumables in the shop"
t_items_clear townie
tu "currentaction='In Town', latitude=30, longitude=30, gold=1000"     # Roma
t_get /shop/buy/67;               expect_body '<span class="buy-tag">60 gold each</span>'; expect_body 'Consumable, into your bag'
expect_body 'name="qty" value="1" min="1" max="10"'; expect_body 'up to 10;'
for q in 0 11 abc -1; do
	t_post /shop/buy/67 "csrf=$TC&submit=Buy&qty=$q"; expect_body 'Please enter a quantity from 1 to 10.'
done
expect_db "gold,coalesce($T_ITEMS, '')" "1000|" "no bad quantities"
t_post /shop/buy/67 "csrf=$TC&submit=Buy&qty=4"; expect_body 'Thank you for purchasing this item.'
expect_db "gold,$T_ITEMS" "760|potionx4" "4 potions"
t_get /shop/buy/67;               expect_body 'max="6"'                    # room on the stack
t_post /shop/buy/67 "csrf=$TC&submit=Buy&qty=6"
expect_db "gold,$T_ITEMS" "400|potionx10" "a full stack"
t_get /shop/buy/67;               expect_body 'max="6"'                    # a new stack: 400 gold buys 6
t_post /shop/buy/67 "csrf=$TC&submit=Buy&qty=2"
expect_db "gold,$T_ITEMS" "280|potionx10,potionx2" "a second stack"
# the gold limit
tu "gold=100"
t_get /shop/buy/68;               expect_body '<b>Buy the Ether</b>'; expect_body '<span class="buy-tag">80 gold</span>'; expect_no_body 'name="qty"'
t_post /shop/buy/68 "csrf=$TC&submit=Buy&qty=2"; expect_body 'Please enter a quantity from 1 to 1.'
t_post /shop/buy/68 "csrf=$TC&submit=Buy"
expect_db "gold,$T_ITEMS" "20|potionx10,potionx2,ether" "one ether"
tu "gold=10"
t_get /shop/buy/66;               expect_body 'You do not have enough gold to buy this item.'
# a full bag: only topping up a stack works
tu "gold=1000"
for k in stick branch club dagger hatchet axe brand poleaxe broadsword; do t_give townie "$k"; done
t_get /shop/buy/66;               expect_body 'Your bag is full.'
t_post /shop/buy/66 "csrf=$TC&submit=Buy"; expect_body 'Your bag is full.'
t_get /shop/buy/67;               expect_body 'max="8"'
t_post /shop/buy/67 "csrf=$TC&submit=Buy&qty=8"
expect_db "gold" "520" "topped up a stack in a full bag"
t_get /shop/buy/67;               expect_body 'Your bag is full.'
# selling part of a stack
POTION_E=$(t_sql "SELECT min(ui.id) FROM user_items ui JOIN users u ON u.id = ui.user_id WHERE u.username = 'townie' AND ui.item_id = 67")
t_get /shop;                      expect_body 'aria-label="Sell Potion for 30 gold each">'; expect_body '<span class="item-badge item-badge-qty" aria-hidden="true">x10</span>'
t_post "/shop/sell/$POTION_E" "csrf=$TC&submit=Sell&qty=11"; expect_body 'Please enter a quantity from 1 to 10.'
t_post "/shop/sell/$POTION_E" "csrf=$TC&submit=Sell&qty=3"; expect_body 'You sold 3 x Potion for 90 gold.'
expect_db "gold" "610" "sold 3 potions"
t_post "/shop/sell/$POTION_E" "csrf=$TC&submit=Sell&qty=7"; expect_body 'You sold 7 x Potion for 210 gold.'
expect_db "gold" "820" "sold the stack"
[ "$(t_sql "SELECT count(*) FROM user_items WHERE id = $POTION_E")" = 0 ] && t_ok || t_fail "empty stack kept"
t_items_clear townie
tu "$TOWN_BASE"

t_section "town: maps"
# the market sells the maps of town_maps (by default a town's neighbours along the road:
# Midworld only Roma's); /maps is the market's now
tu "$TOWN_HOME, towns='0,1', gold=100"
t_get /maps;                      expect_redirect /shop
t_get /shop;                      expect_status 200; expect_body '<title>Market</title>'
expect_body '<span class="shop-group-label" id="shop-maps-label">Maps</span>'
expect_body '<li><a class="market-map" href="/maps/buy/2" data-modal><b>Roma</b><span>25 gold</span></a></li>'
expect_no_body 'href="/maps/buy/3"'      # Bris's map isn't sold in Midworld
t_get /maps/buy/3;                expect_body 'Cheat attempt detected.'
t_get /maps/buy/2;                expect_body 'You are buying the Roma map. Is that ok?'
expect_body '<input type="submit" name="cancel" value="No" data-modal-close>'
t_post /maps/buy/2 "csrf=$TC&cancel=No"; expect_redirect /shop
t_post /maps/buy/2 "submit=Yes";  expect_status 403
t_post /maps/buy/2 "csrf=$TC&submit=Yes"; expect_body 'Thank you for purchasing this map.'
expect_db "towns,gold" "0,1,2|75" "buy roma map"
expect_body 'the <a href="/shop">market</a>'
t_get /shop;                      expect_body '<li class="market-map market-map-owned"><b>Roma</b><span>On your map: 30N, 30E &middot; 5 TP</span></li>'
t_get /maps/buy/2 -H 'X-DK-Modal: 1'; expect_body 'Cheat attempt detected.'   # mapped
t_post /maps/buy/2 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_post /maps/buy/99 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_get /maps/buy/99;               expect_body 'Cheat attempt detected.'
expect_db "towns,gold" "0,1,2|75" "map cheats"
# in Roma: Midworld's and Bris's maps (Midworld's on the map already); the gold short
tu "latitude=30, longitude=30, gold=10"
t_get /shop;                      expect_body '<li><a class="market-map shop-short" href="/maps/buy/3" data-modal><b>Bris</b><span>50 gold</span></a></li>'
expect_body '<li class="market-map market-map-owned"><b>Midworld</b>'; expect_no_body 'href="/maps/buy/4"'
t_get /maps/buy/3;                expect_body 'You do not have enough gold to buy this map.'
t_post /maps/buy/3 "csrf=$TC&submit=Yes"; expect_body 'You do not have enough gold to buy this map.'
t_get /maps/buy/3 -H 'X-DK-Modal: 1'; expect_body 'You do not have enough gold to buy this map.<div class="dk-modal-actions"><button type="button" data-modal-close autofocus>Back to the market</button></div>'
tu "gold=1000"
t_post /maps/buy/4 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'   # Kalle's: not sold in Roma
tu "currentaction='Exploring', latitude=3, longitude=3"
t_get /maps;                      expect_body 'Cheat attempt detected.'
t_post /maps/buy/3 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
expect_db "towns" "0,1,2" "map bought outside town, or not sold there"

t_section "town: travel"
# the Towns box: a button per town on the map with its TP; here, out of reach or while
# fighting: disabled; no maps: where to buy them
tu "$TOWN_HOME, towns='0', currenttp=3, base_maxtp=50"
t_get /;                          expect_body 'No maps yet: buy them at a town'; expect_no_body 'action="/travel/'
tu "towns='0,1,2'"
t_get /;                          expect_body 'action="/travel/2"'
expect_body '<button class="towns-btn towns-here" type="submit" title="You are here" disabled><span class="towns-name">Midworld</span><span class="towns-cost">here</span></button>'
expect_body '<button class="towns-btn towns-short" type="submit" title="You need 2 more TP" disabled><span class="towns-name">Roma</span><span class="towns-cost">5 TP</span></button>'
expect_no_body 'action="/travel/3"'   # Bris isn't on the map
t_post /travel/2 "csrf=$TC";      expect_body 'You do not have enough TP to travel here.'
tu "currenttp=20"
t_get /;                          expect_body '<button class="towns-btn" type="submit" title="Travel to Roma for 5 TP"><span class="towns-name">Roma</span>'
t_post /travel/3 "csrf=$TC";      expect_body 'Cheat attempt detected.'        # Bris not mapped
t_post /travel/99 "csrf=$TC";     expect_body 'Cheat attempt detected.'
t_post /travel/1 "csrf=$TC";      expect_body 'You are already in this town.'
expect_db "currenttp" "20" "no tp for staying"
t_post /travel/2 "";              expect_status 403
t_post /travel/2 "csrf=$TC";      expect_redirect /    # the town's page at once (3.0: no page in between)
expect_db "currentaction,latitude,longitude,currenttp,towns" "In Town|30|30|15|0,1,2" "travel to roma"
t_get /;                          expect_body 'Welcome to Roma'
tu "currentaction='Fighting'"
t_get /fight;                     expect_body 'title="Not while fighting" disabled><span class="towns-name">Midworld</span>'
t_post /travel/1 "csrf=$TC";      expect_redirect /fight
expect_db "latitude,currenttp" "30|15" "travel while fighting"

t_section "town: move"
tu "currentaction='Exploring', latitude=10, longitude=10, towns='0', dropcode=7"; t_fight_clear townie
t_post /move "north=North";       expect_status 403
t_post /move "csrf=$TC&north=North"
expect_db "latitude,longitude,dropcode" "11|10|0" "move north"
case $(tq currentaction) in
	Exploring) expect_redirect / ;;
	Fighting)  expect_redirect /fight; expect_db "$T_ROUND,$T_MONSTER > 0" "2|1" "fight started (the monster picked)" ;;
	"In Town") expect_redirect /fight ;;   # killed by the monster's first strike: its page
	*) t_fail "move set currentaction to $(tq currentaction)" ;;
esac
fights=0 explores=0
for _ in $(seq 1 40); do
	tu "currentaction='Exploring', latitude=10, longitude=10"; t_fight_clear townie
	t_post /move "csrf=$TC&east=East"
	case $(tq "currentaction||','||$T_ROUND||','||longitude") in
		Exploring,0,11) explores=$((explores + 1)) ;;
		Fighting,2,11|"In Town,0,0")  fights=$((fights + 1)) ;;   # (or killed by its first strike)
		*) t_fail "unexpected move result $(tq "currentaction||','||$T_ROUND||','||longitude")" ;;
	esac
done
[ "$fights" -gt 0 ] && [ "$explores" -gt "$fights" ] && t_ok || t_fail "fight odds: $fights fights / $explores explores"
for dir in "north 250 5 250|5" "south -250 5 -250|5" "east 5 250 5|250" "west 5 -250 5|-250"; do
	read -r d lat lon want <<< "$dir"
	# (sturdy: an encounter's first strike at the edge of the map must not kill)
	tu "currentaction='Exploring', latitude=$lat, longitude=$lon, currenthp=100000, base_maxhp=100000"
	t_post /move "csrf=$TC&$d=x"
	expect_db "latitude||'|'||longitude" "$want" "clamp $d"
done
tu "currentaction='Exploring', latitude=0, longitude=1, towns='0', currenttp=4"
t_post /move "csrf=$TC&west=West"; expect_redirect /
expect_db "currentaction,latitude,longitude,currenttp,towns" "In Town|0|0|4|0,1" "walk into midworld"
tu "currentaction='In Town', latitude=-250, longitude=-250"
t_post /move "csrf=$TC&south=South"; expect_body 'You are already in this town.'
tu "currentaction='Fighting', latitude=3, longitude=3"
t_post /move "csrf=$TC&north=North"; expect_redirect /fight
expect_db "latitude" "3" "move while fighting"

t_section "town: heal spells"
tu "$TOWN_HOME, currenthp=5, base_maxhp=20, currentmp=20, base_maxmp=20"; t_spells townie ""
t_post /spell/1 "csrf=$TC";       expect_body 'You have not yet learned this spell.'
t_get /
tr -d '\n' < "$BODY" | grep -qF '<div class="box-body spellpanel"><span class="light">None</span></div>' && t_ok || t_fail "Fast Spells: None"
t_spells townie 1,2,6
t_get /;                          expect_body 'action="/spell/1"'
# Fast Spells: a grid of icon buttons, each its own form (CSRF) to /spell/<id>; town
# spells only (Hurt is not one), the icon or default.png, the MP cost as a badge
expect_body '<div class="spell-grid spell-grid-small">'
# each form carries its spell's tooltip (docs/APP.md "Tooltips"), opening to the left
expect_body '<form class="spell-tip" method="post" action="/spell/1" data-tip data-tip-side="left"><input type="hidden" name="csrf" value="'"$TC"'"><button class="spell-btn" type="submit" title="Heal (5 MP)" aria-label="Heal (5 MP)"><img src="/static/images/skills/heal.png" width="34" height="34" alt=""><span class="spell-mp" aria-hidden="true">5</span></button><template class="tip"><div class="tip-title">Heal</div><div class="tip-meta">5 MP · In fights and in town</div><div class="tip-body"><p>Restores hit points, in a fight or out of it.</p></div><div class="tip-lore"><p>The first word every young Mage learns,'
expect_body '<span class="spell-mp" aria-hidden="true">10</span></button><template class="tip"><div class="tip-title">Revive</div><div class="tip-meta">10 MP · In fights and in town</div><div class="tip-body"><p>'
expect_no_body '<div class="tip-lore"></div>'
expect_body '<button class="spell-btn" type="submit" title="Revive (10 MP)" aria-label="Revive (10 MP)"><img src="/static/images/skills/revive.png" width="34" height="34" alt=""><span class="spell-mp" aria-hidden="true">10</span></button>'
expect_no_body 'action="/spell/6"'; expect_no_body ' disabled><img'
# disabled (greyed out) only when the MP don't cover it
tu "currentmp=7"
t_get /;                          expect_body 'title="Revive (10 MP)" aria-label="Revive (10 MP)" disabled><img'
expect_body '<form class="spell-tip spell-tip-short" method="post" action="/spell/2" data-tip data-tip-side="left">'
expect_body 'title="Heal (5 MP)" aria-label="Heal (5 MP)"><img'
# casting with the panel's button: its form as the page has it (action and CSRF field; the button has no name)
FS_FORM=$(grep -o '<form class="spell-tip" method="post" action="/spell/1" data-tip data-tip-side="left"><input type="hidden" name="csrf" value="[0-9a-f]*">' "$BODY")
FS_ACTION=$(printf '%s' "$FS_FORM" | sed 's/.*action="\([^"]*\)".*/\1/'); FS_CSRF=$(printf '%s' "$FS_FORM" | sed 's/.*value="\([0-9a-f]*\)".*/\1/')
t_post "$FS_ACTION" "csrf=$FS_CSRF"; expect_body 'You have cast the Heal spell, and gained 10 Hit Points.'
expect_db "currenthp,currentmp" "15|2" "Fast Spells button"
expect_body 'title="Heal (5 MP)" aria-label="Heal (5 MP)" disabled><img'   # the page after: 2 MP left
tu "currenthp=5, currentmp=20"; t_spells townie 1,6
t_post /spell/6 "csrf=$TC";       expect_body 'This is not a healing spell.'
t_post /spell/2 "csrf=$TC";       expect_body 'You have not yet learned this spell.'
t_post /spell/1 "";               expect_status 403
tu "currentmp=4"
t_post /spell/1 "csrf=$TC";       expect_body 'You do not have enough Magic Points to cast this spell.'
tu "currentmp=20, currentaction='Fighting'"
t_post /spell/1 "csrf=$TC";       expect_body 'You cannot use the Quick Spells list during a fight.'
tu "currentaction='In Town', currenthp=20"
t_post /spell/1 "csrf=$TC";       expect_body 'Your Hit Points are already full.'
tu "currenthp=25"                 # above max (e.g. after losing a maxhp item): no "negative heal"
t_post /spell/1 "csrf=$TC";       expect_body 'Your Hit Points are already full.'
expect_db "currenthp,currentmp" "25|20" "no heal above max"
tu "currenthp=5"
t_post /spell/1 "csrf=$TC";       expect_body 'You have cast the Heal spell, and gained 10 Hit Points.'
expect_db "currenthp,currentmp" "15|15" "heal 1"
t_post /spell/1 "csrf=$TC";       expect_body 'and gained 5 Hit Points.'
expect_db "currenthp,currentmp" "20|10" "heal capped"

t_section "town: character + map"
tu "base_exp_bonus=-5, base_gold_bonus=10, level=1, experience=1234, charclass=1"
t_get /character;                 expect_status 200
expect_body '<b>Townie</b>'; expect_body 'Class: Mage'; expect_no_body 'Difficulty'
expect_body 'Experience: 1,234 <span class="light">(-5%)</span>'; expect_body '<span class="light">(+10%)</span>'
expect_body "Next Level: 15<"
expect_body 'Heal<br>'; expect_body 'Hurt<br>'; expect_no_body 'Revive<br>'; expect_no_body 'action="/move"'
tu "level=10"                     # lib/leveling.lua: Mage level 11 at 2,991 (the original table: 2,997)
t_get /character;                 expect_body "Next Level: 2,991<"
tu "level=99"
t_get /character;                 expect_body "Next Level: 16,777,215<"
tu "level=100"
t_get /character;                 expect_body 'Next Level: <span class="light">None</span>'
ADMIN_ID=$(t_sql "SELECT id FROM users WHERE username = '$ADMIN_USER'")
t_get "/character/$ADMIN_ID";     expect_status 200
expect_body 'Here is the character profile for <b>Admin</b>'; expect_body 'action="/move"'
expect_no_body 'Next Level'
t_get /character/999999;          expect_body 'No such user.'
t_get /map;                       expect_status 200; expect_body '<image href="/static/images/world.svg"'

t_section "town: babble"
# (the chat in detail, live: tests/e2e/chat.sh; the rate limit is lifted here by aging the
# player's messages)
babble_unlimit() { t_sql "UPDATE babble SET posttime = posttime - 10"; }
t_get /babble;                    expect_status 200; expect_body 'name="babble"'; expect_body 'maxlength="120"'
BC=$(t_csrf)
before=$(t_sql "SELECT count(*) FROM babble")
t_post /babble "babble=hi";       expect_status 403
t_post /babble "csrf=$BC&babble=$(t_enc '<script>alert(1)</script> & "q"')"; expect_redirect /babble
babble_unlimit
t_post /babble "csrf=$BC&babble=$(t_enc '   ')"; expect_redirect /babble
[ "$(t_sql "SELECT count(*) FROM babble")" = $((before + 1)) ] && t_ok || t_fail "blank babble stored"
[ "$(t_sql "SELECT babble FROM babble ORDER BY id DESC LIMIT 1")" = '<script>alert(1)</script> & "q"' ] && t_ok || t_fail "babble not stored raw"
t_get /babble
expect_body '<b class="babble-author">Townie</b><span class="babble-text">&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;q&quot;'; expect_no_body '<script>alert'
long=$(printf 'x%.0s' $(seq 1 200))
t_post /babble "csrf=$BC&babble=$long&submit=Babble"
[ "$(t_sql "SELECT length(babble) FROM babble ORDER BY id DESC LIMIT 1")" = 120 ] && t_ok || t_fail "babble not cut to 120"
t_sql "INSERT INTO babble (posttime, author, author_id, babble) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 52)
	SELECT 1000 + i, 'Townie', NULL, 'msg' || i FROM n"
t_get /babble
[ "$(grep -c 'class="babble-post[^"]*" data-id=' "$BODY")" = 50 ] && t_ok || t_fail "babble shows $(grep -c 'class="babble-post[^"]*" data-id=' "$BODY") posts"
expect_no_body '>msg2<'; expect_body '>msg3<'
[ "$(grep -o '>msg[0-9]*<' "$BODY" | head -n1)" = '>msg3<' ] && [ "$(grep -o '>msg[0-9]*<' "$BODY" | tail -n1)" = '>msg52<' ] \
	&& t_ok || t_fail "babble order (oldest first)"

t_section "town: ninja"
t_get /ninja;                     expect_redirect 'http://www\.se7enet\.com/img/shirtninja\.jpg'

t_section "town: character panel (right column)"
# compact panel: CSS-gradient bars with values; HP coloured by how full, MP and TP fixed;
# HP/MP at or below a fifth blink (no bar images any more)
t_items_clear townie
tu "$TOWN_HOME, currenthp=3, base_maxhp=15, currentmp=9, base_maxmp=20, currenttp=10, base_maxtp=10"
t_get /inventory;                 expect_status 200
expect_body '<span class="meter-fill bar-low" data-bar="hp" style="width: 20%"></span>'
expect_body '<span class="meter-value highlight blink" data-meter="hp" data-max="15"><b>3</b>/15</span>'
expect_body '<span class="meter-fill bar-mp" data-bar="mp" style="width: 45%"></span>'
expect_body '<span class="meter-value" data-meter="mp" data-max="20"><b>9</b>/20</span>'
expect_body '<span class="meter-fill bar-tp" data-bar="tp" style="width: 100%"></span>'
expect_no_body 'bars_'
tu "currenthp=12"
t_get /inventory;                 expect_body '<span class="meter-fill bar-high" data-bar="hp" style="width: 80%"></span>'
expect_body '<span class="meter-value" data-meter="hp" data-max="15"><b>12</b>/15</span>'
tu "currenthp=7"
t_get /inventory;                 expect_body '<span class="meter-fill bar-mid" data-bar="hp" style="width: 47%"></span>'
t_get /static/images/bars_green.gif; expect_status 404

t_section "town: inventory panel (right column)"
# bag first, then the gear: icons for weapon/armor/shield, numbered badges for the slots,
# "None" greyed; the full label in each row's title (a tooltip: plain for an empty slot, the
# item's for gear)
t_get /inventory
expect_body '<a class="invpanel-bag" href="/inventory" title="Open your bag"><span>Bag</span><span class="invpanel-count"><b>0</b>/12</span></a>'
expect_body '<li title="Weapon: None" data-tip data-tip-side="left"><img src="/static/images/icon_weapon.gif" width="15" height="15" alt="Weapon"><span class="invpanel-name light">None</span></li>'
expect_body '<li class="invpanel-first-slot" title="Slot 1: None" data-tip data-tip-side="left"><span class="invpanel-badge" aria-label="Slot 1">1</span>'
t_give townie stick 1 weapon; t_give townie life_pebble 1 accessory2
for k in herb potion ether antidote branch club dagger hatchet axe brand poleaxe broadsword; do t_give townie "$k"; done
t_get /inventory
expect_body '<li title="Weapon: Stick" data-tip data-tip-side="left" tabindex="0"><img class="invpanel-image" src="/static/images/items/stick.png" width="17" height="17" alt="Weapon"><span class="invpanel-name">Stick</span><template class="tip"><div class="tip-title"><img class="tip-icon" src="/static/images/items/stick.png" width="20" height="20" alt="">Stick</div><div class="tip-meta">Weapon</div><ul class="tip-lines"><li>Attack Power +2</li></ul>'
expect_body '<li title="Slot 2: Life Pebble" data-tip data-tip-side="left" tabindex="0"><img class="invpanel-image" src="/static/images/items/life_pebble.png" width="17" height="17" alt="Slot 2"><span class="invpanel-name">Life Pebble</span><template class="tip"><div class="tip-title"><img class="tip-icon" src="/static/images/items/life_pebble.png" width="20" height="20" alt="">Life Pebble</div><div class="tip-meta">Accessory</div><ul class="tip-lines"><li>Max HP +10</li></ul>'
expect_body '<a class="invpanel-bag full" href="/inventory" title="Open your bag"><span>Bag</span><span class="invpanel-count"><b>12</b>/12</span></a>'
t_items_clear townie

tu "$TOWN_HOME"
t_jar default
fi
