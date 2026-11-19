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
t_register townie townpw1 townie@example.com Townie 1 1
t_login townie townpw1;           expect_redirect /
t_get /;                          expect_body 'Welcome to Midworld'
TC=$(t_csrf)
[ -n "$TC" ] && t_ok || t_fail "no csrf token on the town page"

t_section "town: inn"
tu "$TOWN_HOME, gold=100, currenthp=1, currentmp=0, currenttp=0, maxhp=20, maxmp=10, maxtp=12"
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
tu "$TOWN_HOME, gold=1000, weaponid=0, weaponname='None', armorid=0, armorname='None', shieldid=0, shieldname='None', attackpower=5, defensepower=5, strength=5, dexterity=5, goldbonus=0, expbonus=0"
t_get /shop;                      expect_status 200
expect_body 'href="/shop/buy/1">Stick</a>'; expect_body 'Price: <b>10 gold</b>'
expect_body 'Skivvies</a><span class="highlight">*</span>'; expect_no_body 'Dagger'
t_get /shop/buy/4;                expect_body 'Cheat attempt detected.'
t_post /shop/buy/4 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_post /shop/buy/999 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
expect_db "gold,weaponid" "1000|0" "cheat buy"

t_section "town: shop weapon + sell-back"
t_get /shop/buy/1;                expect_body 'You are buying the Stick, is that ok?'; expect_body 'action="/shop/buy/1"'
t_post /shop/buy/1 "submit=Yes";  expect_status 403
t_post /shop/buy/1 "csrf=$TC&cancel=No"; expect_redirect /
expect_db "gold,weaponid" "1000|0" "shop cancel"
t_post /shop/buy/1 "csrf=$TC&submit=Yes"; expect_body 'Thank you for purchasing this item.'
expect_db "gold,attackpower,weaponid,weaponname" "990|7|1|Stick" "buy stick"
t_get /shop;                      expect_body 'Already purchased'
t_post /shop/buy/1 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'
t_get /shop/buy/2;                expect_body 'If you are buying the Branch, then I will buy your Stick for 5 gold. Is that ok?'
t_post /shop/buy/2 "csrf=$TC&submit=Yes"
# 990 + ceil(10/2) - 30 ; 7 + 4 - 2
expect_db "gold,attackpower,weaponid,weaponname" "965|9|2|Branch" "branch replaces stick"

t_section "town: shop armor specials"
t_post /shop/buy/17 "csrf=$TC&submit=Yes"     # Skivvies: 25 gold, def 2, goldbonus,10
expect_db "gold,defensepower,armorid,goldbonus" "940|7|17|10" "skivvies"
t_get /shop/buy/18;               expect_body 'then I will buy your Skivvies for 13 gold'
t_post /shop/buy/18 "csrf=$TC&submit=Yes"     # Clothes: 940 + ceil(25/2) - 50 ; 7 + 5 - 2
expect_db "gold,defensepower,armorid,armorname,goldbonus" "903|10|18|Clothes|0" "clothes sells skivvies"

t_section "town: shop shield maxhp special + clamping"
tu "gold=1000, shieldid=33, shieldname='Destiny Aegis', defensepower=110, maxhp=70, currenthp=70, maxmp=10, currentmp=10"
t_post /shop/buy/28 "csrf=$TC&submit=Yes"     # Reed Shield 50/2; sells Aegis (25000, 100, maxhp,50)
# gold 1000 + 12500 - 50 ; def 110 + 2 - 100 ; maxhp 70 - 50 ; currenthp clamped to 20
expect_db "gold,defensepower,shieldid,maxhp,currenthp,currentmp" "13450|12|28|20|20|10" "reed shield sells aegis"

t_section "town: shop strength special"
tu "gold=100, weaponid=16, weaponname='Destiny Blade', strength=55, attackpower=300"
t_post /shop/buy/3 "csrf=$TC&submit=Yes"      # Club 40/5; sells Destiny Blade (50000, 250, strength,50)
# gold 100 + 25000 - 40 ; strength 55 - 50 ; atk 300 - 50 + 5 - 250
expect_db "gold,strength,attackpower,weaponid" "25060|5|5|3" "club sells destiny blade"
tu "gold=5"
t_get /shop/buy/18;               expect_body 'Cheat attempt detected.'      # already wearing clothes
t_get /shop/buy/19;               expect_body 'You do not have enough gold to buy this item.'
t_post /shop/buy/19 "csrf=$TC&submit=Yes"; expect_body 'You do not have enough gold to buy this item.'
expect_db "gold,armorid" "5|18" "shop too poor"
# sell-back counts toward the price: 50 gold + 25 for the Clothes covers Leather Armor (75)
tu "gold=50"
t_get /shop/buy/19;               expect_body 'I will buy your Clothes for 25 gold'
t_post /shop/buy/19 "csrf=$TC&submit=Yes"
expect_db "gold,armorid" "0|19" "sell-back covers price"
tu "gold=0, armorid=18, armorname='Clothes'"
t_post /shop/buy/19 "csrf=$TC&submit=Yes"; expect_body 'You do not have enough gold to buy this item.'
expect_db "gold,armorid" "0|18" "sell-back alone too little"

t_section "town: shop at Endworld + Bris"
tu "currentaction='In Town', latitude=-250, longitude=-250, gold=30000, shieldid=0, shieldname='None', defensepower=10, maxhp=20, currenthp=20"
t_post /shop/buy/33 "csrf=$TC&submit=Yes"
expect_db "gold,defensepower,shieldid,maxhp,currenthp" "5000|110|33|70|20" "buy aegis"
tu "latitude=70, longitude=-70, gold=1000"
t_get /shop;                      expect_body 'Hard Leather Armor'; expect_body 'Buckler'; expect_body 'Small Shield'
t_post /shop/buy/29 "csrf=$TC&submit=Yes"     # Buckler 100/4; sells Aegis (25000, 100, maxhp,50)
expect_db "gold,shieldid,defensepower,maxhp,currenthp" "13400|29|14|20|20" "bris sells buckler"
tu "latitude=5, longitude=5, currentaction='Exploring'"
t_get /shop;                      expect_body 'Cheat attempt detected.'
t_post /shop/buy/1 "csrf=$TC&submit=Yes"; expect_body 'Cheat attempt detected.'

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
tu "$TOWN_HOME, towns='0,1,2', currenttp=3, maxtp=50"
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
tu "currentaction='Exploring', latitude=10, longitude=10, towns='0', dropcode=7, currentfight=0"
t_post /move "north=North";       expect_status 403
t_post /move "csrf=$TC&north=North"
expect_db "latitude,longitude,dropcode" "11|10|0" "move north"
case $(tq currentaction) in
  Exploring) expect_redirect / ;;
  Fighting)  expect_redirect /fight; expect_db currentfight 1 "fight started" ;;
  *) t_fail "move set currentaction to $(tq currentaction)" ;;
esac
fights=0 explores=0
for _ in $(seq 1 40); do
  tu "currentaction='Exploring', latitude=10, longitude=10, currentfight=0"
  t_post /move "csrf=$TC&east=East"
  case $(tq "currentaction||','||currentfight||','||longitude") in
    Exploring,0,11) explores=$((explores + 1)) ;;
    Fighting,1,11)  fights=$((fights + 1)) ;;
    *) t_fail "unexpected move result $(tq "currentaction||','||currentfight||','||longitude")" ;;
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
tu "$TOWN_HOME, spells='0', currenthp=5, maxhp=20, currentmp=20, maxmp=20"
t_post /spell/1 "csrf=$TC";       expect_body 'You have not yet learned this spell.'
tu "spells='0,1,6'"
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
tu "expbonus=-5, goldbonus=10, level=1, experience=1234, charclass=1"
t_get /character;                 expect_status 200
expect_body '<b>Townie</b>'; expect_body 'Class: Mage'; expect_body 'Difficulty: Easy'
expect_body 'Experience: 1,234 <span class="light">(-5%)</span>'; expect_body '<span class="light">(+10%)</span>'
expect_body "Next Level: $(t_sql 'SELECT "1_exp" FROM levels WHERE id = 2')<"
expect_body 'Heal<br>'; expect_body 'Hurt<br>'; expect_no_body 'Revive<br>'; expect_no_body 'action="/move"'
tu "level=99"
t_get /character;                 expect_body 'Next Level: <span class="light">None</span>'
ADMIN_ID=$(t_sql "SELECT id FROM users WHERE username = '$ADMIN_USER'")
t_get "/character/$ADMIN_ID";     expect_status 200
expect_body 'Here is the character profile for <b>Admin</b>'; expect_body 'action="/move"'
expect_no_body 'Next Level'
t_get /character/999999;          expect_body 'No such user.'
t_get /map;                       expect_status 200; expect_body 'src="/static/images/map.gif"'

t_section "town: babble"
t_get /babble;                    expect_status 200; expect_body 'name="babble"'; expect_body 'maxlength="120"'
BC=$(t_csrf)
before=$(t_sql "SELECT count(*) FROM babble")
t_post /babble "babble=hi";       expect_status 403
t_post /babble "csrf=$BC&babble=$(t_enc '<script>alert(1)</script> & "q"')"; expect_redirect /babble
t_post /babble "csrf=$BC&babble=$(t_enc '   ')"; expect_redirect /babble
[ "$(t_sql "SELECT count(*) FROM babble")" = $((before + 1)) ] && t_ok || t_fail "blank babble stored"
[ "$(t_sql "SELECT babble FROM babble ORDER BY id DESC LIMIT 1")" = '<script>alert(1)</script> & "q"' ] && t_ok || t_fail "babble not stored raw"
t_get /babble
expect_body '[<b>Townie</b>] &lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;q&quot;'; expect_no_body '<script>alert'
long=$(printf 'x%.0s' $(seq 1 200))
t_post /babble "csrf=$BC&babble=$long&submit=Babble"
[ "$(t_sql "SELECT length(babble) FROM babble ORDER BY id DESC LIMIT 1")" = 120 ] && t_ok || t_fail "babble not cut to 120"
for i in $(seq 1 22); do t_post /babble "csrf=$BC&babble=msg$i"; done
t_get /babble
[ "$(grep -c 'class="babble-post"' "$BODY")" = 20 ] && t_ok || t_fail "babble shows $(grep -c 'class="babble-post"' "$BODY") posts"
expect_no_body '] msg2<'; expect_body '] msg3<'
[ "$(grep -o '] msg[0-9]*<' "$BODY" | head -n1)" = '] msg3<' ] && [ "$(grep -o '] msg[0-9]*<' "$BODY" | tail -n1)" = '] msg22<' ] \
  && t_ok || t_fail "babble order (oldest first)"

t_section "town: ninja"
t_get /ninja;                     expect_redirect 'http://www\.se7enet\.com/img/shirtninja\.jpg'

tu "$TOWN_HOME"
t_jar default
fi
