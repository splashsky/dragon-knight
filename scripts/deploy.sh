#!/usr/bin/env bash
# scripts/deploy.sh :: `make deploy`: install this working tree on a server and upgrade
# its database.
#
#   DEST=DIR|[USER@]HOST:DIR [CONFIG=config.lua] [RESTART='command'] [DK_BIN=build/release/dk] \
#       scripts/deploy.sh
#   scripts/deploy.sh --preflight         check DEST and the tools only (make deploy runs
#                                         this before building)
#   scripts/deploy.sh --parse-dest DEST   print how DEST is understood (for tests)
#
# 1. checks the working tree with DK_BIN (`dk check`);
# 2. copies DK_BIN to DEST/dk (under a temporary name, then renamed, so a running server
#    is never handed a half-written file), syncs app/ templates/ public/ with --delete
#    and copies config.example.lua README.md LICENSE. Nothing else in DEST is touched:
#    not config.lua, not data/;
# 3. in DEST: `./dk check`, `./dk backup` and `./dk migrate`, all with --config CONFIG
#    (relative paths are relative to DEST). Without a database yet, it prints the
#    first-time setup steps instead and stops;
# 4. runs RESTART in DEST if given.
#
# DEST is remote when it has a ':' before its first '/' (like rsync and scp; write
# ./name:x for a local directory with a colon). Remote steps run over ssh, so DEST's
# machine needs rsync too. The binary must match the server's OS and CPU: if `uname -sm`
# differs there, the binary is not copied and the server keeps its own.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SYNC_DIRS=(app templates public)
SYNC_FILES=(config.example.lua README.md LICENSE)
BIN_TMP=.dk.deploy
NO_DB=3  # `dk backup` exit status when the database does not exist

die() { echo "deploy: $*" >&2; exit 1; }
say() { echo "==> $*"; }

usage_hint() {
	echo "usage: make deploy DEST=/srv/dk | DEST=[user@]host:/srv/dk [CONFIG=config.lua] [RESTART='sudo systemctl restart dk']"
}

# parse_dest DEST: sets DEST_HOST (empty when local) and DEST_DIR.
parse_dest() {
	local d=$1
	[ -n "$d" ] || die "DEST is not set. $(usage_hint)"
	DEST_HOST=
	DEST_DIR=$d
	case ${d%%/*} in
		*:*)
			DEST_HOST=${d%%:*}
			DEST_DIR=${d#*:}
			[ -n "$DEST_HOST" ] || die "DEST '$d' has an empty host name"
			# ssh starts in the home directory: ~ and ~/x are relative paths there
			case $DEST_DIR in
				'' | '~' | '~/') DEST_DIR=. ;;
				'~/'*) DEST_DIR=${DEST_DIR#'~/'} ;;
			esac
			;;
	esac
}

# Single-quote for a POSIX shell (the remote login shell or sh -c).
sq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
# Same, for display: only when needed.
show() { if [[ $1 =~ ^[A-Za-z0-9_./:@+=-]+$ ]]; then printf '%s' "$1"; else sq "$1"; fi; }

# Run a shell command line on the target machine (not inside DEST).
target_sh() {
	if [ -n "$DEST_HOST" ]; then
		ssh -- "$DEST_HOST" "$1"
	else
		sh -c "$1"
	fi
}
# Run a shell command line in DEST.
in_dest() { target_sh "cd $(sq "$DEST_DIR") && $1"; }
# rsync destination for a path inside DEST.
dest_path() {
	if [ -n "$DEST_HOST" ]; then
		printf '%s:%s/%s' "$DEST_HOST" "$DEST_DIR" "$1"
	else
		printf '%s/%s' "$DEST_DIR" "$1"
	fi
}
where() { if [ -n "$DEST_HOST" ]; then echo "$DEST_HOST:$DEST_DIR"; else echo "$DEST_DIR"; fi; }

preflight() {
	parse_dest "${DEST:-}"
	command -v rsync >/dev/null || die "rsync is required (here and on the server)"
	if [ -n "$DEST_HOST" ]; then
		command -v ssh >/dev/null || die "ssh is required for a remote DEST"
	else
		case $DEST_DIR in /*) ;; *) DEST_DIR=$PWD/$DEST_DIR ;; esac
		if [ -d "$DEST_DIR" ] && [ "$(cd "$DEST_DIR" && pwd -P)" = "$(cd "$ROOT" && pwd -P)" ]; then
			die "DEST is this source tree; deploy to another directory"
		fi
	fi
}

check_local() {
	local cfg rc=0
	cfg=$(mktemp "${TMPDIR:-/tmp}/dk-deploy.XXXXXX")
	printf 'return {}\n' > "$cfg"  # defaults: app/, templates/, public/ of this tree
	(cd "$ROOT" && "$DK_BIN" check --config "$cfg") || rc=$?
	rm -f "$cfg"
	[ "$rc" = 0 ] || die "dk check failed on the working tree; nothing was deployed"
}

checksum() { cksum < "$1" | awk '{ print $1 " " $2 }'; }

# Copy the binary unless the target already has this one; sets BIN_CHANGED.
sync_binary() {
	local here there
	BIN_CHANGED=0
	if [ -n "$DEST_HOST" ]; then
		here=$(uname -sm)
		there=$(target_sh 'uname -sm') || die "cannot run commands on $DEST_HOST over ssh"
		if [ "$here" != "$there" ]; then
			echo "deploy: warning: $DEST_HOST is '$there' but this build is for '$here';" >&2
			echo "deploy: warning: not copying the dk binary (the server keeps its own: build it there with make release, or deploy from a '$there' machine)" >&2
			return 0
		fi
	fi
	here=$(checksum "$DK_BIN")
	there=$(in_dest 'if [ -f dk ]; then cksum < dk; fi' | awk '{ print $1 " " $2 }')
	if [ "$here" = "$there" ]; then
		echo "dk binary unchanged"
		return 0
	fi
	rsync -a -s "$DK_BIN" "$(dest_path "$BIN_TMP")"
	in_dest "chmod 755 $BIN_TMP && mv -f $BIN_TMP dk"
	BIN_CHANGED=1
	echo "dk binary updated"
}

sync_files() {
	local d files=()
	for d in "${SYNC_DIRS[@]}"; do
		rsync -a -s --delete "$ROOT/$d/" "$(dest_path "$d/")"
	done
	for d in "${SYNC_FILES[@]}"; do files+=("$ROOT/$d"); done
	rsync -a -s "${files[@]}" "$(dest_path "")"
}

first_install_hint() {
	local cfg
	cfg=$(show "$CONFIG")
	cat <<EOF
No database yet: the game files are in place. To finish a first-time setup, on the server:
	cd $(show "$DEST_DIR")
	cp config.example.lua $cfg    # then set secret, dev = false, cookie_secure, ...
	./dk install --config $cfg --admin USER EMAIL PASSWORD
	./dk serve --config $cfg      # or a systemd unit: see deploy/dk.service
Later deploys back up and migrate the database.
EOF
}

deploy() {
	local cfg rc=0
	CONFIG=${CONFIG:-config.lua}
	DK_BIN=${DK_BIN:-build/release/dk}
	case $DK_BIN in /*) ;; *) DK_BIN=$ROOT/$DK_BIN ;; esac
	[ -x "$DK_BIN" ] || die "$DK_BIN not found (make deploy builds it with make release)"
	cfg=$(sq "$CONFIG")

	say "checking the working tree"
	check_local

	say "syncing to $(where)"
	target_sh "mkdir -p -- $(sq "$DEST_DIR")"
	sync_binary
	sync_files

	say "checking on the target"
	in_dest "./dk check --config $cfg" || die "dk check failed on the target (the files are in place; fix and deploy again)"

	say "backing up the database"
	in_dest "./dk backup --config $cfg" || rc=$?
	if [ "$rc" = "$NO_DB" ]; then
		first_install_hint
		return 0
	fi
	[ "$rc" = 0 ] || die "backup failed; the database was not migrated"

	say "migrating the database"
	in_dest "./dk migrate --config $cfg" || die "dk migrate failed (it changes nothing on error; the backup above is untouched)"

	if [ -n "${RESTART:-}" ]; then
		say "restarting: $RESTART"
		in_dest "$RESTART" || die "restart command failed: $RESTART"
	elif [ "$BIN_CHANGED" = 1 ]; then
		echo "The dk binary changed: restart the server to run it (or pass RESTART='sudo systemctl restart dk')."
	else
		echo "Lua and template changes are live already (hot reload); no restart needed."
	fi
	say "deployed to $(where)"
}

case ${1:-} in
	--parse-dest)
		[ $# = 2 ] || die "usage: $0 --parse-dest DEST"
		parse_dest "$2"
		if [ -n "$DEST_HOST" ]; then
			printf 'remote\t%s\t%s\n' "$DEST_HOST" "$DEST_DIR"
		else
			printf 'local\t%s\n' "$DEST_DIR"
		fi
		;;
	--preflight)
		preflight
		;;
	'')
		preflight
		deploy
		;;
	*)
		die "unknown argument: $1 ($(usage_hint))"
		;;
esac
