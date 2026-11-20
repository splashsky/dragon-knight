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
tu "currentaction='Fighting'"
t_get /inn;                       expect_redirect /fight
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
expect_body 'href="/shop/buy/1">Stick</a>'; expect_body 'Price: <b>10 gold</b>'; expect_body 'Attack Power: 2'
expect_body 'Skivvies</a><span class="highlight">*</span>'; expect_no_body 'Dagger'
expect_body 'href="/shop/buy/66">Herb</a>'; expect_no_body '>Potion<'
expect_no_body 'I will buy these from your bag'
t_get /shop/buy/4;                expect_body 'Cheat attempt detected.'
t_post /shop/buy/4 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_post /shop/buy/999 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_post /shop/buy/67 "csrf=$TC&submit=Buy"; expect_body 'Cheat attempt detected.'      # Potions: not in Midworld
expect_db "gold,coalesce($T_ITEMS, '')" "1000|" "cheat buy"

t_section "town: shop weapon, keep or sell the old one"
t_get /shop/buy/1;                expect_body 'You are buying the Stick, is that ok?'; expect_body 'action="/shop/buy/1"'
t_post /shop/buy/1 "submit=Yes";  expect_status 403
t_post /shop/buy/1 "csrf=$TC&cancel=No"; expect_redirect /
expect_db "gold,coalesce($T_ITEMS, '')" "1000|" "shop cancel"
t_post /shop/buy/1 "csrf=$TC&submit=Yes"; expect_body 'Thank you for purchasing this item.'
expect_db "gold,$T_ITEMS" "990|stick@weapon" "buy stick"
expect_stats "15 0 10 5 5 7 5" "stick"
t_get /shop;                      expect_body 'Already purchased'
t_get /;                          expect_body 'Weapon: Stick'
t_post /shop/buy/1 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_get /shop/buy/2
expect_body 'You are buying the Branch for 30 gold. What should I do with your Stick?'
expect_body 'name="keep" value="Buy (keep my Stick in the bag)"'; expect_body 'name="sell" value="Buy and sell my Stick for 5 gold"'
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
expect_body '<td>Stick</td><td>5 gold</td>'; expect_no_body "action=\"/shop/sell/$WEAPON_E\""
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
t_get /shop/buy/18;               expect_body 'Buy and sell my Skivvies for 13 gold'
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
t_get /shop/buy/29;               expect_body "Your bag is full, so you can't keep your Reed Shield."
expect_no_body 'name="keep"'; expect_body 'Buy and sell my Reed Shield for 25 gold'
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
t_get /shop/buy/18;               expect_body 'Cheat attempt detected.'      # already wearing clothes
t_get /shop/buy/19;               expect_body 'You do not have enough gold to buy this item.'
t_post /shop/buy/19 "csrf=$TC&sell=x"; expect_body 'You do not have enough gold to buy this item.'
expect_db "gold" "5" "shop too poor"
# sell-back counts toward the price: 50 gold + 25 for the Clothes covers Leather Armor (75)
tu "gold=50"
t_get /shop/buy/19;               expect_body 'Buy and sell my Clothes for 25 gold'
expect_body "You don't have enough gold to buy it and keep your Clothes."; expect_no_body 'name="keep"'
t_post /shop/buy/19 "csrf=$TC&keep=x"; expect_body 'You do not have enough gold to buy this item.'
t_post /shop/buy/19 "csrf=$TC&sell=x"
expect_db "gold,$T_ITEMS" "0|buckler@shield,club@weapon,leather_armor@armor" "sell-back covers price"
t_sql "UPDATE user_items SET item_id = 18 WHERE equipped = 'armor' AND user_id = (SELECT id FROM users WHERE username = 'townie')"
t_post /shop/buy/19 "csrf=$TC&sell=x"; expect_body 'You do not have enough gold to buy this item.'
expect_db "gold" "0" "sell-back alone too little"

t_section "town: shop at Endworld + Bris"
t_sql "DELETE FROM user_items WHERE equipped = 'shield' AND user_id = (SELECT id FROM users WHERE username = 'townie')"
tu "currentaction='In Town', latitude=-250, longitude=-250, gold=30000, base_maxhp=20, currenthp=20"
t_get /shop;                      expect_body 'Destiny Aegis'; expect_body '>Potion</a>'; expect_body '>Ether</a>'
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
t_get /shop/buy/67;               expect_body 'You are buying the Potion for 60 gold each. It goes into your bag.'
expect_body 'name="qty"'; expect_body '(1 to 10)'
for q in 0 11 abc -1; do
	t_post /shop/buy/67 "csrf=$TC&submit=Buy&qty=$q"; expect_body 'Please enter a quantity from 1 to 10.'
done
expect_db "gold,coalesce($T_ITEMS, '')" "1000|" "no bad quantities"
t_post /shop/buy/67 "csrf=$TC&submit=Buy&qty=4"; expect_body 'Thank you for purchasing this item.'
expect_db "gold,$T_ITEMS" "760|potionx4" "4 potions"
t_get /shop/buy/67;               expect_body '(1 to 6)'                   # room on the stack
t_post /shop/buy/67 "csrf=$TC&submit=Buy&qty=6"
expect_db "gold,$T_ITEMS" "400|potionx10" "a full stack"
t_get /shop/buy/67;               expect_body '(1 to 6)'                   # a new stack: 400 gold buys 6
t_post /shop/buy/67 "csrf=$TC&submit=Buy&qty=2"
expect_db "gold,$T_ITEMS" "280|potionx10,potionx2" "a second stack"
# the gold limit
tu "gold=100"
t_get /shop/buy/68;               expect_body 'You are buying the Ether for 80 gold.'; expect_no_body 'name="qty"'
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
t_get /shop/buy/67;               expect_body '(1 to 8)'
t_post /shop/buy/67 "csrf=$TC&submit=Buy&qty=8"
expect_db "gold" "520" "topped up a stack in a full bag"
t_get /shop/buy/67;               expect_body 'Your bag is full.'
# selling part of a stack
POTION_E=$(t_sql "SELECT min(ui.id) FROM user_items ui JOIN users u ON u.id = ui.user_id WHERE u.username = 'townie' AND ui.item_id = 67")
t_get /shop;                      expect_body '<td>Potion x10</td><td>30 gold each</td>'
t_post "/shop/sell/$POTION_E" "csrf=$TC&submit=Sell&qty=11"; expect_body 'Please enter a quantity from 1 to 10.'
t_post "/shop/sell/$POTION_E" "csrf=$TC&submit=Sell&qty=3"; expect_body 'You sold 3 x Potion for 90 gold.'
expect_db "gold" "610" "sold 3 potions"
t_post "/shop/sell/$POTION_E" "csrf=$TC&submit=Sell&qty=7"; expect_body 'You sold 7 x Potion for 210 gold.'
expect_db "gold" "820" "sold the stack"
[ "$(t_sql "SELECT count(*) FROM user_items WHERE id = $POTION_E")" = 0 ] && t_ok || t_fail "empty stack kept"
t_items_clear townie
tu "$TOWN_BASE"

t_section "town: maps"
tu "$TOWN_HOME, towns='0,1', gold=100"
t_get /maps;                      expect_status 200
expect_body 'href="/maps/buy/2">Roma</a>'; expect_body 'Price: 25 gold'
expect_body '<span class="light">Midworld</span>'; expect_body 'Location: 0N, 0E'
t_get /maps/buy/2;                expect_body 'You are buying the Roma map. Is that ok?'
t_post /maps/buy/2 "csrf=$TC&cancel=No"; expect_redirect /
t_post /maps/buy/2 "submit=Yes";  expect_status 403
t_post /maps/buy/2 "csrf=$TC&submit=Yes"; expect_body 'Thank you for purchasing this map.'
expect_db "towns,gold" "0,1,2|75" "buy roma map"
t_get /maps;                      expect_body 'Location: 30N, 30E'; expect_body 'TP: 5'
t_post /maps/buy/2 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_post /maps/buy/99 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_get /maps/buy/99;               expect_body 'Cheat attempt detected.'
expect_db "towns,gold" "0,1,2|75" "map cheats"
tu "gold=10"
t_get /maps/buy/3;                expect_body 'You do not have enough gold to buy this map.'
t_post /maps/buy/3 "csrf=$TC&submit=Yes"; expect_body 'You do not have enough gold to buy this map.'
tu "currentaction='Exploring', latitude=3, longitude=3, gold=1000"
t_get /maps;                      expect_body 'Cheat attempt detected.'
t_post /maps/buy/3 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
expect_db "towns" "0,1,2" "map bought outside town"

t_section "town: travel"
tu "$TOWN_HOME, towns='0,1,2', currenttp=3, base_maxtp=50"
t_get /;                          expect_body 'action="/travel/2"'
t_post /travel/2 "csrf=$TC";      expect_body 'You do not have enough TP to travel here.'
tu "currenttp=20"
t_post /travel/3 "csrf=$TC";      expect_body 'Cheat attempt detected.'        # Bris not mapped
t_post /travel/99 "csrf=$TC";     expect_body 'Cheat attempt detected.'
t_post /travel/1 "csrf=$TC";      expect_body 'You are already in this town.'
expect_db "currenttp" "20" "no tp for staying"
t_post /travel/2 "";              expect_status 403
t_post /travel/2 "csrf=$TC";      expect_body 'You have travelled to Roma. You may now <a href="/">enter this town</a>.'
expect_db "currentaction,latitude,longitude,currenttp,towns" "In Town|30|30|15|0,1,2" "travel to roma"
t_get /;                          expect_body 'Welcome to Roma'
tu "currentaction='Fighting'"
t_post /travel/1 "csrf=$TC";      expect_redirect /fight
expect_db "latitude,currenttp" "30|15" "travel while fighting"

t_section "town: move"
tu "currentaction='Exploring', latitude=10, longitude=10, towns='0', dropcode=7"; t_fight_clear townie
t_post /move "north=North";       expect_status 403
t_post /move "csrf=$TC&north=North"
expect_db "latitude,longitude,dropcode" "11|10|0" "move north"
case $(tq currentaction) in
	Exploring) expect_redirect / ;;
	Fighting)  expect_redirect /fight; expect_db "$T_ROUND" 1 "fight started" ;;
	*) t_fail "move set currentaction to $(tq currentaction)" ;;
esac
fights=0 explores=0
for _ in $(seq 1 40); do
	tu "currentaction='Exploring', latitude=10, longitude=10"; t_fight_clear townie
	t_post /move "csrf=$TC&east=East"
	case $(tq "currentaction||','||$T_ROUND||','||longitude") in
		Exploring,0,11) explores=$((explores + 1)) ;;
		Fighting,1,11)  fights=$((fights + 1)) ;;
		*) t_fail "unexpected move result $(tq "currentaction||','||$T_ROUND||','||longitude")" ;;
	esac
done
[ "$fights" -gt 0 ] && [ "$explores" -gt "$fights" ] && t_ok || t_fail "fight odds: $fights fights / $explores explores"
for dir in "north 250 5 250|5" "south -250 5 -250|5" "east 5 250 5|250" "west 5 -250 5|-250"; do
	read -r d lat lon want <<< "$dir"
	tu "currentaction='Exploring', latitude=$lat, longitude=$lon"
	t_post /move "csrf=$TC&$d=x"
	expect_db "latitude||'|'||longitude" "$want" "clamp $d"
done
tu "currentaction='Exploring', latitude=0, longitude=1, towns='0', currenttp=4"
t_post /move "csrf=$TC&west=West"; expect_body 'You have travelled to Midworld.'
expect_db "currentaction,latitude,longitude,currenttp,towns" "In Town|0|0|4|0,1" "walk into midworld"
tu "currentaction='In Town', latitude=-250, longitude=-250"
t_post /move "csrf=$TC&south=South"; expect_body 'You are already in this town.'
tu "currentaction='Fighting', latitude=3, longitude=3"
t_post /move "csrf=$TC&north=North"; expect_redirect /fight
expect_db "latitude" "3" "move while fighting"

t_section "town: heal spells"
tu "$TOWN_HOME, currenthp=5, base_maxhp=20, currentmp=20, base_maxmp=20"; t_spells townie ""
t_post /spell/1 "csrf=$TC";       expect_body 'You have not yet learned this spell.'
t_spells townie 1,6
t_get /;                          expect_body 'action="/spell/1"'
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
t_get /map;                       expect_status 200; expect_body 'src="/static/images/map.gif"'

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
expect_body '[<b>Townie</b>] &lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;q&quot;'; expect_no_body '<script>alert'
long=$(printf 'x%.0s' $(seq 1 200))
t_post /babble "csrf=$BC&babble=$long&submit=Babble"
[ "$(t_sql "SELECT length(babble) FROM babble ORDER BY id DESC LIMIT 1")" = 120 ] && t_ok || t_fail "babble not cut to 120"
t_sql "INSERT INTO babble (posttime, author, author_id, babble) WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 52)
	SELECT 1000 + i, 'Townie', NULL, 'msg' || i FROM n"
t_get /babble
[ "$(grep -c 'class="babble-post"' "$BODY")" = 50 ] && t_ok || t_fail "babble shows $(grep -c 'class="babble-post"' "$BODY") posts"
expect_no_body '] msg2<'; expect_body '] msg3<'
[ "$(grep -o '] msg[0-9]*<' "$BODY" | head -n1)" = '] msg3<' ] && [ "$(grep -o '] msg[0-9]*<' "$BODY" | tail -n1)" = '] msg52<' ] \
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

tu "$TOWN_HOME"
t_jar default
fi
