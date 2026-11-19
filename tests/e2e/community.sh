# tests/e2e/community.sh :: forum (legacy forum.php) and help pages (help*.php). F3.
# Sourced by tests/run.sh; see docs/APP.md for the helpers.

t_section "help pages (logged out)"
t_jar f3anon; t_reset_jar
t_get /help;          expect_status 200; expect_body 'Dragon Knight Help</h1>'
expect_body '<b>Mage</b>'; expect_body 'Medium: <b>1.2</b>'; expect_body 'Easy: <b>1</b>'
expect_body 'Each quadrant is 250 spaces'; expect_body 'href="/help/items"'; expect_body 'href="/ninja"'
expect_no_body 'help_items.php'
t_get /help/items;    expect_status 200; expect_body 'Help: Items &amp; Drops'
expect_body '>Stick</td><td style="width: 20%">10 Gold</td><td style="width: 20%">2 Attack Power<'
expect_body '>Skivvies</td>'; expect_body 'Gold Bonus (%) +10'; expect_body 'icon_shield.gif'
expect_body '>Life Pebble</td><td style="width: 15%">1</td><td style="width: 30%">Max HP +10<'
t_get /help/spells;   expect_status 200; expect_body 'Help: Spells'
expect_body '>Heal</td><td style="width: 25%">5</td><td style="width: 25%">Heal</td><td style="width: 25%">10<'
expect_body '+Damage (%)'; expect_body '+Defense (%)'; expect_body 'X in 15 chance'
t_get /help/monsters; expect_status 200; expect_body 'Help: Monsters'
expect_body '>Blue Slime</td><td style="width: 10%">4</td>'; expect_body 'Hurt &amp; Sleep'
t_get /help/levels;   expect_status 200; expect_body 'Mage Levels'; expect_body 'Warrior Levels'; expect_body 'Paladin Levels'
expect_body '<tr><td>2</td><td>15</td><td>2</td><td>5</td><td>1</td><td>0</td><td>1</td><td>Heal</td></tr>'
expect_body '<tr><td>99</td><td>7,964,068</td>'; expect_no_body '<tr><td>100</td>'
expect_body 'Experience points listed are total values'
t_get /static/css/community.css; expect_status 200; expect_body 'table.forum'

t_section "forum: logged out"
t_get /forum;              expect_status 200; expect_body 'The forum is for registered players only.'
t_get /forum/new;          expect_body 'The forum is for registered players only.'
t_get /forum/thread/1;     expect_body 'The forum is for registered players only.'
t_get /login; t_post /forum/new "csrf=$(t_csrf)&title=x&content=y"; expect_body 'The forum is for registered players only.'

t_section "forum: threads"
t_jar f3user; t_reset_jar
t_register forumer forumpw1 forumer@example.com Forumer
t_login forumer forumpw1
t_get /forum;              expect_status 200; expect_body 'No threads in forum.'; expect_body 'href="/forum/new"'
t_get /;                   expect_body 'href="/forum"'
t_get /forum/new;          expect_status 200; expect_body 'Make A New Post'; expect_body 'action="/forum/new"'
TOKEN=$(t_csrf)
t_post /forum/new "title=NoToken&content=x"; expect_status 403
t_post /forum/new "csrf=$TOKEN&title=+++&content=$(t_enc 'keep me')"
expect_status 200; expect_body 'Title is required.'; expect_body 'keep me</textarea>'
t_post /forum/new "csrf=$TOKEN&title=Hello&content=+%0A+"; expect_body 'Message is required.'
LONG=$(printf 'x%.0s' $(seq 101))
t_post /forum/new "csrf=$TOKEN&title=$LONG&content=x"; expect_body 'Title must be 100 characters or less.'
t_post /forum/new "csrf=$TOKEN&title=$(t_enc '<script>alert(1)</script>')&content=$(t_enc $'<b>bold</b> & co\nline two')"
expect_redirect /forum
t_get /forum;              expect_body '&lt;script&gt;alert(1)&lt;/script&gt;'; expect_no_body '<script>alert'
expect_no_body 'NoToken'; expect_no_body 'No threads in forum.'
if t_has_sql; then
	[ "$(t_sql "SELECT count(*) FROM forum")" = 1 ] && t_ok || t_fail "exactly one thread stored"
	[ "$(t_sql "SELECT author || '|' || parent || '|' || replies FROM forum")" = "Forumer|0|0" ] && t_ok || t_fail "thread row"
	[ "$(t_sql "SELECT title FROM forum")" = '<script>alert(1)</script>' ] && t_ok || t_fail "title stored raw"
	XSS=$(t_sql "SELECT id FROM forum WHERE parent = 0")
	t_get "/forum/thread/$XSS"; expect_status 200
	expect_body 'Forum</a> :: &lt;script&gt;'; expect_body '&lt;b&gt;bold&lt;/b&gt; &amp; co<br />'; expect_no_body '<b>bold</b>'
	expect_body '<b>Forumer</b>'; expect_body "action=\"/forum/reply/$XSS\""

	t_section "forum: replies"
	t_sql "INSERT INTO forum (postdate, newpostdate, author, parent, replies, title, content) VALUES (100, 100, 'Old', 0, 0, 'Older thread', 'old')"
	OLD=$(t_sql "SELECT id FROM forum WHERE title = 'Older thread'")
	t_sql "UPDATE forum SET newpostdate = 200 WHERE id = $XSS"
	t_get /forum
	[ "$(grep -n 'Older thread' "$BODY" | cut -d: -f1)" -gt "$(grep -n '&lt;script&gt;' "$BODY" | cut -d: -f1)" ] \
		&& t_ok || t_fail "threads ordered by newpostdate"
	t_get "/forum/thread/$OLD"; TOKEN=$(t_csrf)
	t_post "/forum/reply/$OLD" "content=x"; expect_status 403
	t_post "/forum/reply/$OLD" "csrf=$TOKEN&content=+"; expect_status 200; expect_body 'Message is required.'
	t_post "/forum/reply/$OLD" "csrf=$TOKEN&content=$(t_enc 'First reply <i>')"
	expect_redirect "/forum/thread/$OLD"
	[ "$(t_sql "SELECT replies FROM forum WHERE id = $OLD")" = 1 ] && t_ok || t_fail "replies bumped"
	[ "$(t_sql "SELECT newpostdate > 200 FROM forum WHERE id = $OLD")" = 1 ] && t_ok || t_fail "newpostdate bumped"
	[ "$(t_sql "SELECT title || '|' || author FROM forum WHERE parent = $OLD")" = "Re: Older thread|Forumer" ] && t_ok || t_fail "reply row"
	t_get "/forum/thread/$OLD"; expect_body 'First reply &lt;i&gt;'
	t_get /forum
	[ "$(grep -n 'Older thread' "$BODY" | cut -d: -f1)" -lt "$(grep -n '&lt;script&gt;' "$BODY" | cut -d: -f1)" ] \
		&& t_ok || t_fail "reply moves thread to the top"
	REPLY=$(t_sql "SELECT id FROM forum WHERE parent = $OLD")
	t_post "/forum/reply/$REPLY" "csrf=$TOKEN&content=nested"; expect_status 404
	t_post "/forum/reply/999999" "csrf=$TOKEN&content=ghost"; expect_status 404
	t_get "/forum/thread/$REPLY"; expect_status 404
	t_get /forum/thread/999999;   expect_status 404
	[ "$(t_sql "SELECT count(*) FROM forum WHERE content IN ('nested', 'ghost', 'x')")" = 0 ] && t_ok || t_fail "rejected replies stored"
	[ "$(t_sql "SELECT replies FROM forum WHERE id = $REPLY")" = 0 ] && t_ok || t_fail "reply row bumped"
	# "Re: " + a 100-character title is cut to the column width, like MySQL did
	t_sql "INSERT INTO forum (postdate, newpostdate, author, parent, replies, title, content) VALUES (1, 1, 'Old', 0, 0, '$LONG', 'long')"
	LONGID=$(t_sql "SELECT id FROM forum WHERE content = 'long'")
	t_post "/forum/reply/$LONGID" "csrf=$TOKEN&content=r"
	[ "$(t_sql "SELECT length(title) FROM forum WHERE parent = $LONGID")" = 100 ] && t_ok || t_fail "reply title truncated"

	t_section "forum: paging"
	t_sql "WITH RECURSIVE c(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM c WHERE n < 25)
				 INSERT INTO forum (postdate, newpostdate, author, parent, replies, title, content)
				 SELECT 10, 10 + n, 'Bulk', 0, 0, 'Bulk thread ' || n, 'bulk' FROM c"
	t_get /forum
	[ "$(grep -c 'href="/forum/thread/' "$BODY")" = 20 ] && t_ok || t_fail "20 threads on the first page"
	expect_body 'href="/forum?start=20"'; expect_body '<b>[1]</b>'
	t_get "/forum?start=20"
	[ "$(grep -c 'href="/forum/thread/' "$BODY")" = 8 ] && t_ok || t_fail "8 threads on the second page"
	expect_body '<b>[2]</b>'; expect_body 'href="/forum">1</a>'
	t_get "/forum?start=-5";  expect_status 200; expect_body '<b>[1]</b>'
	t_get "/forum?start=abc"; expect_status 200; expect_body '<b>[1]</b>'
	t_sql "WITH RECURSIVE c(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM c WHERE n < 20)
				 INSERT INTO forum (postdate, newpostdate, author, parent, replies, title, content)
				 SELECT 10, 10, 'Bulk', $OLD, 0, 'Re: Older thread', 'bulk reply ' || n || '.' FROM c"
	t_sql "UPDATE forum SET replies = replies + 20 WHERE id = $OLD"
	t_get "/forum/thread/$OLD"
	expect_body 'bulk reply 13.'; expect_no_body 'bulk reply 14.'; expect_body "href=\"/forum/thread/$OLD?start=15\""
	t_get "/forum/thread/$OLD?start=15"
	expect_body 'bulk reply 14.'; expect_body 'bulk reply 20.'; expect_no_body 'bulk reply 13.'
	t_post "/forum/reply/$OLD" "csrf=$TOKEN&content=last+page"
	expect_redirect "/forum/thread/$OLD\\?start=15"
	[ "$(t_sql "SELECT replies FROM forum WHERE id = $OLD")" = 22 ] && t_ok || t_fail "replies counted"

	t_section "forum: guards"
	t_sql "UPDATE control SET forumtype = 0"
	t_get /forum;              expect_body 'The forum is currently disabled.'; expect_no_body 'New Thread'
	t_post /forum/new "csrf=$TOKEN&title=Off&content=off"; expect_body 'The forum is currently disabled.'
	t_get /;                   expect_no_body 'href="/forum"'
	t_sql "UPDATE control SET forumtype = 2, forumaddress = 'https://forum.example.com/'"
	t_get /forum;              expect_body 'The forum is currently disabled.'
	t_sql "UPDATE control SET forumtype = 1, forumaddress = ''"
	[ "$(t_sql "SELECT count(*) FROM forum WHERE title = 'Off'")" = 0 ] && t_ok || t_fail "post while disabled"
	t_sql "UPDATE control SET gameopen = 0"
	t_get /forum;              expect_body 'The game is currently closed'
	t_sql "UPDATE control SET gameopen = 1"
	t_sql "UPDATE users SET authlevel = 2 WHERE username = 'forumer'"
	t_get /forum;              expect_status 403; expect_body 'Your account has been blocked.'
	t_sql "UPDATE users SET authlevel = 0 WHERE username = 'forumer'"
	t_get /forum;              expect_status 200
fi

t_section "help pages (logged in)"
t_get /help/levels;        expect_status 200; expect_body 'Paladin Levels'
t_jar default
