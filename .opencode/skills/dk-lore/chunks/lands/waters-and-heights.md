---
id: lands/waters-and-heights
summary: Lakes, ponds, hills and peaks across every land: where they lie, their battlefield fields, who lives in them, and how near each town stands to water and height.
related: [world/overview, world/weather-and-time, lands/midlands, lands/copper-downs, lands/salt-shoals, lands/diggings, lands/greymoor, lands/hambry-weald, lands/storm-barrens, lands/ashlands, lands/dry-country, lands/thornbog, things/battlefield-objects, monsters/elementals, monsters/giants, monsters/drakes-and-dragons, monsters/fey-and-spirits]
sources: [app/lib/terrain_lines.lua, app/lib/terrain.lua, app/lib/terrain/world.lua, app/content/fields/shallows.lua, app/content/fields/hills.lua, app/content/fields/peaks.lua, app/content/monsters/aqua_elemental.lua, app/content/monsters/leviathan.lua, app/content/monsters/blue_dragon.lua, app/content/monsters/titan.lua, app/content/monsters/nymph.lua, docs/plans/elements-and-weather.md, continuity.md#Decided]
---

# Waters and heights

On top of every land lie four features: lakes, ponds, hills and peaks. A feature belongs to no one
land; it takes its own battlefield field, and the land's words give way to the feature's.
Every tile can be walked: lakes are waded and peaks climbed, and nothing blocks the way.

## The numbers

- The world is 73% plain, 17% hills, 5% lakes, 4% peaks and 1% ponds, drawn once and permanent.
- 32 lakes, nine of them 30 cells or more (the largest 81 cells); ponds are single cells or pairs, none
	over four.
- The land is sorted in 36 steps of height: hills from step 21, peaks from step 28, the towns on plateaus
	at 15. Three ranges reach the top step (35): north of Roma, above Kalle and east of Gilead.
- Nothing stands on a town: no feature within 16 tiles of Midworld or 8 of any other town, and few within
	40 and 24.
- The sea is not on the map. The Shoals' water is lakes, ponds and pools; the open sea, the "lake beyond
	Endworld" and the mountains over it lie beyond the edge (world/overview.md). The map near the Endworld corner is
	hills; its big lakes lie along the south and west edges (71 cells at latitude -250 to -190, longitude -40 to 25;
	17 cells at latitude -10 to 20, longitude -250 to -235). See continuity.md.

## Lakes and ponds (Shallows)

Field `shallows`: water and lightning stronger, fire weak and unable to catch, everyone wading slowly.
"Knee-deep water over soft mud... The pearl divers of Bris wade out to the shell beds like this every day,
and they say a diver who is afraid of the water is the first to drown."

- Lake lines: wide grey water, reeds along the shore, a heron still in the shallows, silt clouding round
	your legs, a lake bed that sucks at the ankles; "every splash carries a long way over the lake".
- Pond lines: a dark pond among lily pads, dragonflies, frogs on the duckweed, mud at the rim and clear water
	in the middle, snail tracks on a stone, rushes thick around the rim.
- Where: the Thornbog is a fifth lake (the biggest, 81 cells, lies between Bris and Gilead; two more, of 71
	and 38 cells, lie in its southern tract), then the Shoals, the Greymoor (34 cells west of Narcissa) and
	the Weald (32 cells in the far north). The Diggings have none, the Ashlands and the Dry Country almost
	none. The Midlands have a few: 30 cells north-east of Roma, 35 tiles west of Midworld.
- Objects: Tide Pools in any Shallows (6%); Beehives in the Weald's lakes and ponds (see
	things/battlefield-objects.md).
- Who: Aqua Elemental (31), "a body of water that has come loose from its lake", in the deep pools below
	Hambry and the flooded mines past Gilead; Drakefin (8); Nymph (12), singing at pond edges; Leviathan
	(46), in "the deep water of the lake beyond Endworld", never rushing a boat that keeps still.
	Spells: Water Jet (drakefins, nymphs) and Deluge ("a wall of water comes off the lake all at once").

## Hills (Rough Ground)

Field `hills` (wind 1): earth and wind stronger, footing poor. "The stones clatter so that the whole hill
hears a fight... the shepherds of the downs say the man on the higher side has the better of it."

- Lines: an open slope of loose stones, a cairn on the crest and the wind pushing from one side, heather and
	gorse grey with lichen, a sheep trail worn by many feet, a hawk over the ridge; "from up here the road
	you walked looks very small".
- Where: the Copper Downs are over half hills and peaks; then the Diggings, the Ashlands ("the volcanic hills
	rise black and steep"), the Greymoor and the Shoals.
- Who: goblins on the ridges above Roma; Hellcat on the ledges between Roma and Bris; Drakemal in the caves
	near Bris; Beast in the far hills near Gilead; Ogre east of Gilead; the hill clans said to have forged the first
	Claymores; the forty men of Last Stand who held a road in a pass and are buried there.

## Peaks (High Peaks)

Field `peaks` (wind 2): frost, wind and lightning stronger, fire weaker, everyone short of breath and
unsteady. Peaks snow at any latitude (never in the Ashlands or the Dry Country, where it rains).
"Bare rock and ledges, with a drop on one side and the wind on the other... The herders of the passes beyond
Kalle climb with a rope."

- Lines: bare rock and scree in thin cold air, snow in the cracks, iron pegs driven into the rock, "a notch in
	the ridge... the only pass for miles", lichen in orange and grey, "one wrong step here is a long way down".
- Ranges: above Kalle (156 cells; the largest and one of the highest, "the passes above Kalle"); north of Roma
	(81 cells, "the cliffs north of Roma"); south of Midworld (53 cells); a range 55 tiles east of Gilead (11
	cells); a range on the north edge in the Ashlands (16 cells); smaller ones near Bris (about 30 tiles off),
	Hambry (22 tiles), north of Midworld (a peak 35 tiles off) and the south-east edge.
- Who: Blue Dragon (39), patient in the cold peaks above Kalle, breathing frost; Frost Wyrm (30), in the
	passes above Narcissa; Wyvern (33) on the cliffs above the Bris road; Sylph (15), leading climbers
	toward cliffs for fun; Aero Elemental (29), on the bare ridges east of Hambry; Dark Knight (43), on the
	high passes past Gilead; Giant (43) in the high valleys beyond it; Titan (50), who "sleeps in the
	mountains above Endworld" (beyond the edge: see continuity.md).
	Spells: Hail ("a winter on the hills above Hambry, where the stones fall the size of a thumb"), Whiteout.

## How near each town stands

Rough distances in tiles to the nearest cell of each kind (from the world's data); "-" means none within 75.

| Town | Hill | Peak | Lake | Pond |
|---|---|---|---|---|
| Midworld | 30 | 35 | 35 | 57 |
| Roma | 18 | 22 | 21 | 65 |
| Bris | 20 | 29 | 30 | 38 |
| Kalle | 16 | 21 | - | - |
| Narcissa | 35 | 60 | 45 | 22 |
| Hambry | 18 | 22 | 35 | 38 |
| Gilead | 16 | 22 | 63 | 54 |
| Endworld | 45 | 60 | - | - |
