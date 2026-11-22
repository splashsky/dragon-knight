#!/bin/sh
# tools/world.sh :: (re)writes the world's data and picture (docs/APP.md "Terrain and the
# map"): app/lib/terrain/world.lua from world generator v1 (app/lib/terrain/generator_v1.lua),
# and public/images/world.svg drawn from it (app/lib/terrain/picture.lua).
#
#   BIN=./dk tools/world.sh
#
# The data it writes must be the committed data, byte for byte (tests/lua/test_terrain.lua
# checks it, and that the picture is the drawing of it), so this changes nothing unless
# generator v1 or the picture's drawing or colours changed. Generator v1 may still change
# until 3.2.0 is released (run this then, and commit both files); after the release the
# world is permanent, and a new world is a new generator beside v1 and a deliberate commit
# of its data. It runs in the project's own
# Lua: a scratch copy of app/ whose cli/check.lua is tools/world.lua, run by `dk check`
# (which needs no database).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=${BIN:-./dk}
case $BIN in /*) ;; *) BIN="$ROOT/${BIN#./}" ;; esac
[ -x "$BIN" ] || { echo "world.sh: $BIN not found (build with make)" >&2; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/dk-world.XXXXXX")
trap 'rm -rf "$T"' EXIT
cp -r "$ROOT/app" "$T/app"
cp "$ROOT/tools/world.lua" "$T/app/cli/check.lua"
cat > "$T/config.lua" <<EOF
return {
	db_path = "$T/dk.db",
	app_dir = "$T/app",
	template_dir = "$ROOT/templates",
	public_dir = "$ROOT/public",
	secret = "world",
}
EOF
DK_WORLD_OUT="$T" "$BIN" check --config "$T/config.lua" >"$T/out" 2>&1 || { cat "$T/out" >&2; exit 1; }
cp "$T/world.lua" "$ROOT/app/lib/terrain/world.lua"
cp "$T/world.svg" "$ROOT/public/images/world.svg"
echo "wrote app/lib/terrain/world.lua and public/images/world.svg"
