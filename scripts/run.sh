#!/usr/bin/env bash
# scripts/run.sh :: `make run`: serve the game locally, setting things up on first use.
#
#   [DK_BIN=./dk] [CONFIG=config.lua] [PORT=8080] [BIND=addr] \
#   [ADMIN_USER=admin] [ADMIN_EMAIL=admin@example.com] [ADMIN_PASS=admin] scripts/run.sh
#
# Run from the directory the config's relative paths refer to (make run: the source tree).
# - no CONFIG: creates it from config.example.lua with a random secret;
# - no database: `dk install` with the ADMIN_* account;
# - an out-of-date database: `dk check`, `dk backup`, `dk migrate` (as make migrate);
# then `exec dk serve --port PORT [--bind BIND]` in the foreground.
# An existing config or database is never replaced.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DK=${DK_BIN:-./dk}
CONFIG=${CONFIG:-config.lua}
PORT=${PORT:-8080}
BIND=${BIND:-}
ADMIN_USER=${ADMIN_USER:-admin}
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.com}
ADMIN_PASS=${ADMIN_PASS:-admin}
NO_DB=3  # exit status of dk migrate when the database does not exist

die() { echo "run: $*" >&2; exit 1; }

[ -x "$DK" ] || die "$DK not found (make run builds it)"

host=${BIND:-127.0.0.1}
case $host in 0.0.0.0) host=127.0.0.1 ;; ::) host=::1 ;; esac
case $host in *:*) host="[$host]" ;; esac
url="http://$host:$PORT/"
[ "$PORT" = 0 ] && url="http://$host:<free port, see the log>/"

if [ ! -e "$CONFIG" ]; then
	secret=$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')
	[ ${#secret} = 64 ] || die "cannot read random bytes for the secret"
	sed "s/^\([[:space:]]*\)secret = \"\",/\1secret = \"$secret\",/" "$ROOT/config.example.lua" > "$CONFIG.tmp"
	grep -qF "secret = \"$secret\"," "$CONFIG.tmp" || { rm -f "$CONFIG.tmp"; die "config.example.lua has no 'secret = \"\",' line"; }
	mv "$CONFIG.tmp" "$CONFIG"
	echo "run: created $CONFIG from config.example.lua with a random secret (edit it to taste)"
fi

rc=0
status=$("$DK" migrate --config "$CONFIG" --status 2>&1) || rc=$?
if [ "$rc" = "$NO_DB" ]; then
	echo "run: no database yet; installing the game with an administrator account"
	"$DK" install --config "$CONFIG" --admin "$ADMIN_USER" "$ADMIN_EMAIL" "$ADMIN_PASS"
	echo "run: log in at $url as '$ADMIN_USER' with password '$ADMIN_PASS'"
elif [ "$rc" != 0 ]; then
	die "the database can't be used: $status"
elif [[ $status == *"(run dk migrate)"* ]]; then
	echo "run: $status"
	"$DK" check --config "$CONFIG"
	"$DK" backup --config "$CONFIG"
	"$DK" migrate --config "$CONFIG"
fi

args=(serve --config "$CONFIG" --port "$PORT")
[ -n "$BIND" ] && args+=(--bind "$BIND")
echo "Dragon Knight on $url (Ctrl-C to stop)"
exec "$DK" "${args[@]}"
