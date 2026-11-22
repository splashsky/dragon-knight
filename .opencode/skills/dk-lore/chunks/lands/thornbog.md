---
id: lands/thornbog
summary: The Thornbog, the wild bog-land: black water, reeds and thornwood, stilt-huts and hags, the wettest ground, gas pockets, and the old marsh dragons.
related: [towns/kalle, towns/gilead, towns/narcissa, lands/diggings, lands/storm-barrens, lands/salt-shoals, lands/hambry-weald, lands/waters-and-heights, things/battlefield-objects, things/legendary-sets, peoples/trades, monsters/drakes-and-dragons, monsters/fey-and-spirits, monsters/others]
sources: [app/lib/terrain_lines.lua, app/lib/terrain.lua, app/lib/terrain/world.lua, app/lib/weather.lua, app/content/interactables/gas_pocket.lua, app/content/fields/marsh.lua, app/content/monsters/bog_witch.lua, app/content/monsters/behemoth.lua, app/content/monsters/black_dragon.lua, app/content/monsters/green_dragon.lua, app/content/monsters/drakefin.lua, app/content/items/thornwood_bark.lua, app/content/items/thornwood_root.lua, app/content/items/thornwood_heart.lua, app/content/items/thornwood_thorn.lua, docs/plans/elements-and-weather.md, continuity.md#Decided]
---

# The Thornbog

A wild land with no town: reed-beds and black water under a hum of flies, thornwood in thick grey
thickets, stilt-huts out over the bog. It is the wettest ground on the map, a fifth of it open water, and
every step in it is slow.

## Where it lies

- Four seeds (latitude, longitude) sit in the gaps between the towns' lands: (-235, -20), (120, -150),
	(-40, 235) and (80, 190). The land is 919 cells (9.0% of the map), in tracts:
	- east (351 cells; latitude -110 to 85, longitude 160 to 250), with 25 lake cells and 15 ponds: the
		"marshes near Kalle";
	- south (289 cells; latitude -250 to -145, longitude -75 to 70), with a lake of 71 cells and another of 38:
		"the bog below Kalle";
	- north-west (139 cells; latitude 110 to 170, longitude -145 to -60), round the biggest lake on the map (81
		cells), between Bris and Gilead: Gilead's "thornwood bog" and "the marshes beyond Gilead";
	- smaller tracts on the north-west edge (latitude 85 to 105, longitude -240 to -195) and the south edge.
- Lakes are a fifth of its cells (200 lake cells, 25 pond cells, 56 hill cells, no peaks). See
	lands/waters-and-heights.md.
- Neighbours: the Diggings and the Dry Country in the south-east, the Salt Shoals and the Barrens in the
	north-west, the Weald in the north-east (see lands/diggings.md, lands/salt-shoals.md,
	lands/storm-barrens.md, lands/hambry-weald.md).
- Rivers, "river marshes" and "river gravel" appear in the lore but are not drawn: see continuity.md.

## Underfoot

Black water and reed-beds stretch away under a hum of flies. Thornwood spines "as long as a finger" snag
at the sleeves; thornwood bushes grow in thick clumps with their roots in the water; a stilt-hut stands
out in the bog with a green pot steaming on its porch; dead reeds stand in the pools like broken spears;
bubbles rise through the black water and burst. The bog sucks at boots, the frogs have gone quiet, thorns
tear a cloak, and "the ground ahead looks firm, and then it is not".

Fights open among the reeds, knee-deep in the bog, through a parted thicket, from under a mat of
duckweed, beside a stilt-hut's ladder. Edges read "the ground turns soft and rotten", "the thornwood
grows in dense grey thickets", "hags' huts and old fences lie in the reeds".

## Climate

Fog sits in the hollows: 12%, 30% more at dawn and 10% more at night. Drizzle 15%, overcast 25%, sun
20% by day, and mud that lasts twice as long as in the Midlands (40 minutes). The snow line is the
usual latitude 150. See world/weather-and-time.md.

## The battlefield

Marsh (field `marsh`): poison and earth stronger, poisons biting deeper, fire weak and burning out sooner,
everyone slogging. "The people who live on the Thornbog say the bog takes what it likes, and it likes
whatever is slow. Stilt-hut folk test each step with a long pole before they put a foot down." A torch "is no
friend in the reeds". Lakes and ponds bring Shallows instead.

## Objects

- Gas Pocket: a bubble of marsh gas swelling under the peat. 12% of fights, 20% in fog or at night. It bursts
	by itself after a minute: a spark makes it flash (burning on everyone), anything else makes it burst
	(poison on everyone, and miasma over the field). Locals call them bog-bubbles and say the marsh breathes
	out through them; stilt-hut children are told to run when one quivers and not to look back. The Bog
	Witch bursts them on you.
- Dead Tree: in a gale, 25%.
See things/battlefield-objects.md.

## Monsters and levels

Levels run from 23 to 51 over the three main tracts (medians 28 to 45). Lore homes (families in
monsters/drakes-and-dragons.md, monsters/fey-and-spirits.md and monsters/others.md):

- Bog Witch (9), a hag who keeps a hut on stilts and stirs a green pot; folk leave a loaf on the path for
	her. She is never met at random.
- Drakefin (8), fast in water, taking a line "and rarely lets go"; Nymph (12), singing from the pond edge.
- Behemoth (48), "a beast of the old marshes, the size of a barn", leaving a flattened road from one ruined
	village to the next.
- Black Dragon (47), seen over "the marshes beyond Narcissa" since before the towns were walled; Green
	Dragon (36), in the marsh-forest beyond Hambry, where the fog hides it.
- Illusion (5), in "the mists of the marshes past Roma".
- Swamp tortoises and marsh hornets are named by the lore but have no monster files.

## People

Stilt-hut folk, bog priests, woodcutters who strip the bark, hags. See peoples/trades.md.

## From the land

- Thornwood Bark: from the bog below Kalle, "where the trees put out spines to keep the bears off";
	dries hard enough to stop a club.
- Thornwood Thorn: the longest spines, high up where the bears and woodcutters do not go.
- Thornwood Root: runs a mile under the bog; the Mages' guild buys every one; the folk of Gilead say
	the first one dug up was a hand.
- Thornwood Heart: found only in trees three hundred years old; bog priests in Gilead carve them into charms.
	These four make the Thornwood set (things/legendary-sets.md).
- Lucky Charm: a four-leaf clover "from a field only she knows", sunk in the marshes near Kalle.
- Tortoise Shell (a swamp tortoise), Hornet Sting (a marsh hornet), Dragon's Wing (a dragon brought down
	over the marshes beyond Gilead), Cure-All (first made for monks who came back from the marsh).
