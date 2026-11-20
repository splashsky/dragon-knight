# tests/e2e/live_wire.sh :: live requests (docs/APP.md "Live client", app/lib/wire.lua,
# app/main.lua): the same routes answering in the wire format with the regions the client
# lacks; a live answer rebuilds exactly the page a full load shows; redirects followed on
# the server (login, logout, a move into a fight); go for other sites and changed scripts;
# doc for pages outside the layouts; errors, CSRF, HEAD, Vary. Sourced by tests/run.sh.
if ! command -v python3 >/dev/null; then
	t_section "live wire (skipped: needs python3)"
else

# the body of the last full page / of the live answer's root region, with the footer's
# timing (different on every request) blanked
lw_norm() { sed -E 's/[0-9.]+ Seconds, [0-9]+ Queries/T Seconds, Q Queries/'; }
lw_page_body() { sed -n '/^<body/,/<\/body>$/p' "$BODY" | lw_norm; }
lw_root() { { w_payload region root; echo; } | lw_norm; }
# GET PATH both ways: the live answer without any hashes is the page's whole body
lw_same() {
	local full
	t_get "$1"; expect_status "${2:-200}"; full=$(lw_page_body)
	[ -n "$full" ] || t_fail "$1: no <body> in the page"
	t_live_forget; t_live GET "$1"; expect_status "${2:-200}"
	expect_header '^content-type: application/x-dk-live'
	if [ "$(lw_root)" = "$full" ]; then t_ok; else t_fail "$1: live root differs from the page: $(diff <(echo "$full") <(lw_root) | head -4 | tr '\n' ' ')"; fi
}

t_section "live wire: a page and its live answer"
t_jar livewire; t_reset_jar
t_get /login; expect_header '^vary: X-DK-Live'
expect_body '<html lang="en" data-h="head='
grep -q $'\x01' "$BODY" && t_fail "region markers left in the page" || t_ok
lw_same /login
lw_same /help
lw_same /no/such/page 404
t_register lwuser lwpass1 lw@example.com Lwuser 2
t_login lwuser lwpass1
LQ="WHERE username = 'lwuser'"
for p in / /inn /shop /inventory /maps /babble /online /news /forum /character /changelog; do lw_same "$p"; done
w_has title; w_has url; w_has hashes; w_has region root
[ "$(w_payload url)" = /changelog ] && t_ok || t_fail "url: $(w_payload url)"

t_section "live wire: only what changed"
t_get /; t_live_page
t_live GET /; expect_status 200
# the page as the client has it: nothing but the footer's timing
# (the footer's timing, unless it came out the same)
[ -z "$(w_ops | grep '^region' | grep -v '^region foot ')" ] && t_ok || t_fail "unchanged page sent: $(w_ops | tr '\n' ';')"
[ "$(w_payload title)" = "In Town" ] && t_ok || t_fail "title: $(w_payload title)"
# a change in the gold: the Character panel
t_sql "UPDATE users SET gold = gold + 7 $LQ"
t_live GET /
w_has region charpanel; w_lacks region right; w_lacks region main; w_lacks region invpanel
w_payload region charpanel | grep -q '<section class="box" data-r="charpanel">' && t_ok || t_fail "charpanel payload"
w_payload hashes | grep -qE '^charpanel=[0-9a-f]+( foot=[0-9a-f]+)?$' && t_ok \
	|| t_fail "hashes: only what changed: $(w_payload hashes)"
# another page: its middle column, the chat moves from the middle to the right column
t_live GET /inn
w_has region main; w_has region right; w_lacks region left; w_lacks region root
[ "$(w_payload url)" = /inn ] && t_ok || t_fail "url /inn"
# unknown hashes: the whole body
echo "root=000000000000" > "$JAR.have"
t_live GET /inn; w_has region root

t_section "live wire: a move (a POST and its redirect, one round trip)"
t_get /; t_live_page; LW_CS=$(t_csrf)
t_sql "UPDATE users SET currentaction = 'Exploring', latitude = 30, longitude = 30, currenthp = 100000, base_maxhp = 100000 $LQ"
t_live GET /
for _ in $(seq 1 30); do
	t_live POST /move "csrf=$LW_CS&north=North"
	[ "$(w_payload url)" = / ] && break
	t_fight_clear lwuser; t_sql "UPDATE users SET currentaction = 'Exploring' $LQ"; t_live GET /
done
expect_status 200; [ "$(w_payload url)" = / ] && t_ok || t_fail "move: url $(w_payload url)"
w_has region loc; w_lacks region towns; w_lacks region main; w_lacks region right
w_payload region loc | grep -q 'Latitude: ' && t_ok || t_fail "loc payload"
# an encounter: the move lands on the fight page, the monster's first strike included
t_fight_clear lwuser; t_sql "UPDATE users SET currentaction = 'Exploring' $LQ"; t_live GET /
for _ in $(seq 1 60); do
	t_live POST /move "csrf=$LW_CS&north=North"
	[ "$(w_payload url)" = /fight ] && break
done
[ "$(w_payload url)" = /fight ] && t_ok || t_fail "no encounter in 60 moves"
[ "$(w_payload title)" = Fighting ] && t_ok || t_fail "title: $(w_payload title)"
w_payload region main | grep -q 'You are fighting a' && t_ok || t_fail "fight page in main"
t_fight_clear lwuser; t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 $LQ"

t_section "live wire: errors, CSRF, other answers"
t_get /; t_live_page
t_live POST /inn "csrf=nope&submit=Yes"; expect_status 403
w_payload region main | grep -q 'Your form has expired' && t_ok || t_fail "CSRF page in main"
t_live GET /no/such/page; expect_status 404; w_has region main
t_live GET /ninja; expect_status 200
[ "$(w_ops | cut -d" " -f1)" = go ] && [ "$(w_payload go)" = http://www.se7enet.com/img/shirtninja.jpg ] && t_ok || t_fail "external redirect: $(w_ops)"
t_live GET /__test/boom; expect_status 500; w_has doc
w_payload doc | grep -q '<title>Internal Server Error</title>' && t_ok || t_fail "500 page as doc"
t_live GET /__test/routes; expect_status 200; expect_header '^content-type: text/plain'   # not HTML: as is
t_req HEAD / -H 'X-DK-Live: 1' -I; expect_header '^content-type: text/html'                # HEAD is never live
# other scripts or stylesheets (a theme, a deploy): load the page normally
t_get /; t_live_page; sed -i 's/head=[0-9a-f]*/head=000000000000/' "$JAR.have"
t_live GET /inn; [ "$(w_ops)" = "go 4" ] && [ "$(w_payload go)" = /inn ] && t_ok || t_fail "changed head: $(w_ops)"

t_section "live wire: logging in and out"
t_jar livewire2; t_reset_jar
t_get /login; t_live_page
t_live POST /login "csrf=$(t_csrf)&username=lwuser&password=lwpass1"; expect_status 200
expect_header '^set-cookie: dk_session='
[ "$(w_payload url)" = / ] && [ "$(w_payload title)" = "In Town" ] && t_ok || t_fail "login lands in town: $(w_ops | tr '\n' ';')"
w_has region root
w_payload region root | grep -q 'data-live data-csrf=' && t_ok || t_fail "logged-in body"
LW_TOKEN=$(w_payload region root | grep -o 'name="csrf" value="[0-9a-f]*"' | head -n1 | cut -d'"' -f4)
t_live GET /inventory; expect_status 200; w_lacks region root   # the new session's cookie works
t_live POST /logout "csrf=$LW_TOKEN"
[ "$(w_payload url)" = /login ] && t_ok || t_fail "logout lands on /login: $(w_ops | tr '\n' ';')"
expect_header '^set-cookie: dk_session=;'
t_get /; expect_redirect /login

fi
