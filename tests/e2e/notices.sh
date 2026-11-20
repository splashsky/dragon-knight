# tests/e2e/notices.sh :: live notices and the broadcast banner (lib/notices.lua,
# lib/banner.lua, admin/broadcast.lua) and the logout event: a news post reaches every
# stream, a forum reply only the streams of the players who started or posted in the
# thread (not the one replying); the banner set and cleared live, on every page load
# (escaped, logged out too), dismissed per browser, expiring; logout and password changes
# close the right pages' streams. Sourced by tests/run.sh (live_* helpers there).

notice_player() {  # notice_player USER CHARNAME: register, log in, load a page (own jar)
	t_jar "$1"; t_reset_jar
	t_register "$1" "${1}pw1" "$1@example.com" "$2"; t_login "$1" "${1}pw1"
	t_get /inn
}

t_section "notices: forum replies"
t_sql "UPDATE control SET forumtype = 1"
notice_player nstart NStart; live_open start
notice_player nposter NPoster; live_open poster
notice_player nother NOther; live_open other
notice_player nreply NReply; live_open reply
t_jar nstart
t_get /forum/1/new
t_post /forum/1/new "csrf=$(t_csrf)&title=$(t_enc 'Notice <me> thread')&content=first"; expect_redirect /forum/1
NTHREAD=$(t_sql "SELECT id FROM forum WHERE title = 'Notice <me> thread'")
t_jar nposter
t_get "/forum/thread/$NTHREAD"
t_post "/forum/reply/$NTHREAD" "csrf=$(t_csrf)&content=second"; expect_redirect "/forum/thread/$NTHREAD"
live_has start $'event: reply\ndata: {"author":"NPoster","thread":'"$NTHREAD"',"title":"Notice \\u003cme\\u003e thread","url":"/forum/thread/'"$NTHREAD"'"}'
live_lacks poster 'event: reply'
t_jar nreply
t_get "/forum/thread/$NTHREAD"
t_post "/forum/reply/$NTHREAD" "csrf=$(t_csrf)&content=third"; expect_redirect "/forum/thread/$NTHREAD"
live_has poster '"author":"NReply"'
live_has start '"author":"NReply"'
live_lacks reply 'event: reply'
live_lacks other 'event: reply'
t_post "/forum/reply/$NTHREAD" "content=no+csrf"; expect_status 403

t_section "notices: news"
t_jar nadmin; t_reset_jar
t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin/news
t_post /admin/news "csrf=$(t_csrf)&title=$(t_enc 'Live <news>')&content=$(t_enc 'Read all about it.')"
expect_redirect '/admin/news\?saved=1'
NEWS_ID=$(t_sql "SELECT max(id) FROM news")
for s in start poster other reply; do
	live_has $s $'event: news\ndata: {"author":"Admin","id":'"$NEWS_ID"',"title":"Live \\u003cnews\\u003e","url":"/news/'"$NEWS_ID"'"}'
done
t_get /admin/news
t_post /admin/news "csrf=$(t_csrf)&title=&content="; expect_body 'Content is required.'
[ "$(live_count other 'event: news')" = 1 ] && t_ok || t_fail "a refused news post was announced"

t_section "notices: the broadcast banner"
t_get /admin/broadcast; expect_status 200; expect_body 'Current banner:'; expect_body 'none'
BC_CSRF=$(t_csrf)
t_post /admin/broadcast "csrf=$BC_CSRF&text=&minutes=&set=1"; expect_body 'Text is required.'
t_post /admin/broadcast "csrf=$BC_CSRF&text=x&minutes=soon&set=1"; expect_body 'Expires must be a number of minutes'
t_post /admin/broadcast "csrf=$BC_CSRF&text=$(printf 'z%.0s' $(seq 1 201))&set=1"; expect_body 'Text must be 200 characters or less.'
t_post /admin/broadcast "text=x&set=1"; expect_status 403
[ "$(t_sql "SELECT banner FROM control")" = "" ] && t_ok || t_fail "a refused banner was stored"
t_post /admin/broadcast "csrf=$BC_CSRF&text=$(t_enc 'Restart at <b>noon</b> & then')&minutes=&set=1"
expect_redirect '/admin/broadcast\?saved=set'
BANNER_ID=$(t_sql "SELECT banner_id FROM control")
for s in start other; do
	live_has $s $'event: banner\ndata: {"id":'"$BANNER_ID"',"text":"Restart at \\u003cb\\u003enoon\\u003c/b\\u003e \\u0026 then"}'
done
t_get /admin/broadcast; expect_body '<span class="admin-banner-current">Restart at &lt;b&gt;noon&lt;/b&gt; &amp; then</span>'
expect_body 'name="clear"'
for j in nother nadmin; do
	t_jar $j; t_get /inn
	expect_body "<div class=\"dk-banner\" role=\"status\" data-banner=\"$BANNER_ID\">"
	expect_body 'Restart at &lt;b&gt;noon&lt;/b&gt; &amp; then'; expect_no_body '<b>noon'
done
t_jar nbanneranon; t_reset_jar
t_get /login;  expect_body 'Restart at &lt;b&gt;noon&lt;/b&gt; &amp; then'
t_get /help;   expect_body 'Restart at &lt;b&gt;noon&lt;/b&gt; &amp; then'
# dismissed in one browser (no JS: the form; live.js sets the same cookie itself)
t_jar nother
t_get /inn
t_post /banner/dismiss "csrf=$(t_csrf)&id=$BANNER_ID&back=/inn"; expect_redirect /inn
expect_header "^set-cookie: dk_banner=$BANNER_ID; Path=/; Max-Age=2592000; SameSite=Lax"
t_get /inn;    expect_no_body 'class="dk-banner" role="status" data-banner='
t_jar nreply;  t_get /inn; expect_body 'class="dk-banner" role="status" data-banner='
t_get "/live/state?back=/inn"; expect_body '"banner":"\n\u003cdiv class=\"dk-banner\"'
# a new banner shows again where the old one was dismissed; with an expiry
t_jar nadmin
t_get /admin/broadcast
t_post /admin/broadcast "csrf=$(t_csrf)&text=Short+one&minutes=5&set=1"
BANNER_ID2=$(t_sql "SELECT banner_id FROM control")
[ "$BANNER_ID2" = $((BANNER_ID + 1)) ] && t_ok || t_fail "banner id not increased"
live_has other "data: {\"expires\":"
live_has other "\"id\":$BANNER_ID2,\"text\":\"Short one\",\"ttl\":300}"
t_jar nother;  t_get /inn
grep -qE "data-banner=\"$BANNER_ID2\" data-banner-ttl=\"(300|29[0-9])\"" "$BODY" && t_ok || t_fail "banner ttl"
expect_body 'Short one'
t_sql "UPDATE control SET banner_expires = strftime('%s', 'now') - 1"
t_get /inn;    expect_no_body 'Short one'
t_jar nadmin
t_get /admin/broadcast; expect_body '<span class="light">none</span>'
t_post /admin/broadcast "csrf=$(t_csrf)&text=Clear+me&set=1"
t_get /admin/broadcast
t_post /admin/broadcast "csrf=$(t_csrf)&clear=1"; expect_redirect '/admin/broadcast\?saved=cleared'
BANNER_ID3=$(t_sql "SELECT banner_id FROM control")
live_has start $'event: clear\ndata: {"id":'"$BANNER_ID3"'}'
t_jar nreply;  t_get /inn; expect_no_body 'Clear me'; expect_no_body 'class="dk-banner" role="status" data-banner='
[ "$(t_sql "SELECT banner || '|' || banner_expires FROM control")" = "|0" ] && t_ok || t_fail "banner not cleared"

t_section "notices: logout closes the session's pages"
t_jar nstart;  t_get /inn
SID1=$(grep -o 'data-live-session="[0-9a-f]*"' "$BODY" | cut -d'"' -f2)
t_jar nstart2; t_reset_jar
t_login nstart nstartpw1; t_get /inn
SID2=$(grep -o 'data-live-session="[0-9a-f]*"' "$BODY" | cut -d'"' -f2)
[ -n "$SID1" ] && [ "$SID1" != "$SID2" ] && t_ok || t_fail "session ids: '$SID1' '$SID2'"
live_open start2
t_jar nstart; t_logout; expect_redirect /login
live_has start "event: logout"$'\n'"data: {\"session\":\"$SID1\"}"
live_has start2 "data: {\"session\":\"$SID1\"}"   # the other session's pages ignore it
live_lacks other 'event: logout'
t_jar nstart2
t_get /changepassword
t_post /changepassword "csrf=$(t_csrf)&username=nstart&oldpass=nstartpw1&newpass1=nstartpw2&newpass2=nstartpw2"
expect_body 'Your password was changed successfully.'
live_has start2 'data: {"all":true}'
live_lacks other 'event: logout'
live_stop
for s in start poster other reply start2; do live_frames_ok $s; done
t_jar default
