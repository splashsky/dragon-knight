# 3.4: the map's clouds and fog of war

The plan for 3.4.0. The World Map's weather reads as noise: every 10-tile weather cell
draws its sky with a hash of its own, so a fifth of the cells are overcast, scattered like
salt and pepper, and the map's clouds (WebGL fractal noise over the cells, or blurred
squares in the SVG) look like a haze over everything instead of clouds over regions. And
the map shows the whole world from the first step: there is nothing to find.

Decisions (agreed with the owner):

- **The weather itself becomes coherent**: the base sky comes from smooth fields that drift
	with a prevailing wind and form and dissolve over time, so clouds and drizzle gather in
	banks over regions and fog lies in patches. The shares of each sky per climate stay
	what they are; where and when a player meets them changes.
- **Stylized clouds on the map**: banks of puffy clouds with inked edges, lit tops and shaded
	bases, casting shadows; rain and snow falling from them clearly (dark streaks, outlined
	flakes). In both renderings (the WebGL sky and the SVG reference).
- **Fog of war**: the map shows only what the player has mapped. The unit is the map's cell
	(5 by 5 tiles, the picture's unit): standing in a cell maps it and the eight around it.
	A town's map (bought in a market, or the town visited: `users.towns`) shows the town's
	cell and the eight around it; no road between towns (yet). Existing characters start
	with their towns and where they stand.
- **The fog covers everything** on the map but its frame: the land, its weather (still drawn
	in real time underneath, and genuinely occluded), the towns and their lights at night.
	The border, the compass rose and the scale bar stay above it.
- This is 3.4.0; 3.3.0 is released.

## Invariants (carried over)

- **Pure GETs**: the map reads what a player has explored; only a move (a POST) maps more.
- **Weather is a pure function** of the place, the time and the seed: no dice, nothing
	stored, the same all through a step, on every worker.
- **The server renders the markup**; the WebGL sky stays the one exception (it draws pixels
	from the server's facts).

## A. The weather's fields (`lib/weather.lua`)

- Two smooth fields over the weather's grid (value noise: hashed lattice values, smoothstep
	between, in space and time), each mapped to an even share in [0, 1) by a fixed table of
	its quantiles, so a threshold of p covers a share p of the cells over time:
	- **clouds**: two octaves (lattice 6 and 2.5 cells), drifting toward Gilead (north-west)
		at a cell every five minutes, reshaped every half hour;
	- **fog**: one octave (lattice 4 cells), slower, reshaped every 40 minutes, no drift.
- A cell's base sky by its climate (the shares as before): fog where the fog field is under
	the fog's share (dawn and night adding theirs); otherwise along the cloud field, from
	the wet end drizzle (snow where it snows), then overcast; from the dry end heat by day
	(not where it snows), then sun by day; clear between. Heat keeps its precedence where
	the shares add up past the whole (the Ashlands), sun takes what remains.
- Storms, the ground, snow lines and everything else unchanged.
- Cost: lattice values kept for the request (neighbouring cells share them), so the map's
	2,601 cells cost about what they did.
- Tests: the shares per climate (Midlands, Greymoor at dawn, Ashlands), coherence (a cloudy
	cell's neighbours are cloudy far more often than chance), drift (a cloud bank moves
	north-west), the calm place still calm (re-picked if it isn't), the cost.

## B. Stylized clouds, rain and snow on the map

- **WebGL** (`public/js/worldgl.js`): the cells' cover (as now, smoothed) shapes cloud banks
	of overlapping puffs (cellular puffs at two scales, a drifting detail): crisp outlines in
	the map's ink, lit on the side toward the sun or the moon and shaded away from it, a
	darker base for rain clouds and storms, and shadows cast away from the light. Rain falls
	as dark slanted streaks under the clouds, snow as white flakes with a dark rim; both
	denser with the weather.
- **SVG** (`town/sky.lua`): cloud banks as unions of puffs (circles) over the cloudy cells,
	sized by the sky, with an inked outline (the puffs stroked under their fill); rain as
	darker hatching under them; snow as outlined flakes; the size kept near today's.
- The legend's swatches follow.

## C. Fog of war

- **Data** (schema version 27): `user_explored (user_id → users ON DELETE CASCADE, cells)`:
	a bitmap of the 101 by 101 map cells, six cells a character (`lib/fog.lua`). The step
	maps where each character stands (and the eight around it).
- **`lib/fog.lua`**: the cell of a tile; `fog.known(user)`: the explored cells, each town of
	`users.towns` and where the player stands, with the eight around each; `fog.reveal(id,
	lat, lon)`: the cell and the eight around it stored (a write only when something is new);
	the bitmap's encoding (also read by the WebGL sky).
- **Mapping**: every move (`POST /move`) reveals where it lands. Travel and buying a map add a
	town to `users.towns`, which shows its cells.
- **The map** (`GET /map`, the window): the towns only where known; over the sky a fog group
	(the unknown cells' runs, filled with the parchment and a faint hatching, its edge
	ragged and inked by an SVG filter); over the fog the map's frame, split out of the
	land's picture into `public/images/world-frame.svg` (the border, the compass rose, the
	scale bar). The legend names it. The window is fetched again after a move, as now.
- **The WebGL sky** reads the known cells (`data-fog` on the map), grown by one cell under the
	fog's ragged edge, and draws nothing beyond them (an early return in the shader); its
	frame rate counts only the weather in known land.

## Checks

- `tests/lua/test_weather.lua` (A), `tests/lua/test_sky.lua` (B, the SVG's clouds),
	`tests/lua/test_fog.lua` (C: the cells, the encoding, what a player knows),
	`tests/e2e/town.sh` (the map's fog and its towns), `tests/e2e/migrate.sh` (version 27),
	`tests/e2e/browser.sh` (the WebGL sky with the fog), `tests/lua/test_terrain.lua` (the
	picture and the frame are the drawing).
