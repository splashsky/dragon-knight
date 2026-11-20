# tests/e2e/playthrough.sh :: one player's journey through the HTTP surface, start to finish,
# plus a short concurrency check. Sourced by tests/run.sh (helpers in docs/APP.md).
# SQL is used only to read results and to overrule the dice (encounters, drops, damage).

if ! t_has_sql; then
	t_section "playthrough (skipped: needs sqlite3 or python3)"
else

pq() { t_sql "SELECT $1 FROM users WHERE username = 'pthero'"; }
pu() { t_sql "UPDATE users SET $1 WHERE username = 'pthero'"; }
pt_is() { # pt_is "col,col" "v|v" label
	local got; got=$(pq "$1")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$3: $1 = '$got', expected '$2'"; fi
}
pt_admin_setting() { # pt_admin_setting name=value (as the admin, via the settings form)
	t_jar pt_admin
	t_get /admin/settings; expect_status 200
	t_form_submit /admin/settings "$1"; expect_redirect '/admin/settings\?saved=1'
	t_jar pt_hero
}
# Walk around next to Midworld until an encounter starts (forced if the dice refuse).
pt_explore() {
	local i dir=north
	for i in $(seq 1 80); do
		t_post /move "csrf=$TC&$dir=$dir"
		if [ "$STATUS" = 302 ] && grep -qiE '^location: /fight' "$HEADERS"; then t_ok; return; fi
		expect_redirect /
		if [ $((i % 2)) = 1 ]; then dir=east; else dir=west; fi
	done
	t_fight_new pthero
}
# Walk back into Midworld (entering a town adds its map), fighting whatever turns up.
pt_walk_home() {
	local i lat lon dir
	for i in $(seq 1 20); do
		[ "$(pq currentaction)" = "In Town" ] && break
		lat=$(pq latitude); lon=$(pq longitude)
		if [ "$lon" -gt 0 ]; then dir=west; elif [ "$lon" -lt 0 ]; then dir=east
		elif [ "$lat" -gt 0 ]; then dir=south; else dir=north; fi
		t_post /move "csrf=$TC&$dir=$dir"
		if [ "$STATUS" = 302 ] && grep -qiE '^location: /fight' "$HEADERS"; then pt_fight; fi
	done
	expect_body 'You have travelled to Midworld.'
	pt_is "currentaction,latitude,longitude" "In Town|0|0" "walked home"
}
# Fight the current encounter until the victory page.
pt_fight() {
	local i
	t_get /;      expect_redirect /fight
	t_get /fight; expect_status 200; expect_body 'You are fighting a <b class="tip-term" data-tip tabindex="0">'
	for i in $(seq 1 60); do
		[ "$(pq currenthp)" -lt 8 ] && pu "currenthp = base_maxhp"   # keep the dice from killing us
		t_post /fight "csrf=$TC&fight=Fight"
		[ "$STATUS" = 302 ] && break
		expect_status 200; expect_no_body 'You have died.'
	done
	expect_redirect /victory
	t_get /victory; expect_status 200; expect_body 'Congratulations. You have defeated the'
	pt_is "currentaction,$T_ROUND" "Exploring|0" "after victory"
}

t_section "playthrough: admin turns on email verification"
t_jar pt_admin; t_reset_jar
t_login "$ADMIN_USER" "$ADMIN_PASS"; expect_redirect /
t_jar pt_hero; t_reset_jar
pt_admin_setting verifyemail=1
[ "$(t_sql 'SELECT verifyemail FROM control')" = 1 ] && t_ok || t_fail "verifyemail not enabled"

t_section "playthrough: register + verify"
t_get /;         expect_redirect /login
t_get /register; expect_body 'A verification code will be sent'
mails=$(t_mail_count)
t_register pthero heropass1 pthero@example.com Wanderer 1
expect_body 'You should receive an Account Verification email'
[ "$(t_mail_count)" -gt "$mails" ] && t_ok || t_fail "no verification mail"
MAIL=$(t_mail_latest)
grep -q '^To: pthero@example.com' "$MAIL" && t_ok || t_fail "verification mail recipient"
CODE=$(sed -n 's/^Verification code: \([A-Z]\{8\}\).*/\1/p' "$MAIL" | tr -d '\r')
[ -n "$CODE" ] && t_ok || t_fail "no code in the verification mail"
t_login pthero heropass1; expect_redirect /
t_get /;         expect_redirect /verify
t_get /verify
t_post /verify "csrf=$(t_csrf)&username=pthero&email=$(t_enc pthero@example.com)&verify=$CODE"
expect_body 'Your account was verified successfully.'
pt_admin_setting verifyemail=0
[ "$(t_sql 'SELECT verifyemail FROM control')" = 0 ] && t_ok || t_fail "verifyemail not disabled"

t_section "playthrough: town, inn, shop, maps"
t_get /;         expect_status 200; expect_body 'Welcome to Midworld'; expect_body 'Town Options'
expect_body '>Wanderer</a>'
TC=$(t_csrf)
pt_is "gold,currenthp,base_maxhp,level" "100|15|15|1" "new character"
pt_is "currentmp,base_maxmp,$T_KNOWN" "5|5|25" "a new Mage: 5 MP and Magic Bolt"
t_get /inn;      expect_body 'Resting at the inn'
t_post /inn "csrf=$TC&submit=Yes"; expect_body 'You wake up feeling refreshed and ready for action.'
t_get /shop;     expect_body 'href="/shop/buy/1" data-tip>Stick<template class="tip">'
t_get /shop/buy/1; expect_text 'You are buying the Stick, is that ok?'
t_post /shop/buy/1 "csrf=$TC&submit=Yes"; expect_body 'Thank you for purchasing this item.'
t_get /shop/buy/66; expect_text 'You are buying the Herb for 15 gold each.'
t_post /shop/buy/66 "csrf=$TC&submit=Buy&qty=2"; expect_body 'Thank you for purchasing this item.'
t_get /maps;     expect_body 'href="/maps/buy/2">Roma</a>'
t_get /maps/buy/2; expect_body 'You are buying the Roma map. Is that ok?'
t_post /maps/buy/2 "csrf=$TC&submit=Yes"; expect_body 'Thank you for purchasing this map.'
pt_is "gold,$T_ITEMS,towns" "30|stick@weapon,herbx2|0,2" "after shopping"
t_get /;         expect_body 'Weapon: Stick'; expect_body '<span class="invpanel-count"><b>1</b>/12</span></a>'
expect_stats "15 5 10 5 5 7 5" "a stick adds 2 attack power"

t_section "playthrough: explore, fight, level up"
pu "experience = 14"   # one kill short of level 2
pt_explore
pt_fight
expect_body 'You have gained a level!'; expect_body 'You have learned a new spell.'
pt_is "level,base_maxmp,$T_KNOWN" "2|10|1,25" "level up (+5 MP, Heal)"
t_get /victory;  expect_body 'You have gained a level!'   # shown again, paid once
pt_is level 2 "paid once"
pt_walk_home

t_section "playthrough: travel"
pt_is "towns" "0,2,1" "maps after walking into Midworld"
t_post /travel/2 "csrf=$TC"; expect_body 'You have travelled to Roma.'
t_get /;         expect_body 'Welcome to Roma'
t_post /travel/1 "csrf=$TC"; expect_body 'You have travelled to Midworld.'
pt_is "currentaction,latitude,longitude,currenttp" "In Town|0|0|5" "back in Midworld"

t_section "playthrough: second fight + item drop"
t_post /inn "csrf=$TC&submit=Yes"; expect_body 'You wake up feeling refreshed'
pt_is "currentmp" "10" "inn restores mp"
pt_explore
pt_fight
if grep -qF 'This monster has dropped an item' "$BODY"; then t_ok; else pu "dropcode = 34"; fi
DROP=$(pq dropcode)
t_get /drop;     expect_status 200; expect_body 'name="take" value="Take it"'
t_post /drop "csrf=$TC&take=Take+it"; expect_body 'is in your bag.'
[ "$(pq "dropcode = 0 AND (SELECT count(*) FROM user_items WHERE user_id = users.id AND item_id = $DROP AND equipped IS NULL)")" = 1 ] \
	&& t_ok || t_fail "drop not in the bag"

t_section "playthrough: inventory"
t_get /inventory; expect_status 200; expect_body 'Bag (2 / 12)'; expect_text 'Herb x2'
DROP_E=$(t_sql "SELECT ui.id FROM user_items ui JOIN users u ON u.id = ui.user_id WHERE u.username = 'pthero' AND ui.item_id = $DROP")
t_post "/inventory/equip/$DROP_E" "csrf=$TC&slot=0"; expect_body 'You equipped the'
[ "$(pq "(SELECT equipped FROM user_items WHERE id = $DROP_E)")" = accessory1 ] && t_ok || t_fail "drop not equipped in slot 1"
t_get /;         expect_no_body 'Slot 1: None'
pu "currenthp = 1"
HERB_E=$(t_sql "SELECT ui.id FROM user_items ui JOIN users u ON u.id = ui.user_id WHERE u.username = 'pthero' AND ui.item_id = 66")
t_post "/inventory/use/$HERB_E" "csrf=$TC"; expect_body 'You have used the Herb, and gained'
pt_is "$T_ITEMS" "stick@weapon,herb,$(t_sql "SELECT key FROM items WHERE id = $DROP")@accessory1" "a herb used"

t_section "playthrough: heal spell"
[ "$(pq "currenthp < base_maxhp")" = 1 ] || pu "currenthp = 1"
t_get /;         expect_body 'action="/spell/1"'
t_post /spell/1 "csrf=$TC"; expect_body 'You have cast the Heal spell'
pt_is "currentmp" "5" "heal costs 5 mp"

t_section "playthrough: babble + forum"
t_get /babble;   expect_status 200
t_post /babble "csrf=$TC&babble=$(t_enc 'Hello from the playthrough')"; expect_redirect /babble
t_get /babble;   expect_body '[<b>Wanderer</b>] Hello from the playthrough'
t_get /forum;    expect_status 200
t_get /forum/1/new; expect_body 'Make A New Post'
t_post /forum/1/new "csrf=$TC&title=$(t_enc 'Journey log')&content=$(t_enc 'Found a Stick.')"; expect_redirect /forum/1
t_get /forum/1
THREAD=$(grep -o 'href="/forum/thread/[0-9]*">Journey log<' "$BODY" | grep -o '[0-9][0-9]*')
[ -n "$THREAD" ] && t_ok || t_fail "new thread not listed"
t_post "/forum/reply/$THREAD" "csrf=$TC&content=$(t_enc 'And a Life Pebble.')"; expect_redirect "/forum/thread/$THREAD"
t_get "/forum/thread/$THREAD"; expect_body 'Found a Stick.'; expect_body 'And a Life Pebble.'

t_section "playthrough: news"
t_get /;         expect_body 'href="/news">News</a>'
t_get /news;     expect_status 200; expect_body 'This is the first news post.'
t_get /news/1;   expect_status 200
NEWS_THREAD=$(grep -o 'href="/forum/thread/[0-9]*"' "$BODY" | head -n1 | grep -o '[0-9][0-9]*')
[ -n "$NEWS_THREAD" ] && t_ok || t_fail "no discussion link on the news post"
t_post "/forum/reply/$NEWS_THREAD" "csrf=$TC&content=$(t_enc 'Welcome to me.')"; expect_redirect "/forum/thread/$NEWS_THREAD"
t_get "/forum/thread/$NEWS_THREAD"; expect_body 'href="/forum/2">News</a>'; expect_body 'Welcome to me.'
t_get /news/1;   expect_body "href=\"/forum/thread/$NEWS_THREAD\">$(t_sql "SELECT replies FROM forum WHERE id = $NEWS_THREAD") repl"

t_section "playthrough: help pages"
for p in /help /help/items /help/spells /help/monsters /help/levels; do
	t_get "$p"; expect_status 200; expect_body '<body class="minimal theme-default help" data-live data-csrf="'; expect_body 'Help'
done

t_section "playthrough: character pages"
t_get /character; expect_status 200; expect_body '<b>Wanderer</b>'; expect_body 'Class: Mage'
t_get /map;      expect_status 200; expect_body 'map.gif'
t_post /travel/1 "csrf=$TC"
t_get /
ADMIN_LINK=$(grep -o 'href="/character/[0-9]*">Admin<' "$BODY" | grep -o '/character/[0-9]*')
[ -n "$ADMIN_LINK" ] && t_ok || t_fail "admin not in Who's Online"
t_get "$ADMIN_LINK"; expect_body 'Here is the character profile for <b>Admin</b>'

t_section "playthrough: change password, logout, login"
t_get /changepassword; expect_status 200
t_post /changepassword "csrf=$(t_csrf)&username=pthero&oldpass=heropass1&newpass1=heropass2&newpass2=heropass2"
expect_body 'Your password was changed successfully.'
t_get /;         expect_redirect /login
t_login pthero heropass1; expect_body 'Invalid username or password'
t_login pthero heropass2; expect_redirect /
t_get /;         expect_status 200; expect_body 'Welcome to Midworld'
t_logout;        expect_redirect /login
t_get /;         expect_redirect /login
t_login pthero heropass2; expect_redirect /

t_section "playthrough: concurrency"
for i in $(seq 1 20); do
	t_jar "pt_cc$i"; t_reset_jar
	t_register "ptcc$i" ccpass1 "ptcc$i@example.com" "Crowd$i"
	t_login "ptcc$i" ccpass1; expect_redirect /
done
mark=$(wc -l < "$T/server.log")
pids=
for i in $(seq 1 20); do
	(for _ in $(seq 1 25); do
		curl -s -o /dev/null -w '%{http_code}\n' -b "$T/jar.pt_cc$i" "$BASE/"
	done > "$T/pt_cc.$i") &
	pids+=" $!"
done
# shellcheck disable=SC2086
wait $pids
ok=$(cat "$T"/pt_cc.* | grep -c '^200$')
[ "$ok" = 500 ] && t_ok || t_fail "concurrency: $ok/500 responses were 200 ($(sort "$T"/pt_cc.* | uniq -c | tr '\n' ' '))"
sleep 0.2
served=$(tail -n "+$((mark + 1))" "$T/server.log" | grep -c '"GET /" 200 ')
[ "$served" -ge 500 ] && t_ok || t_fail "concurrency: server logged $served/500 GET / 200"
if tail -n "+$((mark + 1))" "$T/server.log" | grep -qE '" 5[0-9][0-9] |\[error\]'; then
	t_fail "concurrency: server errors"; tail -n "+$((mark + 1))" "$T/server.log" | grep -E '" 5[0-9][0-9] |\[error\]' | head >&2
else
	t_ok
fi
[ "$(t_sql "SELECT count(*) FROM users WHERE username LIKE 'ptcc%' AND onlinetime > 0")" = 20 ] && t_ok || t_fail "concurrency: onlinetime"

t_jar default
fi
