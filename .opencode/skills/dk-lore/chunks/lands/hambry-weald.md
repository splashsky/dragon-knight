---
id: lands/hambry-weald
summary: The Hambry Weald: close forest in the north-east, moss and bear sign, honey and woodcutters, fog off the marsh-forest, snow half the year, beehives.
related: [towns/hambry, towns/roma, lands/greymoor, lands/thornbog, lands/storm-barrens, lands/waters-and-heights, things/battlefield-objects, peoples/trades, peoples/roads-and-outlaws, monsters/beasts, monsters/drakes-and-dragons, monsters/elementals, monsters/undead, monsters/people, monsters/demons]
sources: [app/lib/terrain_lines.lua, app/lib/terrain.lua, app/lib/terrain/world.lua, app/lib/weather.lua, app/content/interactables/beehive.lua, app/content/fields/forest.lua, app/content/fields/snow.lua, app/content/fields/ice.lua, app/content/fields/blizzard.lua, app/content/monsters/grey_bear.lua, app/content/monsters/green_dragon.lua, app/content/monsters/aero_elemental.lua, app/content/monsters/advocate.lua, app/content/spells/fog_bank.lua, app/content/items/emerald.lua, docs/plans/elements-and-weather.md, continuity.md#Decided]
---

# The Hambry Weald

The north-east's forest, the largest land on the map. Close trees and moss, honey in the
branches, a marsh-forest where fog hides dragons, and snow on the high ground for half the year.
Hambry stands at its heart with its hall of pleaders, its abbey and its smiths.

## Where it lies

- Hambry (170, 170) is the far north-east town. The home tract is 653 cells (latitude 50 to 250,
	longitude 35 to 250). The Weald is the largest land (1,459 cells, about 14.3% of the map) because
	it also lies in several outlying tracts of like climate:
	- 196 cells between Roma and Hambry (latitude 50 to 130, longitude 60 to 185): flat, with
		thirteen ponds and hardly a hill;
	- 198 cells in the south-west between Midworld and Narcissa (latitude -205 to -125, longitude
		-175 to -60);
	- smaller stands in the far north-west near Gilead, east of Gilead, and on the west edge.
- Features in the whole land: 148 hill cells, 73 lake cells (a lake of 32 cells lies in the north,
	latitude 220 to 240, longitude 35 to 95), 35 pond cells and 19 peak cells. The ponds and lakes are
	the "deep pools below Hambry"; the rivers of the lore (river marshes near Hambry) are not drawn:
	see continuity.md. See lands/waters-and-heights.md.
- Neighbours: five patches of the Greymoor lie in and about it (Hambry's "high pastures", "grey
	hills" and "bare ridges": see lands/greymoor.md) and stands of the Storm Barrens (see
	lands/storm-barrens.md); the Thornbog lies to the south-east (the "marsh-forest"); the Dry
	Country lies to the west of the home tract, with the Barrens beyond it.

## Underfoot

Close grey-green forest, moss on every trunk, branches meeting overhead so that the light comes
down green. Roots as thick as an arm cross the path and the ground between them is soft; fallen
logs rot with mushrooms on them; bear sign scores the bark; a woodcutter's marks show on a stump
and the cut wood is stacked by the road. Leaves drift down, a branch catches at an elbow, wolves
call "somewhere further off than you would like". Snow lies on the branches in winter.

Fights open in a clearing ringed by dark trees, down a deer path, beside a fallen oak, from a branch
overhead, up through the bracken. Edges read "the dark eaves of the Weald", "Hambry's forest road runs
through the trees", "the ground falls away toward the river marshes", "close trees wall off everything".

## Climate

More fog (10%, plus 20% at dawn and 5% at night), drizzle 10%, overcast 30%, sun 25%. The snow
line is latitude 100, so most of the home tract snows rather than rains, and the peaks snow at any
latitude. "Snow falls on Hambry and Gilead for half the year, and the people there have stopped
complaining about it." Ice forms on the north roads once the snow has lain and the thaw has come
and gone; Hambry's old hands walk with their feet turned out. In a blizzard the guards ring a bell
at the gate so the lost can find the road. "Fog comes off the marsh beyond Hambry the way steam
comes off a kettle." See world/weather-and-time.md.

## The battlefield

Woods (field `forest`) on plain ground: wind and lightning weaker under the cover, fire stronger
and burning hotter in the timber, a trunk to dodge behind. "Hunters of the Weald move from trunk to
trunk and keep a tree between themselves and any open ground. They say the forest is kind to
anyone who knows where the roots lie." A hill, peak, pond or lake takes its own field instead.

## Objects

- Beehive: a straw skep in the branches. Bees are out in sun or heat and in at night, in rain and in
	snow, so it appears 18% of the time on plain ground under sun or heat, 12% under any Woods
	field, 9% in sunny hills and shallows, 6% otherwise, and never at night or in wet weather.
	"Honey is the oldest trade in the Weald": the honey-cutters of Hambry walk under the skeps each
	morning with a smoking pot on a string. A knocked-down hive swarms whoever stood under it. Fire
	smokes the bees off. Bears knock them over (see things/battlefield-objects.md).
- Dead Tree: at the Weald's edges, 25% in a gale.

## Monsters and levels

Hambry's band is 33 to 35; across the home tract levels run from 27 to 51 (the median is 44).
Lore homes (families in monsters/beasts.md, monsters/drakes-and-dragons.md,
monsters/elementals.md, monsters/undead.md, monsters/people.md and monsters/demons.md):

- Beasts: Grey Bear (21), in the northern forests past Hambry; Large Beast (27) down from the high
	ground in hard winters; Nymph (12), singing at the pond edges.
- Dragon kin: Drakefin (8), in the river marshes near Hambry; Green Dragon (36), in the marsh-forest
	beyond it; Greater Wyvern (34), on the high pastures; Dark Dragon (45), asleep in a mountain
	under Hambry.
- Wind and water: Aero Elemental (29), on the bare ridges east of Hambry; Sylph (15) in the passes
	beyond it; Aqua Elemental (31), in the deep pools below Hambry.
- The dead: Haunt (22), at a ruined inn or manor outside Hambry; Fright (25), in abandoned mills;
	Ultrawraith (26), in ruined churches and toll houses beyond it; Ultradoomer (36), in the dead hall
	beneath the Hambry road.
- Mines and pits: Dawkin (21), in the mines beyond Hambry; Hellion (16) from the fire pits beyond it;
	Hellbeast (22), bred in the fire pits under it by the cult that runs them.
- Silver Scorpion (40) under the dunes beyond Hambry (see lands/dry-country.md).
- The pleaders' hall and its followers: Advocate (35), Fanatic (36), Obsessive (40), Zealot (38).
	Rogue (8) works the Hambry road; the Traitor (45) is a captain of the Hambry garrison who sold the
	gate keys.

## People

Honey-cutters, woodcutters, hunters and trappers, shepherds on the high pastures, smiths, the watch
guild, guards, surgeons, the abbey, the temple, herbalists, mages, minstrels. See peoples/trades.md.
Roads and inns: peoples/roads-and-outlaws.md.

## From the land

- Emerald: heavy green stone from the deep workings past Hambry; porters wear them to shift loads.
- Hawk Eye: a lens from a trader of Hambry who hunted "the grey hills".
- Ogre-hide Cuirass: trophies traded by hunters in the hills near Hambry.
- Sage's Lens: ground by a monk in the hills above Hambry, sold at cost.
- Angel's Rise: a golden feather left where a guardian fell in the hills past Hambry.
- Dragon's Plate: from "the scorched road past Hambry".
- Cure-All, from the abbey's cellars, first made for monks who came back from the marsh.
