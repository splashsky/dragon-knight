# tests/e2e/terrain.sh :: the land (docs/APP.md "Terrain and the map", lib/terrain.lua):
# the Location box names the biome and the feature; the exploring page says where the
# player stands and what lies next door, in a region of its own; a fight on the land's
# field (the Battlefield line, the fight's data, the encounter's first line); /help/fields
# lists the terrain group. Places are found in the world's data (app/lib/terrain/world.lua:
# permanent). Sourced by tests/run.sh.
if ! t_has_sql || ! command -v python3 >/dev/null; then
	t_section "terrain (skipped: needs sqlite3 or python3, and python3)"
else

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
grep -qE '<p class="explore-standing">(Black water and reed-beds|Thornwood spines|A stilt-hut)' "$BODY" && t_ok \
	|| t_fail "a Thornbog line where the player stands: $(grep -o '<p class="explore-standing">[^<]*' "$BODY")"
# the same on a reload (hashed, never rolled)
TE_LINE=$(grep -o '<p class="explore-standing">[^<]*' "$BODY")
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
expect_body '<span class="fight-field tip-term" data-field="marsh" data-tip tabindex="0">Marsh<template class="tip"><div class="tip-title">Marsh</div><div class="tip-meta">Terrain</div><ul class="tip-lines"><li>Fire damage -10%</li><li>Earth damage +10%</li><li>Poison damage +15%</li>'
grep -qE 'class="fight-yourturn">(Among the reeds, the|Knee-deep in the bog, you meet the)' "$BODY" && t_ok \
	|| t_fail "the encounter opens with the Thornbog's line: $(grep -o 'class="fight-yourturn">[^<]*' "$BODY" | head -n1)"
# a GET changes nothing
TE_DATA=$(t_sql "SELECT data FROM fights WHERE user_id = (SELECT id FROM users $TQ)")
T_NOW=$((T_NOW + 600)) t_get /fight
[ "$(t_sql "SELECT data FROM fights WHERE user_id = (SELECT id FROM users $TQ)")" = "$TE_DATA" ] && t_ok || t_fail "a GET moved the fight"
t_fight_clear terrainer
t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 $TQ"

t_section "terrain: /help/fields"
t_get /help/fields
expect_row '<td style="width: 15%">Terrain</td><td style="width: 40%">Fire damage -35%<br>Lightning damage +15%<br>Water damage +20%<br>Burning can&#39;t take hold<br>Dexterity -20%</td>'
fi
