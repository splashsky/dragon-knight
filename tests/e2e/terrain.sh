# tests/e2e/terrain.sh :: the land (docs/APP.md "Terrain and the map", lib/terrain.lua):
# the Location box names the biome and the feature; the exploring page says where the
# player stands and what lies next door, in a region of its own; a fight on the land's
# field (the Battlefield line, the fight's data, the encounter's first line); /help/fields
# lists the terrain group; the World Map's weather (/map/sky, and as data /map/sky/data),
# the tick's `sky` event and the sky it keeps for both (meta map_sky).
# Places are found in the world's data (app/lib/terrain/world.lua). Sourced by tests/run.sh.
if ! t_has_sql || ! command -v python3 >/dev/null; then
	t_section "terrain (skipped: needs sqlite3 or python3, and python3)"
else

# te_from KIND KEY LIST TEXT: TEXT (as the page shows it, entities and all) is one of the
# lines of terrain_lines.lua's KIND ("biome" or "feature") KEY's LIST, "{monster}" and
# "{direction}" standing for any words. Lines are picked by a hash and the lists grow, so
# the tests ask "one of this place's lines", never which one.
te_from() {
	python3 - "$ROOT/app/lib/terrain_lines.lua" "$1" "$2" "$3" "$4" <<'PY'
import html, re, sys
text, kind, key, name, line = open(sys.argv[1]).read(), sys.argv[2], sys.argv[3], sys.argv[4], html.unescape(sys.argv[5])
def block(s, opener):
	i = s.index(opener) + len(opener)
	depth = 1
	for j in range(i, len(s)):
		depth += {"{": 1, "}": -1}.get(s[j], 0)
		if depth == 0: return s[i:j]
part = block(block(block(text, "\n\t" + kind + " = {"), "\n\t\t" + key + " = {"), name + " = {")
for cand in re.findall(r'"((?:[^"\\]|\\.)*)"', part):
	pattern = re.escape(cand).replace(re.escape("{monster}"), ".+").replace(re.escape("{direction}"), ".+")
	if re.fullmatch(pattern, line): sys.exit(0)
sys.exit(1)
PY
}

# te_place LAND RELIEF [NEIGHBOUR]: "lat lon" of the first tile (a cell's centre, read
# north-west to south-east) whose cell has the biome letter LAND and the feature character
# RELIEF; with NEIGHBOUR "north", the top tile of such a cell whose northern neighbour's
# land differs.
te_place() {
	python3 - "$ROOT/app/lib/terrain/world.lua" "$1" "$2" "${3:-}" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
rows = lambda name: re.findall(r'"([A-Z.~on^]+)"', text.split(name + " = {", 1)[1].split("}", 1)[0])
land, relief = rows("land"), rows("relief")
cells = (len(land) - 1) // 2
for r in range(1, len(land)):
	for c in range(len(land[r])):
		if land[r][c] == sys.argv[2] and relief[r][c] == sys.argv[3]:
			lat, lon = (cells - r) * 5, (c - cells) * 5
			if sys.argv[4] == "north":
				if (land[r - 1][c], relief[r - 1][c]) == (land[r][c], relief[r][c]):
					continue
				lat += 2
			if abs(lat) < 20 and abs(lon) < 20:
				continue
			print(lat, lon)
			sys.exit(0)
sys.exit(1)
PY
}

t_section "terrain: the Location box and the exploring page"
t_jar terrain; t_reset_jar
t_register terrainer terrainpw1 terrain@example.com Terrainer 2
t_login terrainer terrainpw1
TQ="WHERE username = 'terrainer'"
t_get /; expect_body '<div class="loc-land">The Midlands</div>'
read -r TE_LAT TE_LON <<EOF
$(te_place T .)
EOF
[ -n "$TE_LAT" ] && t_ok || t_fail "a Thornbog tile in the world's data"
t_sql "UPDATE users SET currentaction = 'Exploring', latitude = $TE_LAT, longitude = $TE_LON $TQ"
t_get /; expect_body '<div class="loc-land">The Thornbog</div>'
expect_body '<div class="explore-land" data-r="explore-land"><p class="explore-standing">'
TE_LINE=$(grep -o '<p class="explore-standing">[^<]*' "$BODY")
te_from biome marsh standing "${TE_LINE#*>}" && t_ok || t_fail "a Thornbog line where the player stands: $TE_LINE"
# the same on a reload (hashed, never rolled)
t_get /; [ "$(grep -o '<p class="explore-standing">[^<]*' "$BODY")" = "$TE_LINE" ] && t_ok || t_fail "the same line again"
# a hill tile: the feature is named too
read -r TE_LAT TE_LON <<EOF
$(te_place K n)
EOF
t_sql "UPDATE users SET latitude = $TE_LAT, longitude = $TE_LON $TQ"
t_get /; expect_body '<div class="loc-land">The Diggings &middot; Hills</div>'
# at the edge of a cell whose northern neighbour differs: a line naming the north
read -r TE_LAT TE_LON <<EOF
$(te_place M . north)
EOF
t_sql "UPDATE users SET latitude = $TE_LAT, longitude = $TE_LON $TQ"
t_get /; grep -qE '<p class="explore-land-edge">[^<]*north' "$BODY" && t_ok \
	|| t_fail "a line for the land to the north at $TE_LAT,$TE_LON: $(grep -o 'explore-land.*' "$BODY" | head -n1)"

t_section "terrain: a fight on the land's field"
read -r TE_LAT TE_LON <<EOF
$(te_place T .)
EOF
t_sql "UPDATE users SET currenthp = 5000, base_maxhp = 5000, latitude = $TE_LAT, longitude = $TE_LON $TQ"
t_fight_new terrainer
case "$(t_sql "SELECT replace(data, char(10), ';') FROM fights WHERE user_id = (SELECT id FROM users $TQ)")" in
	*"field_terrain=s:marsh"*) t_ok ;; *) t_fail "the marsh's field kept with the fight" ;;
esac
expect_body '<span class="fight-field tip-term" data-field="marsh" data-tip tabindex="0"><img class="fight-field-icon" src="/static/images/fields/marsh.png" width="18" height="18" alt="">Marsh<template class="tip"><div class="tip-title"><img class="tip-icon" src="/static/images/fields/marsh.png" width="20" height="20" alt="">Marsh</div><div class="tip-meta">Terrain</div><ul class="tip-lines"><li>Fire damage -10%</li><li>Earth damage +10%</li><li>Poison damage +15%</li>'
TE_OPEN=$(grep -o 'class="fight-yourturn">[^<]*' "$BODY" | head -n1)
te_from biome marsh fight_open "${TE_OPEN#*>}" && t_ok || t_fail "the encounter opens with the Thornbog's line: $TE_OPEN"
# a GET changes nothing
TE_DATA=$(t_sql "SELECT data FROM fights WHERE user_id = (SELECT id FROM users $TQ)")
T_NOW=$((T_NOW + 600)) t_get /fight
[ "$(t_sql "SELECT data FROM fights WHERE user_id = (SELECT id FROM users $TQ)")" = "$TE_DATA" ] && t_ok || t_fail "a GET moved the fight"
t_fight_clear terrainer
t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 $TQ"

t_section "terrain: the World Map's weather (/map/sky)"
t_jar terrain
t_get /map/sky; expect_status 200; expect_header '^content-type: image/svg\+xml'
expect_body '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 101 101"'
expect_body "<g class=\"world-sky\" data-sky=\"$((T_NOW / 10))\">"
expect_body '<g class="sky-cells">'; expect_body '<g class="sky-storms">'
# a pure function of the time: the same again; at night, the night's wash
TE_SKY=$(md5sum < "$BODY"); t_get /map/sky; [ "$(md5sum < "$BODY")" = "$TE_SKY" ] && t_ok || t_fail "the same sky again"
TE_NIGHT=$((T_START - T_START % 7200 + 6000))
T_NOW=$TE_NIGHT t_get /map/sky; expect_body '<g class="sky-time sky-night"><rect '
T_NOW=$((TE_NIGHT - 3000)) t_get /map/sky; expect_body '<g class="sky-time sky-day"></g>'
t_reset_jar; t_get /map/sky; expect_redirect /login
t_login terrainer terrainpw1

t_section "terrain: the World Map's weather as data (/map/sky/data)"
# the same facts for the WebGL sky: the tick, the time of day, the sun and the moon, a
# character per weather cell (51 x 51), the storms in the map's units; pure, at T_NOW
t_get /map/sky/data; expect_status 200; expect_header '^content-type: application/json'
expect_body "\"tick\":$((T_NOW / 10))}"; expect_body '"side":51,'; expect_body '"storms":['
[ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["cells"]), d["phase"], len(d["sun"]), len(d["moon"]))' "$BODY")" = "2601 day 2 2" ] \
	&& t_ok || t_fail "the data's shape: $(head -c 200 "$BODY")"
TE_DATA=$(md5sum < "$BODY"); t_get /map/sky/data; [ "$(md5sum < "$BODY")" = "$TE_DATA" ] && t_ok || t_fail "the same data again"
T_NOW=$TE_NIGHT t_get /map/sky/data; expect_body '"phase":"night"'
T_NOW=$((T_NOW + 10)) t_get /map/sky/data; expect_body "\"tick\":$((T_NOW / 10 + 1))}"
t_reset_jar; t_get /map/sky/data; expect_redirect /login
t_login terrainer terrainpw1

t_section "terrain: the server's tick says the sky moved"
# the weather moves every tick: every tick sends `sky` with its number on every stream, and
# the overlay at that time shows that tick
live_open tesky
t_tick; live_has tesky "data: {\"tick\":$((T_NOW / 10))}"
t_get /map/sky; expect_body "<g class=\"world-sky\" data-sky=\"$((T_NOW / 10))\">"
t_tick; live_has tesky "data: {\"tick\":$((T_NOW / 10))}"
[ "$(live_count tesky 'event: sky')" = 2 ] && t_ok || t_fail "a sky event each tick: $(live_count tesky 'event: sky')"
live_close tesky

t_section "terrain: the tick keeps the sky once for every reader"
# the tick writes its sky into meta (map_sky: the tick on the first line); both routes read
# that row in its tick (a doctored row shows), and compute the sky in another without writing
TE_ROW=$(t_sql "SELECT value FROM meta WHERE key = 'map_sky'")
[ "${TE_ROW%%$'\n'*}" = "$((T_NOW / 10))" ] && t_ok || t_fail "the row is the tick's: ${TE_ROW%%$'\n'*}"
t_get /map/sky/data; TE_CELLS=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["cells"])' "$BODY")
[ "$(t_sql "SELECT instr(value, '$TE_CELLS') > 0 FROM meta WHERE key = 'map_sky'")" = 1 ] && t_ok || t_fail "the data's cells are the row's"
t_sql "UPDATE meta SET value = replace(value, '$TE_CELLS', '$(printf '0%.0s' $(seq 2601))') WHERE key = 'map_sky'"
t_get /map/sky/data; expect_body "\"cells\":\"$(printf '0%.0s' $(seq 2601))\""
t_get /map/sky; expect_no_body 'class="sky-overcast"'; expect_body "<g class=\"world-sky\" data-sky=\"$((T_NOW / 10))\">"
TE_DOCTORED=$(t_sql "SELECT value FROM meta WHERE key = 'map_sky'")
T_NOW=$((T_NOW + 10)) t_get /map/sky/data; expect_no_body "\"cells\":\"$(printf '0%.0s' $(seq 2601))\""
[ "$(t_sql "SELECT value FROM meta WHERE key = 'map_sky'")" = "$TE_DOCTORED" ] && t_ok || t_fail "a read in another tick wrote"
t_tick; [ "$(t_sql "SELECT substr(value, 1, instr(value, char(10)) - 1) FROM meta WHERE key = 'map_sky'")" = "$((T_NOW / 10))" ] \
	&& t_ok || t_fail "the next tick's row"

t_section "terrain: /help/fields"
t_get /help/fields
expect_row '<td style="width: 15%">Terrain</td><td style="width: 40%">Fire damage -35%<br>Lightning damage +15%<br>Water damage +20%<br>Burning can&#39;t take hold<br>Dexterity -20%</td>'
fi
