#!/usr/bin/env bash
# tests/run.sh :: end-to-end smoke tests (bash + curl against a temporary server).
#
#   BIN=./dk tests/run.sh            (make test runs this)
#   tests/run.sh -k                  keep the temp dir (prints its path)
#
# Builds nothing. Creates a temp dir with a COPY of app/ templates/ public/, a config
# (port 0 = random free port, low pbkdf2_iterations, temp db + outbox), runs
# `dk install --admin ...`, starts `dk serve`, runs the core checks below and then
# sources every tests/e2e/*.sh (sorted); feature tests go there.
# See docs/APP.md "End-to-end tests" for the helper API.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=${BIN:-./dk}
case $BIN in /*) ;; *) BIN="$ROOT/${BIN#./}" ;; esac
KEEP=0
[ "${1:-}" = "-k" ] && KEEP=1

command -v curl >/dev/null || { echo "run.sh: curl is required" >&2; exit 1; }
[ -x "$BIN" ] || { echo "run.sh: $BIN not found (build with make)" >&2; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/dk-e2e.XXXXXX")
SERVER_PID=
cleanup() {
	[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
	if [ "$KEEP" = 1 ]; then echo "kept $T"; else rm -rf "$T"; fi
}
trap cleanup EXIT

cp -r "$ROOT/app" "$ROOT/templates" "$ROOT/public" "$T/"
cat > "$T/config.lua" <<EOF
return {
	bind = "127.0.0.1",
	port = 0,
	workers = 2,
	db_path = "$T/dk.db",
	app_dir = "$T/app",
	template_dir = "$T/templates",
	public_dir = "$T/public",
	outbox_dir = "$T/outbox",
	secret = "e2e-test-secret",
	dev = true,
	pbkdf2_iterations = 1000,
}
EOF
CONFIG="$T/config.lua"
OUTBOX="$T/outbox"

# ---------------------------------------------------------------------------------
# helpers (available to tests/e2e/*.sh)

PASS=0
FAILS=0
SECTION=
STATUS=
BODY="$T/body"
HEADERS="$T/headers"
JAR="$T/jar.default"

t_section() { SECTION=$1; echo "== $1"; }
t_ok() { PASS=$((PASS + 1)); }
t_fail() {
	FAILS=$((FAILS + 1))
	echo "FAIL [$SECTION] $*" >&2
	echo "  last request: $LAST_REQ -> $STATUS" >&2
	head -c 600 "$BODY" | sed 's/^/  | /' >&2
	echo >&2
}

# Switch cookie jar (one per simulated browser). t_jar alice; t_jar default
t_jar() { JAR="$T/jar.$1"; }
t_reset_jar() { rm -f "$JAR"; }

# t_req METHOD PATH [extra curl args...] -> sets STATUS, $BODY, $HEADERS
t_req() {
	local method=$1 path=$2
	shift 2
	LAST_REQ="$method $path"
	STATUS=$(curl -s -X "$method" -o "$BODY" -D "$HEADERS" -w '%{http_code}' \
		-b "$JAR" -c "$JAR" "$@" "$BASE$path")
}
t_get() { local p=$1; shift; t_req GET "$p" "$@"; }
# HEAD request (curl -I); $BODY gets the headers too
t_head() {
	LAST_REQ="HEAD $1"
	STATUS=$(curl -s -I -o "$BODY" -D "$HEADERS" -w '%{http_code}' -b "$JAR" -c "$JAR" "$BASE$1")
}
# t_post PATH 'a=1&b=2' (urlencoded as given; use t_enc for values)
t_post() { local p=$1 d=${2:-}; shift; [ $# -gt 0 ] && shift; t_req POST "$p" --data "$d" "$@"; }
# urlencode one value
t_enc() {
	local s=$1 out= c i
	for ((i = 0; i < ${#s}; i++)); do
		c=${s:i:1}
		case $c in [a-zA-Z0-9._~-]) out+=$c ;; *) out+=$(printf '%%%02X' "'$c") ;; esac
	done
	printf '%s' "$out"
}
# Text in expect_body is matched against the raw HTML: escape ' as &#39;, & as &amp; etc.
# CSRF token from the last response body
t_csrf() { grep -o 'name="csrf" value="[0-9a-f]*"' "$BODY" | head -n1 | cut -d'"' -f4; }

expect_status() { if [ "$STATUS" = "$1" ]; then t_ok; else t_fail "expected status $1, got $STATUS"; fi; }
expect_body() { if grep -qF -- "$1" "$BODY"; then t_ok; else t_fail "body lacks: $1"; fi; }
expect_no_body() { if grep -qF -- "$1" "$BODY"; then t_fail "body unexpectedly has: $1"; else t_ok; fi; }
expect_header() { if grep -qiE -- "$1" "$HEADERS"; then t_ok; else t_fail "no header matching: $1"; fi; }
expect_redirect() {
	if [ "$STATUS" = 302 ] && grep -qiE "^location: $1"$'\r'"?$" "$HEADERS"; then t_ok
	else t_fail "expected 302 to $1 (status $STATUS, $(grep -i '^location' "$HEADERS" | tr -d '\r'))"; fi
}

# Text inputs and selected <option>s of the form in $BODY, as name=value lines.
t_form_fields() {
	grep -o '<input type="text" name="[^"]*"[^>]*value="[^"]*"' "$BODY" |
		sed 's/^<input type="text" name="\([^"]*\)".*value="\([^"]*\)"$/\1=\2/'
	awk '/<select name="/ { match($0, /name="[^"]*"/); n = substr($0, RSTART + 6, RLENGTH - 7) }
			 /<option value="[^"]*" selected>/ { match($0, /value="[^"]*"/); print n "=" substr($0, RSTART + 7, RLENGTH - 8) }' "$BODY"
}
t_unhtml() {
	local s=$1
	s=${s//&lt;/<}; s=${s//&gt;/>}; s=${s//&quot;/\"}; s=${s//&#39;/\'}; s=${s//&amp;/&}
	printf '%s' "$s"
}
# t_form_submit PATH [name=value ...]: POST the form currently in $BODY (text inputs and
# selects, plus csrf and submit=Submit) back to PATH with the given fields overridden; names
# not in the form are appended.
t_form_submit() {
	local path=$1 data k v o found fields
	shift
	fields=$(t_form_fields)
	data="csrf=$(t_csrf)&submit=Submit"
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		k=${line%%=*}; v=$(t_unhtml "${line#*=}")
		for o in "$@"; do [ "${o%%=*}" = "$k" ] && v=${o#*=}; done
		data+="&$k=$(t_enc "$v")"
	done <<< "$fields"
	for o in "$@"; do
		k=${o%%=*}; found=0
		while IFS= read -r line; do [ "${line%%=*}" = "$k" ] && found=1; done <<< "$fields"
		[ $found = 0 ] && data+="&$k=$(t_enc "${o#*=}")"
	done
	t_post "$path" "$data"
}
# Run SQL against the test database (sqlite3 CLI or python3). Prints rows '|'-separated.
t_sql() { t_sql_db "$T/dk.db" "$1"; }
# Same against another database file: t_sql_db DB "SQL"
t_sql_db() {
	if command -v sqlite3 >/dev/null; then
		sqlite3 "$1" "$2"
	else
		python3 - "$1" "$2" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
for row in con.execute(sys.argv[2]):
		print("|".join("" if v is None else str(v) for v in row))
con.commit()
PY
	fi
}
# Run an SQL file against a database: t_sql_script DB FILE
t_sql_script() {
	if command -v sqlite3 >/dev/null; then
		sqlite3 "$1" < "$2"
	else
		python3 - "$1" "$2" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.executescript(open(sys.argv[2]).read())
con.commit()
PY
	fi
}
t_has_sql() { command -v sqlite3 >/dev/null || command -v python3 >/dev/null; }

# Newest outbox mail (path), and its count.
t_mail_latest() { ls -t "$OUTBOX"/*.eml 2>/dev/null | head -n1; }
t_mail_count() { ls "$OUTBOX"/*.eml 2>/dev/null | wc -l; }

# t_register USER PASS EMAIL CHARNAME [CLASS] [DIFFICULTY]  (current jar)
t_register() {
	t_get /register
	t_post /register "csrf=$(t_csrf)&username=$1&password1=$(t_enc "$2")&password2=$(t_enc "$2")&email1=$(t_enc "$3")&email2=$(t_enc "$3")&charname=$4&charclass=${5:-1}&difficulty=${6:-1}"
}
# t_login USER PASS [rememberme]  (current jar; expects success)
t_login() {
	t_get /login
	t_post /login "csrf=$(t_csrf)&username=$1&password=$(t_enc "$2")${3:+&rememberme=yes}"
}
# t_logout (current jar)
t_logout() { t_get /changepassword; t_post /logout "csrf=$(t_csrf)"; }

# Wait (max ~5 s) until GET PATH contains TEXT; for hot-reload checks.
t_wait_for() {
	local i
	for i in $(seq 1 50); do
		t_get "$1"
		grep -qF -- "$2" "$BODY" && return 0
		sleep 0.1
	done
	return 1
}

# ---------------------------------------------------------------------------------
# install + serve

ADMIN_USER=admin
ADMIN_PASS=adminpass1
ADMIN_EMAIL=admin@example.com
if ! "$BIN" install --config "$CONFIG" --admin "$ADMIN_USER" "$ADMIN_EMAIL" "$ADMIN_PASS" \
		--charname Admin >"$T/install.log" 2>&1; then
	echo "run.sh: install failed" >&2; cat "$T/install.log" >&2; exit 1
fi

"$BIN" serve --config "$CONFIG" >"$T/server.log" 2>&1 &
SERVER_PID=$!
PORT=
for _ in $(seq 1 100); do
	PORT=$(sed -n 's/.*http: listening on [^ ]*:\([0-9][0-9]*\)$/\1/p' "$T/server.log" | head -n1)
	[ -n "$PORT" ] && break
	kill -0 "$SERVER_PID" 2>/dev/null || break
	sleep 0.05
done
if [ -z "$PORT" ]; then echo "run.sh: server did not start" >&2; cat "$T/server.log" >&2; exit 1; fi
BASE="http://127.0.0.1:$PORT"
echo "e2e: server on $BASE (dir $T)"

# ---------------------------------------------------------------------------------
# core checks: install, accounts, sessions, CSRF, home, static, errors, HEAD, hot reload

t_section "install"
grep -qF "Administrator 'admin' created" "$T/install.log" && t_ok || t_fail "install output"
if t_has_sql; then
	[ "$(t_sql 'SELECT count(*) FROM levels')" = 100 ] && t_ok || t_fail "levels seeded"
	[ "$(t_sql 'SELECT count(*) FROM monsters')" = 151 ] && t_ok || t_fail "monsters seeded"
	[ "$(t_sql 'SELECT verifyemail FROM control')" = 0 ] && t_ok || t_fail "verifyemail default 0"
fi
"$BIN" install --config "$CONFIG" --admin x x@example.com y >/dev/null 2>&1 \
	&& t_fail "second install must refuse" || t_ok

# Lua unit tests (tests/lua/test_*.lua): run inside a dk VM by installing runner.lua as
# cli/user.lua in a scratch copy of app/ (so `dk user` executes it).
t_section "lua unit tests"
mkdir -p "$T/unit"
cp -r "$T/app" "$T/unit/app"
mkdir -p "$T/unit/app/tests"
cp "$ROOT"/tests/lua/*.lua "$T/unit/app/tests/"
cp "$ROOT/tests/lua/runner.lua" "$T/unit/app/cli/user.lua"
sed "s#app_dir = \"$T/app\"#app_dir = \"$T/unit/app\"#" "$CONFIG" > "$T/unit/config.lua"
UNIT_MODS=$(cd "$ROOT/tests/lua" && ls test_*.lua | sed 's/^/tests./; s/\.lua$//')
# shellcheck disable=SC2086
if "$BIN" user --config "$T/unit/config.lua" $UNIT_MODS >"$T/unit.log" 2>&1; then
	t_ok; tail -n1 "$T/unit.log"
else
	t_fail "lua unit tests"; cat "$T/unit.log" >&2
fi

t_section "public pages, static, errors"
t_get /login;            expect_status 200; expect_body 'name="username"'; expect_header '^set-cookie: dk_csrf='
t_get /;                 expect_redirect /login
t_get /static/images/logo.gif; expect_status 200
t_get /static/css/dk.css;      expect_status 200; expect_body 'dk-page'
t_get /no/such/page;     expect_status 404
t_get /logout;           expect_status 405; expect_header '^allow: POST'

t_section "csrf"
t_get /login
t_post /login "username=admin&password=$ADMIN_PASS";                expect_status 403
t_post /login "csrf=$(printf '0%.0s' $(seq 64))&username=admin&password=$ADMIN_PASS"; expect_status 403
t_jar other; t_get /login; OTHER_TOKEN=$(t_csrf); t_jar default
t_post /login "csrf=$OTHER_TOKEN&username=admin&password=$ADMIN_PASS"; expect_status 403

t_section "register + login"
t_jar alice
t_register alice secretpw alice@example.com Alice 2 1
expect_status 200; expect_body 'Your account was created succesfully'
t_register alice secretpw alice@example.com Alice
expect_body 'Username already taken'; expect_body 'Email already taken'
t_get /register
t_post /register "csrf=$(t_csrf)&username=bad+name&password1=a&password2=b&email1=x&email2=y&charname=Bad&charclass=1&difficulty=9"
expect_body 'Username must be alphanumeric.'; expect_body 'Email isn&#39;t valid.'; expect_body 'Emails don&#39;t match.'
expect_body 'Passwords don&#39;t match.'; expect_body 'Difficulty is invalid.'; expect_body 'value="bad name"'
t_login alice wrongpw;   expect_status 200; expect_body 'Invalid username or password'
t_login alice secretpw;  expect_redirect /; expect_header '^set-cookie: dk_session=[0-9a-f]{64}; Path=/; HttpOnly; SameSite=Lax'
t_get /;                 expect_status 200; expect_body 'Welcome to Midworld'; expect_body 'Town Options'
expect_body 'Latest News'; expect_body "Who's Online"; expect_body '>Alice</a>'; expect_body 'src="/babble"'
expect_body 'action="/move"'; expect_body 'Seconds,'
t_post /logout "";       expect_status 403
t_get /;                 expect_status 200
if t_has_sql; then
	[ "$(t_sql "SELECT charclass||','||difficulty FROM users WHERE username='alice'")" = 2,1 ] && t_ok || t_fail "class/difficulty stored"
	t_sql "UPDATE users SET currentaction='Exploring' WHERE username='alice'"
	t_get /; expect_body 'You are exploring the map'
	t_sql "UPDATE users SET currentaction='Fighting' WHERE username='alice'"
	t_get /; expect_redirect /fight
	t_sql "UPDATE users SET currentaction='In Town' WHERE username='alice'"
fi
t_logout;                expect_redirect /login
t_get /;                 expect_redirect /login

t_section "remember me"
t_jar remember
t_login alice secretpw yes; expect_header '^set-cookie: dk_session=[0-9a-f]{64}; Path=/; Max-Age=31536000'

t_section "change password"
t_jar alice
t_login alice secretpw; t_get /
t_get /changepassword;   expect_status 200
t_post /changepassword "csrf=$(t_csrf)&username=alice&oldpass=nope&newpass1=a&newpass2=a"
expect_body 'The old password you provided was incorrect.'
t_post /changepassword "csrf=$(t_csrf)&username=alice&oldpass=secretpw&newpass1=newpw1&newpass2=newpw2"
expect_body 'New passwords don&#39;t match.'
t_post /changepassword "csrf=$(t_csrf)&username=alice&oldpass=secretpw&newpass1=newpw1&newpass2=newpw1"
expect_body 'Your password was changed successfully.'
t_get /;                 expect_redirect /login
t_jar remember; t_get /; expect_redirect /login   # other sessions ended too
t_jar alice
t_login alice secretpw;  expect_body 'Invalid username or password'
t_login alice newpw1;    expect_redirect /

t_section "lost password"
t_jar lost
t_get /lostpassword
t_post /lostpassword "csrf=$(t_csrf)&email=$(t_enc nobody@example.com)"; expect_body 'No account with that email address.'
before=$(t_mail_count)
t_post /lostpassword "csrf=$(t_csrf)&email=$(t_enc ALICE@example.com)"; expect_body 'Your new password was emailed'
[ "$(t_mail_count)" -gt "$before" ] && t_ok || t_fail "no mail written to $OUTBOX"
MAIL=$(t_mail_latest)
NEWPW=$(sed -n 's/^Your new password is: \([A-Z]\{8\}\).*/\1/p' "$MAIL" | tr -d '\r')
grep -q '^To: alice@example.com' "$MAIL" && t_ok || t_fail "mail To header"
[ -n "$NEWPW" ] && t_ok || t_fail "no password in mail"
t_login alice "$NEWPW";  expect_redirect /

if t_has_sql; then
	t_section "email verification"
	t_sql "UPDATE control SET verifyemail = 1"
	t_jar bob
	t_get /register;         expect_body 'A verification code will be sent'
	t_register bob bobpw bob@example.com Bob
	expect_body 'You should receive an Account Verification email'
	CODE=$(sed -n 's/^Verification code: \([A-Z]\{8\}\).*/\1/p' "$(t_mail_latest)" | tr -d '\r')
	[ -n "$CODE" ] && t_ok || t_fail "no verification code mailed"
	t_login bob bobpw;       expect_redirect /
	t_get /;                 expect_redirect /verify
	t_get /verify
	t_post /verify "csrf=$(t_csrf)&username=bob&email=$(t_enc bob@example.com)&verify=WRONGXXX"
	expect_body 'Incorrect verification code.'
	t_post /verify "csrf=$(t_csrf)&username=bob&email=$(t_enc bob@example.com)&verify=$CODE"
	expect_body 'Your account was verified successfully.'
	t_get /;                 expect_status 200; expect_body 'Welcome to Midworld'
	t_sql "UPDATE control SET verifyemail = 0"

	t_section "guards"
	t_sql "UPDATE control SET gameopen = 0"
	t_get /;                 expect_body 'The game is currently closed'
	t_sql "UPDATE control SET gameopen = 1"
	t_sql "UPDATE users SET authlevel = 2 WHERE username = 'bob'"
	t_get /;                 expect_status 403; expect_body 'Your account has been blocked.'
	t_sql "UPDATE users SET authlevel = 0 WHERE username = 'bob'"
	t_jar admin
	t_login admin "$ADMIN_PASS"; t_get /; expect_body 'href="/admin"'

	t_section "HEAD is read-only"
	# GET /fight and GET /victory change state by design; HEAD runs the same handler but
	# main.lua rolls its writes back.
	t_jar headuser
	t_register headuser headpw head@example.com Header; t_login headuser headpw
	head_snap() {
		t_sql "SELECT currentaction, currentfight, currentmonster, currentmonsterhp, currenthp,
					 experience, gold, level, dropcode, onlinetime FROM users WHERE username = 'headuser'"
	}
	t_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 1, currentmonster = 0,
				 currentmonsterhp = 0, onlinetime = 1 WHERE username = 'headuser'"
	before=$(head_snap)
	t_head /fight;   expect_status 200; expect_header '^content-length: [1-9]'
	[ "$(head_snap)" = "$before" ] && t_ok || t_fail "HEAD /fight changed the user: $before -> $(head_snap)"
	t_sql "UPDATE users SET currentfight = 3, currentmonster = 1, currentmonsterhp = 0
				 WHERE username = 'headuser'"
	before=$(head_snap)
	t_head /victory; expect_status 200
	[ "$(head_snap)" = "$before" ] && t_ok || t_fail "HEAD /victory changed the user: $before -> $(head_snap)"
	t_get /victory;  expect_status 200; expect_body 'You have defeated the Blue Slime'
	[ "$(t_sql "SELECT currentfight || ',' || (experience > 0) FROM users WHERE username = 'headuser'")" = "0,1" ] \
		&& t_ok || t_fail "GET /victory (control) did not pay out"
	t_head /victory; expect_redirect /
fi

t_section "hot reload"
t_jar default
echo '<p id="hot-reload-marker">reloaded template</p>' >> "$T/templates/auth/login.html"
t_wait_for /login 'hot-reload-marker' && t_ok || t_fail "template change not picked up"
sed -i 's/view.BUILD = "C\/Lua"/view.BUILD = "C\/Lua hot-reloaded"/' "$T/app/lib/view.lua"
t_wait_for /login 'C/Lua hot-reloaded' && t_ok || t_fail "Lua change not picked up"

t_section "errors roll back"
# test-only route added to the temp copy of routes/home.lua
sed -i 's#^\([[:space:]]*\)r:get("/", auth.game, home)#\1r:get("/__test/boom", function() dk.db:exec("UPDATE control SET gamename = ?", "BOOM"); error("intentional test error") end)\n&#' \
	"$T/app/routes/home.lua"
t_wait_for /__test/boom 'intentional test error' && t_ok || t_fail "test route not loaded"
expect_status 500
if t_has_sql; then
	[ "$(t_sql 'SELECT gamename FROM control')" = "Dragon Knight" ] && t_ok || t_fail "write before error was not rolled back"
fi

t_section "hot reload: new files, template errors, config"
# a module and a template in directories created after startup, used by a new route
mkdir -p "$T/app/hotdir" "$T/templates/hotdir"
echo 'return { who = function() return "new-module" end }' > "$T/app/hotdir/mod.lua"
echo '<p>hot {{ who }}</p>' > "$T/templates/hotdir/page.html"
sed -i 's#^\([[:space:]]*\)r:get("/", auth.game, home)#\1r:get("/__test/hot", function(req) return view.render("hotdir/page", { who = require("hotdir.mod").who() }, req) end)\n&#' \
	"$T/app/routes/home.lua"
t_wait_for /__test/hot 'hot new-module' && t_ok || t_fail "new module/template not picked up"
echo 'return { who = function() return "edited-module" end }' > "$T/app/hotdir/mod.lua"
t_wait_for /__test/hot 'hot edited-module' && t_ok || t_fail "edit of new module not picked up"
echo '{% if then %}' >> "$T/templates/hotdir/page.html"
t_wait_for /__test/hot 'hotdir/page.html:2:' && t_ok || t_fail "template syntax error not reported with its line"
expect_status 500
echo '<p>hot {{ who }} fixed</p>' > "$T/templates/hotdir/page.html"
t_wait_for /__test/hot 'hot edited-module fixed' && t_ok || t_fail "template fix not picked up"
expect_status 200
# app-level config keys apply without a restart (dev = false hides tracebacks)
sed -i 's/^\([[:space:]]*\)dev = true,$/\1dev = false,/' "$CONFIG"
for _ in $(seq 1 50); do
	t_get /__test/boom; grep -qF 'intentional test error' "$BODY" || break; sleep 0.1
done
expect_status 500; expect_body 'Something went wrong'; expect_no_body 'intentional test error'
sed -i 's/^\([[:space:]]*\)dev = false,$/\1dev = true,/' "$CONFIG"
t_wait_for /__test/boom 'intentional test error' && t_ok || t_fail "config restore not picked up"

# ---------------------------------------------------------------------------------
# feature scripts (E2E_ONLY=town,fight runs just tests/e2e/{town,fight}.sh)
for f in "$ROOT"/tests/e2e/*.sh; do
	[ -e "$f" ] || continue
	if [ -n "${E2E_ONLY:-}" ]; then
		case ",$E2E_ONLY," in *",$(basename "$f" .sh),"*) ;; *) continue ;; esac
	fi
	t_jar default
	# shellcheck source=/dev/null
	. "$f"
done

# stop the server first so sanitizer exit reports (DEBUG=1 builds) land in the log
kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
SERVER_PID=
t_section "server log"
if grep '\[error\]' "$T/server.log" | grep -qv '__test/'; then
	t_fail "errors in server log:"; grep -A5 '\[error\]' "$T/server.log" | head -40 >&2
fi
if grep -qE 'runtime error:|Sanitizer' "$T/server.log" "$T/install.log" "$T/unit.log"; then
	t_fail "sanitizer reports:"; grep -hE -A20 'runtime error:|Sanitizer' "$T/server.log" "$T/install.log" "$T/unit.log" | head -60 >&2
fi

echo "e2e: $PASS passed, $FAILS failed"
[ "$FAILS" = 0 ]
