# tests/e2e/chat.sh :: the Babble Box, live (lib/chat.lua, town/babble.lua, live.js): two
# players with event streams: a message posted with fetch (JSON) reaches the other stream,
# stays text (JSON-escaped data, escaped history), the rate limit (429), the length limit,
# blank messages, the no-JS form path, admin deletes, its page and dialog, and
# well-formed frames. Sourced by tests/run.sh (live_* and t_fetch helpers there).

chat_unlimit() { t_sql "UPDATE babble SET posttime = posttime - 10"; }

t_section "chat: its page and its window"
# the Babble Box is /babble; the Functions box's link opens it in the chat window
# (chatbox.js), which fetches it as a dialog's page (X-DK-Modal: the chat alone); no game
# page shows it otherwise
t_jar chata; t_reset_jar
t_register chata chatapw1 chata@example.com ChatA; t_login chata chatapw1
CHATA_ID=$(t_sql "SELECT id FROM users WHERE username = 'chata'")
t_get /;      expect_status 200
expect_no_body 'data-chat-form'; expect_body '<a href="/babble" data-chatbox>Babble Box</a><br>'
expect_body '<script src="/static/js/live.js" defer></script>'
expect_body 'data-live data-csrf="'; expect_no_body 'data-live-admin'
t_get /inn;   expect_status 200; expect_no_body 'data-chat-form'
expect_body 'Online: <span data-online-count>'
t_get /babble; expect_status 200; expect_body "Who's Online"
[ "$(grep -c 'data-chat-form' "$BODY")" = 1 ] && t_ok || t_fail "/babble: one chat panel"
expect_body '<section class="chat" data-r="chat" data-chat>
<h2 class="title">Babble Box</h2>'; expect_body 'name="back" value="/babble"'
t_get /babble -H 'X-DK-Modal: 1'; expect_status 200; expect_header '^X-DK-Modal: 1'
expect_body '<h2 class="dk-modal-title" id="dk-modal-title">Babble Box</h2>'
expect_body '<div class="dk-modal-content"><section class="chat" data-r="chat" data-chat>
<div class="chat-scroll">'
expect_no_body "Who's Online"; expect_no_body '<h2 class="title">Babble Box</h2>'
t_sql "UPDATE control SET showbabble = 0"
t_get /;      expect_no_body 'href="/babble" data-chatbox'
t_get /babble; expect_no_body 'data-chat-form'; expect_body 'The Babble Box is turned off.'
t_sql "UPDATE control SET showbabble = 1"
t_get /help;  expect_body 'data-live data-csrf="'          # minimal layout too: the stream lives on
t_jar chatanon; t_reset_jar
t_get /login; expect_no_body 'data-live'
if command -v node >/dev/null; then
	node --check "$ROOT/public/js/live.js" && t_ok || t_fail "live.js: syntax"
else
	echo "   (node not found: live.js syntax check skipped)"
fi

t_section "chat: a message reaches the other stream, as text"
t_jar chatb; t_reset_jar
t_register chatb chatbpw1 chatb@example.com ChatB; t_login chatb chatbpw1
t_get /
live_open b
t_jar chata
t_get /inn
XSS='<script>alert("x")</script> & </b>'
t_fetch /babble "babble=$(t_enc "$XSS")"
expect_status 200; expect_header '^content-type: application/json'
expect_body '"author":"ChatA"'; expect_body '"text":"\u003cscript\u003ealert(\"x\")\u003c/script\u003e \u0026 \u003c/b\u003e"'
CHAT_ID=$(grep -o '"id":[0-9]*' "$BODY" | cut -d: -f2)
[ "$(t_sql "SELECT author_id || '|' || babble FROM babble WHERE id = ${CHAT_ID:-0}")" = "$CHATA_ID|$XSS" ] \
	&& t_ok || t_fail "message stored raw with its author"
live_has b "event: babble"
live_has b "\"id\":$CHAT_ID,\"text\":\"\\u003cscript\\u003ealert(\\\"x\\\")\\u003c/script\\u003e \\u0026 \\u003c/b\\u003e\""
live_lacks b '<script>'
t_jar chatb
t_get /babble
expect_body "<li class=\"babble-post\" data-id=\"$CHAT_ID\""
expect_body '"><b class="babble-author">ChatA</b><span class="babble-text">&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &lt;/b&gt;</span></li>'
expect_no_body '<script>alert'
t_get "/live/state?back=/inn"; expect_status 200
expect_body '\u0026lt;script\u0026gt;alert(\u0026quot;x\u0026quot;)'; expect_no_body '<script>'

t_section "chat: rate limit, length, blank"
t_sql "UPDATE babble SET posttime = strftime('%s', 'now') WHERE id = $CHAT_ID"   # just posted
t_jar chata
t_get /inn
t_fetch /babble "babble=too+soon"
expect_status 429; expect_header '^retry-after: [12]'; expect_body '"error":"You are sending messages too fast.'
t_get /inn
t_post /babble "csrf=$(t_csrf)&babble=too+soon+again&back=/inn"   # the form (no JS)
expect_status 429; expect_body 'You are sending messages too fast.'
[ "$(t_sql "SELECT count(*) FROM babble WHERE babble LIKE 'too soon%'")" = 0 ] && t_ok || t_fail "rate-limited message stored"
sleep 2.1                                                          # the limit is per 2 seconds
t_get /inn
t_fetch /babble "babble=$(printf 'y%.0s' $(seq 1 130))"
expect_status 200
[ "$(t_sql "SELECT length(babble) FROM babble WHERE author_id = $CHATA_ID ORDER BY id DESC LIMIT 1")" = 120 ] \
	&& t_ok || t_fail "message not cut to 120 characters"
live_has b "\"text\":\"$(printf 'y%.0s' $(seq 1 120))\""
chat_unlimit
before=$(t_sql "SELECT count(*) FROM babble")
t_fetch /babble "babble=+++"; expect_status 200; expect_body '{"message":null}'
[ "$(t_sql "SELECT count(*) FROM babble")" = "$before" ] && t_ok || t_fail "blank message stored"
t_req POST /babble --data "babble=x" -H 'Accept: application/json'; expect_status 403   # no CSRF token

t_section "chat: the form without JavaScript"
chat_unlimit
t_get /inn
CC=$(t_csrf)
t_post /babble "csrf=$CC&babble=$(t_enc 'plain form post')&back=/inn"; expect_redirect /inn
t_get /babble; expect_body '<b class="babble-author">ChatA</b><span class="babble-text">plain form post</span></li>'
live_has b '"text":"plain form post"'
chat_unlimit
t_post /babble "csrf=$CC&babble=elsewhere&back=$(t_enc '//evil.example/')"; expect_redirect /babble
chat_unlimit
t_post /babble "csrf=$CC&babble=nowhere&back=/no/such/page"; expect_redirect /babble

t_section "chat: admins delete messages"
t_jar chata
t_get /inn
t_fetch "/babble/$CHAT_ID/delete"; expect_status 403
[ "$(t_sql "SELECT count(*) FROM babble WHERE id = $CHAT_ID")" = 1 ] && t_ok || t_fail "a player deleted a message"
t_jar chatadmin; t_reset_jar
t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /babble
expect_body 'data-live-admin'; expect_body "action=\"/babble/$CHAT_ID/delete\""
t_fetch "/babble/$CHAT_ID/delete"; expect_status 200; expect_body '{"deleted":true}'
live_has b $'event: delete\ndata: {"id":'"$CHAT_ID}"
[ "$(t_sql "SELECT count(*) FROM babble WHERE id = $CHAT_ID")" = 0 ] && t_ok || t_fail "message not deleted"
t_fetch "/babble/$CHAT_ID/delete"; expect_status 404
PLAIN_ID=$(t_sql "SELECT id FROM babble WHERE babble = 'plain form post'")
t_get /inn
t_post "/babble/$PLAIN_ID/delete" "csrf=$(t_csrf)&back=/inn"; expect_redirect /inn
live_has b "data: {\"id\":$PLAIN_ID}"
t_get /babble; expect_no_body 'plain form post'
t_jar chatb
t_get /babble; expect_no_body "class=\"babble-post\" data-id=\"$CHAT_ID\""; expect_no_body 'chat-delete'

t_section "chat: well-formed frames"
live_stop
live_frames_ok b
t_jar default
