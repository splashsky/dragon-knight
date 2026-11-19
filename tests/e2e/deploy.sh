# tests/e2e/deploy.sh :: `make dist`, `make deploy` to a local directory and to a "remote"
# one (through a fake ssh that runs commands locally), and the DEST parsing of
# scripts/deploy.sh. Sourced by tests/run.sh. The first run builds build/release/dk.

dep_make() {  # a clean make in the source tree (not the one running make test)
	env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u MAKEOVERRIDES \
		make -C "$ROOT" --no-print-directory -j"$(nproc 2>/dev/null || echo 2)" "$@"
}
dep_inode() { stat -c %i "$1"; }

t_section "deploy: DEST parsing"
dep_parse() {  # dep_parse DEST expected
	local got
	got=$("$ROOT/scripts/deploy.sh" --parse-dest "$1" 2>&1 | tr '\t' '|')
	if [ "$got" = "$2" ]; then t_ok; else t_fail "--parse-dest '$1': expected '$2', got '$got'"; fi
}
dep_parse /srv/dk                "local|/srv/dk"
dep_parse games/dk               "local|games/dk"
dep_parse ./odd:name             "local|./odd:name"
dep_parse a/b:c                  "local|a/b:c"
dep_parse host:/srv/dk           "remote|host|/srv/dk"
dep_parse deploy@example.org:dk  "remote|deploy@example.org|dk"
dep_parse host:                  "remote|host|."
dep_parse 'host:~'               "remote|host|."
dep_parse 'host:~/games/dk'      "remote|host|games/dk"
dep_parse host:dir/with:colon    "remote|host|dir/with:colon"
"$ROOT/scripts/deploy.sh" --parse-dest :dir >/dev/null 2>&1 && t_fail "empty host accepted" || t_ok
DEST= "$ROOT/scripts/deploy.sh" --preflight >"$T/deploy.out" 2>&1 && t_fail "preflight without DEST" || t_ok
grep -qF 'DEST is not set' "$T/deploy.out" && t_ok || t_fail "no DEST message: $(cat "$T/deploy.out")"
dep_make deploy >"$T/deploy.out" 2>&1 && t_fail "make deploy without DEST succeeded" || t_ok
grep -qF 'DEST is not set' "$T/deploy.out" && t_ok || t_fail "make deploy without DEST: $(cat "$T/deploy.out")"

t_section "dist"
DEP_VERSION=$(sed -n 's/^view\.GAME_VERSION = "\(.*\)"$/\1/p' "$ROOT/app/lib/view.lua")
DEP_TGZ="$T/dist/dk-$DEP_VERSION-$(uname -s | tr A-Z a-z)-$(uname -m | tr A-Z a-z).tar.gz"
dep_make dist DIST="$T/dist" >"$T/dist.log" 2>&1 && t_ok || { t_fail "make dist:"; tail -20 "$T/dist.log" >&2; }
if [ -f "$DEP_TGZ" ]; then
	t_ok
	tar -tzf "$DEP_TGZ" | sed 's#/$##' > "$T/dist.list"
	for e in dk app/main.lua app/lib/view.lua templates/layout public/css/dk.css \
			config.example.lua README.md LICENSE; do
		grep -qxF "dk-$DEP_VERSION/$e" "$T/dist.list" && t_ok || t_fail "tarball lacks dk-$DEP_VERSION/$e"
	done
	grep -v "^dk-$DEP_VERSION\(/\|$\)" "$T/dist.list" | head -3 | grep -q . \
		&& t_fail "entries outside dk-$DEP_VERSION/" || t_ok
	grep -E '(^|/)(config\.lua|data|backups)$|\.db$' "$T/dist.list" | head -3 | grep -q . \
		&& t_fail "tarball has config.lua, data or a database" || t_ok
	[ "$(ls -A "$T/dist")" = "$(basename "$DEP_TGZ")" ] && t_ok || t_fail "make dist left files: $(ls -A "$T/dist")"
	mkdir -p "$T/dist/x"
	tar -xzf "$DEP_TGZ" -C "$T/dist/x"
	(cd "$T/dist/x/dk-$DEP_VERSION" && ./dk version && ./dk check) >"$T/dist.out" 2>&1 \
		&& t_ok || t_fail "unpacked dist does not run: $(cat "$T/dist.out")"
else
	t_fail "no $DEP_TGZ"
fi

if ! command -v rsync >/dev/null; then
	t_section "deploy (skipped: needs rsync)"
else

t_section "deploy: first deploy to a new local directory"
DEP="$T/deploy/site"
DEP_REL="$ROOT/build/release/dk"
dep_make deploy DEST="$DEP" >"$T/deploy.out" 2>&1 && t_ok || { t_fail "make deploy:"; tail -20 "$T/deploy.out" >&2; }
grep -qF 'No database yet' "$T/deploy.out" && grep -qF './dk install --config config.lua --admin' "$T/deploy.out" \
	&& t_ok || t_fail "no install hint: $(cat "$T/deploy.out")"
grep -qF 'migrating' "$T/deploy.out" && t_fail "migrated without a database" || t_ok
[ -x "$DEP/dk" ] && cmp -s "$DEP/dk" "$DEP_REL" && t_ok || t_fail "release binary not deployed"
for f in app/main.lua templates/layout public/css/dk.css config.example.lua README.md LICENSE; do
	[ -e "$DEP/$f" ] && t_ok || t_fail "deployed tree lacks $f"
done
[ ! -e "$DEP/data" ] && [ ! -e "$DEP/config.lua" ] && [ ! -e "$DEP/.dk.deploy" ] \
	&& t_ok || t_fail "first deploy created data/, config.lua or left .dk.deploy: $(ls -A "$DEP")"

t_section "deploy: upgrade an installed directory"
cat > "$DEP/config.lua" <<EOF
return { port = 0, secret = "deploy-test-secret", pbkdf2_iterations = 1000 }
EOF
(cd "$DEP" && ./dk install --admin depadmin dep@example.com deppass) >"$T/deploy.out" 2>&1 \
	&& t_ok || t_fail "install in the deployed tree: $(cat "$T/deploy.out")"
echo keep > "$DEP/data/keep.txt"
echo keep > "$DEP/notes.txt"
echo 'return {}' > "$DEP/app/stale.lua"
mkdir -p "$DEP/templates/stale"; echo x > "$DEP/templates/stale/old.html"
echo '<p>local edit</p>' >> "$DEP/templates/auth/login.html"
cp "$BIN" "$DEP/dk"  # a different binary: deploy swaps in the release one
DEP_CONFIG_SUM=$(cksum < "$DEP/config.lua")
DEP_DB_ROWS=$(t_sql_db "$DEP/data/dk.db" "SELECT count(*) FROM users")
DEP_OLD_INODE=$(dep_inode "$DEP/dk")
dep_make deploy DEST="$DEP" RESTART='touch restarted.flag' >"$T/deploy.out" 2>&1 \
	&& t_ok || { t_fail "make deploy (upgrade):"; tail -20 "$T/deploy.out" >&2; }
grep -qF 'dk binary updated' "$T/deploy.out" && t_ok || t_fail "binary not reported updated"
cmp -s "$DEP/dk" "$DEP_REL" && [ "$(dep_inode "$DEP/dk")" != "$DEP_OLD_INODE" ] \
	&& t_ok || t_fail "binary not replaced by a rename"
[ ! -e "$DEP/.dk.deploy" ] && t_ok || t_fail ".dk.deploy left behind"
DEP_BACKUPS=$(ls "$DEP/data/backups" 2>/dev/null | grep -c '^dk-[0-9]\{8\}-[0-9]\{6\}\.db$')
[ "$DEP_BACKUPS" = 1 ] && t_ok || t_fail "expected one backup, got: $(ls "$DEP/data/backups" 2>&1)"
grep -qF 'Database schema is up to date' "$T/deploy.out" && t_ok || t_fail "migrate did not run: $(cat "$T/deploy.out")"
[ -e "$DEP/restarted.flag" ] && t_ok || t_fail "RESTART command did not run in DEST"
[ "$(cksum < "$DEP/config.lua")" = "$DEP_CONFIG_SUM" ] && t_ok || t_fail "config.lua changed"
[ -f "$DEP/data/keep.txt" ] && [ -f "$DEP/notes.txt" ] && t_ok || t_fail "files outside the synced dirs removed"
[ "$(t_sql_db "$DEP/data/dk.db" "SELECT count(*) FROM users")" = "$DEP_DB_ROWS" ] && t_ok || t_fail "database rows changed"
[ ! -e "$DEP/app/stale.lua" ] && [ ! -e "$DEP/templates/stale" ] && t_ok || t_fail "stale files not deleted"
cmp -s "$DEP/templates/auth/login.html" "$ROOT/templates/auth/login.html" && t_ok || t_fail "edited template not restored"

t_section "deploy: unchanged binary, failing target check"
DEP_OLD_INODE=$(dep_inode "$DEP/dk")
dep_make deploy DEST="$DEP" >"$T/deploy.out" 2>&1 && t_ok || { t_fail "make deploy (again):"; tail -20 "$T/deploy.out" >&2; }
grep -qF 'dk binary unchanged' "$T/deploy.out" && [ "$(dep_inode "$DEP/dk")" = "$DEP_OLD_INODE" ] \
	&& t_ok || t_fail "unchanged binary was copied"
grep -qF 'no restart needed' "$T/deploy.out" && t_ok || t_fail "no hot reload note: $(cat "$T/deploy.out")"
echo 'return {' > "$DEP/broken.lua"
DEP_BACKUPS=$(ls "$DEP/data/backups" | wc -l)
dep_make deploy DEST="$DEP" CONFIG=broken.lua >"$T/deploy.out" 2>&1 && t_fail "deploy with a broken target config succeeded" || t_ok
[ "$(ls "$DEP/data/backups" | wc -l)" = "$DEP_BACKUPS" ] && t_ok || t_fail "backup made after a failed check"
DEST="$ROOT" "$ROOT/scripts/deploy.sh" --preflight >"$T/deploy.out" 2>&1 && t_fail "deploy into the source tree allowed" || t_ok

t_section "deploy: remote DEST (fake ssh)"
# ssh stand-in: runs the command locally in $T/remote (the "home directory")
mkdir -p "$T/fakessh" "$T/remote"
cat > "$T/fakessh/ssh" <<'EOF'
#!/bin/sh
user=
while [ $# -gt 0 ]; do
	case $1 in
		--) shift; break ;;
		-l) user=$2@; shift 2 ;;
		-p | -i | -o | -F) shift 2 ;;
		-*) shift ;;
		*) break ;;
	esac
done
echo "$user$1" >> "$FAKE_SSH_LOG"
shift
cd "$FAKE_SSH_HOME" || exit 255
if [ "$*" = "uname -sm" ] && [ -n "${FAKE_UNAME:-}" ]; then echo "$FAKE_UNAME"; exit 0; fi
exec sh -c "$*"
EOF
chmod +x "$T/fakessh/ssh"
dep_remote() {
	PATH="$T/fakessh:$PATH" FAKE_SSH_HOME="$T/remote" FAKE_SSH_LOG="$T/fakessh/log" dep_make deploy "$@"
}
dep_remote DEST='deployer@gamehost:~/srv/dk' >"$T/deploy.out" 2>&1 && t_ok || { t_fail "remote deploy:"; tail -20 "$T/deploy.out" >&2; }
RDEP="$T/remote/srv/dk"
grep -qF 'No database yet' "$T/deploy.out" && t_ok || t_fail "remote: no install hint: $(cat "$T/deploy.out")"
cmp -s "$RDEP/dk" "$DEP_REL" && [ -f "$RDEP/app/main.lua" ] && [ -f "$RDEP/LICENSE" ] && t_ok || t_fail "remote files"
grep -qvx 'deployer@gamehost' "$T/fakessh/log" && t_fail "ssh got other hosts: $(sort -u "$T/fakessh/log")" || t_ok
cp "$DEP/config.lua" "$RDEP/config.lua"
(cd "$RDEP" && ./dk install --admin depadmin dep@example.com deppass) >/dev/null 2>&1 || t_fail "remote install"
echo 'return {}' > "$RDEP/app/stale.lua"
DEP_OLD_INODE=$(dep_inode "$RDEP/dk")
FAKE_UNAME='Plan9 vax' dep_remote DEST='deployer@gamehost:srv/dk' RESTART='touch restarted.flag' >"$T/deploy.out" 2>&1 \
	&& t_ok || { t_fail "remote upgrade:"; tail -20 "$T/deploy.out" >&2; }
grep -qF "warning: deployer@gamehost is 'Plan9 vax'" "$T/deploy.out" && grep -qF 'not copying the dk binary' "$T/deploy.out" \
	&& t_ok || t_fail "no platform warning: $(cat "$T/deploy.out")"
[ "$(dep_inode "$RDEP/dk")" = "$DEP_OLD_INODE" ] && t_ok || t_fail "binary copied to a different platform"
[ "$(ls "$RDEP/data/backups" | wc -l)" = 1 ] && t_ok || t_fail "remote backup"
grep -qF 'Database schema is up to date' "$T/deploy.out" && t_ok || t_fail "remote migrate"
[ -e "$RDEP/restarted.flag" ] && [ ! -e "$RDEP/app/stale.lua" ] && [ -f "$RDEP/config.lua" ] \
	&& t_ok || t_fail "remote restart/delete/config"

fi
