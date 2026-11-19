# tests/e2e/server.sh :: engine features visible over HTTP and the CLI: the metrics page
# (/admin/server) and `dk stats`, static file validators (ETag, If-None-Match). Sourced by
# tests/run.sh.

t_section "server: metrics"
t_jar srvanon
t_get /admin/server;       expect_status 403
t_jar srvplayer
t_register srvplayer playerpw1 srvplayer@example.com SrvPlayer
t_login srvplayer playerpw1
t_get /admin/server;       expect_status 403
t_jar srvadmin
t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin;              expect_body 'href="/admin/server"'
t_get /admin/server;       expect_status 200; expect_body '<title>Server</title>'
expect_body '<h2>Per request'; expect_body '<code>requests</code>'; expect_body '<code>vm_restored</code>'
expect_body '<code>db_begin_wait_us</code>'; expect_body 'requests answered within 1 ms'
expect_body '<code>event_backend</code></td><td>epoll</td>'

STATS_OUT=$("$BIN" stats --config "$CONFIG" 2>&1)
if printf '%s\n' "$STATS_OUT" | grep -qE '^  requests +[1-9][0-9]* +requests$'; then t_ok; else t_fail "dk stats: $STATS_OUT"; fi
if printf '%s\n' "$STATS_OUT" | grep -qE '^  vm_hot +[1-9]'; then t_ok; else t_fail "dk stats: no hot VM acquires"; fi
printf '%s\n' "$STATS_OUT" | grep -q '^dk stats from .*/dk.sock$' && t_ok || t_fail "dk stats header"
"$BIN" stats --config "$CONFIG" extra >/dev/null 2>&1; [ $? = 2 ] && t_ok || t_fail "dk stats with an argument should exit 2"

t_section "server: static validators"
t_get /static/css/dk.css;  expect_status 200; expect_header '^etag: "[0-9a-f]+-[0-9a-f]+"'
expect_header '^last-modified: '; expect_header '^cache-control: public, max-age=300'
SRV_ETAG=$(grep -i '^etag:' "$HEADERS" | cut -d' ' -f2 | tr -d '\r')
t_get /static/css/dk.css -H "If-None-Match: $SRV_ETAG"; expect_status 304
t_get /static/css/dk.css -H 'If-None-Match: "other"'; expect_status 200; expect_body 'dk-page'
t_jar default
