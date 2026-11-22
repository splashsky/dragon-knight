---
id: world/overview
summary: The map of the world: its axes, the eight towns and the cross they lie on, distance as danger, the road order, the edge, and how to read a place named in lore.
related: [world/weather-and-time, towns/midworld, towns/endworld, legends/upper-echelon, lands/midlands, lands/dry-country, peoples/roads-and-outlaws]
sources: [app/sql/seed.sql, app/lib/terrain/world.lua, app/lib/terrain.lua, app/fight/combat.lua, app/town/explore.lua, app/town/travel.lua, app/town/maps.lua, app/content/classes/warrior.lua, app/content/monsters/greatest_devil.lua, app/content/monsters/demon_king.lua, docs/plans/elements-and-weather.md, continuity.md]
---

# The world

## The grid

- The world is a square of 501 x 501 tiles. Latitude runs north (positive) to south, longitude
	east (positive) to west, and both stop at 250 either way: a step past that changes nothing. The
	map is drawn with north at the top.
- A step moves one tile; several directions at once make a diagonal, so a day's walking is
	counted in the larger of the two distances from Midworld (the "ring").
- Every tile can be walked. Lakes are waded and peaks are climbed (`lands/waters-and-heights.md`).
- Each tile belongs to a land (ten of them) and may be hill, peak, lake or pond. The land is
	fixed: it was made once and written down, and nothing moves it.

## The eight towns

| Town | Latitude, longitude | Bearing from Midworld | Ring | Inn | Map | Travel |
|---|---|---|---|---|---|---|
| Midworld | 0, 0 | the hub | 0 | 5 | free | 0 |
| Roma | 30, 30 | north-east | 30 | 10 | 25 | 5 |
| Bris | 70, -70 | north-west | 70 | 25 | 50 | 15 |
| Kalle | -100, 100 | south-east | 100 | 40 | 100 | 30 |
| Narcissa | -130, -130 | south-west | 130 | 60 | 500 | 50 |
| Hambry | 170, 170 | north-east | 170 | 90 | 1000 | 80 |
| Gilead | 200, -200 | north-west | 200 | 100 | 3000 | 110 |
| Endworld | -250, -250 | south-west | 250 | 125 | 9000 | 160 |

Inn, map and travel are gold for a night's rest, gold for the town's map and Travel Points
to go there by the Travel menu (needing its map). Walking onto a town is free and puts it on
the traveller's map. See `towns/midworld.md` and the seven others.

## The cross

The towns lie on two straight lines that cross at Midworld:

- **The north-east / south-west line**: Hambry, Roma, Midworld, Narcissa, Endworld.
- **The north-west / south-east line**: Gilead, Bris, Midworld, Kalle.

So the world is four arms from one hub. Each arm has a character of its own, and its towns
climb in strangeness as they go out. The north-east arm is the downs and then the weald
(Roma, Hambry); the north-west is the shoals and then the barrens (Bris, Gilead); the south-east
holds Kalle alone, with wild country around it; the south-west is moor and then
ash (Narcissa, Endworld).

## Distance is danger

A monster is met by the ring, not by the land. At a tile whose larger distance from Midworld is
`d`, the top level met is `(d + 5) // 5` and the bottom is two below it (never below 1). A level
is a ring five tiles wide; one step in five on foot meets something. Towns are never fought in.

| Where | Ring | Levels met |
|---|---|---|
| Midworld | 0 | 1 |
| Roma | 30 | 5 to 7 |
| Bris | 70 | 13 to 15 |
| Kalle | 100 | 19 to 21 |
| Narcissa | 130 | 25 to 27 |
| Hambry | 170 | 33 to 35 |
| Gilead | 200 | 39 to 41 |
| Endworld | 250 | 49 to 50 |

At the edge the band reaches 51, but no monster is above 50. The strongest things, from level 42 (`legends/upper-echelon.md`), live in the outer rings,
past Gilead. The three monsters that do not roam (the Goblin Shaman, the Bog Witch and the
Bandit Captain) are met only where something places them. A drop is the gift of a level, not
of a beast: any monster of the right level may leave it, and the tales name only where the
first was found.

## The road order

A town's market sells the maps of the towns on either side of it, in this order, which is the
order a traveller meets them: Midworld, Roma, Bris, Kalle, Narcissa, Hambry, Gilead, Endworld.
It is a road in the telling, and a long zigzag on the ground:

| Leg | Straight line | Notes |
|---|---|---|
| Midworld to Roma | 42 tiles | along the north-east arm |
| Roma to Bris | 108 | across the north, past the hills |
| Bris to Kalle | 240 | the line runs through Midworld |
| Kalle to Narcissa | 232 | across the south |
| Narcissa to Hambry | 424 | the line runs through Midworld |
| Hambry to Gilead | 371 | across the far north |
| Gilead to Endworld | 453 | down the whole west |

## The edge

Nothing can be walked past the edge. Endworld sits at the south-west corner, on it. What lore
calls "beyond Endworld" (a sea-coast, a deep lake, high mountains and valleys, a stronghold of
demons) is the far side of the edge: known by the things that come from it, and by the heat
that "rolls in from the edge of the world". The map near the corner is ash, dry country and hills, with no
lake and one peak within 75 tiles; its big lakes lie along the south and west edges
(`lands/waters-and-heights.md`). The things said to live there (the Siren, the Leviathan, the Titan, the Red Dragon)
are met on the outermost ring. See `towns/endworld.md`.

## Reading a place named in lore

Lore places things loosely. A place named in a lore line is a region, not a coordinate.

- "Near", "around", "outside" a town: its own land and the next one out.
- "Past" and "beyond" a town: farther from Midworld than the town, along its arm.
- "Above" a place means higher ground there (the passes above Kalle), not north of it.
- "Between X and Y" means the country between their lands. Bris and Kalle lie either side of
	Midworld, and so do Narcissa and Hambry; their roads are read loosely, off the hub. The wild
	country (`lands/dry-country.md`, `lands/thornbog.md`) lies in the gaps off the two lines.
- When a monster's lore and its level disagree about distance, the level is right: a dragon
	said to live over Kalle is met on the rings past it. See `legends/upper-echelon.md`.

## The ten lands

The Midlands (Midworld), the Copper Downs (Roma), the Salt Shoals (Bris), the Diggings (Kalle),
the Greymoor (Narcissa), the Hambry Weald (Hambry), the Storm Barrens (Gilead) and the Ashlands
(Endworld), and in the gaps the Dry Country and the Thornbog. Each has its own chunk under
`lands/`; the weather over them is in `world/weather-and-time.md`.

## A few facts of the world's age

- Midworld is the first town. It was founded when the Demon King already ruled, and the old
	kingdom's roads, garrisons and crown run out from it (`legends/upper-echelon.md`).
- Characters begin in Midworld, and the Warrior's training road is the one to Roma
	(`peoples/roads-and-outlaws.md`).
