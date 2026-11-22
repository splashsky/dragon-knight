---
id: world/weather-and-time
summary: The two-hour day, the storms and the road they take from Midworld to Gilead, the climates of the ten lands, the snow lines, and what the weather fields say.
related: [world/overview, towns/midworld, towns/bris, towns/narcissa, towns/hambry, towns/gilead, towns/endworld, lands/storm-barrens, lands/ashlands, lands/dry-country, magic/elements]
sources: [app/lib/clock.lua, app/lib/weather.lua, app/lib/terrain.lua, app/lib/weather_lines.lua, app/content/fields/sun.lua, app/content/fields/heat.lua, app/content/fields/fog.lua, app/content/fields/rain.lua, app/content/fields/downpour.lua, app/content/fields/thunderstorm.lua, app/content/fields/snow.lua, app/content/fields/blizzard.lua, app/content/fields/mud.lua, app/content/fields/ice.lua, app/content/fields/night.lua, app/content/fields/gale.lua, app/content/items/storm_charm.lua, docs/plans/elements-and-weather.md, continuity.md]
---

# Weather and time

## The day

- The world keeps one clock, in ticks of ten seconds. A day lasts two real hours.
- Its four parts, in order: **dawn** 15 minutes, **day** 60 minutes, **dusk** 15 minutes,
	**night** 30 minutes (a quarter of the day).
- The weather moves on every tick. There are no seasons in the game's clock. Lore speaks of
	winters, springs and "every season of high winds" freely, and none of it is tied to a mechanic.
- What the parts do: fog is likelier at dawn, and at night in the moors, the bog, the shoals and the weald; heat comes
	only by day and only where it does not snow; night is the bandits' hour, when sleep takes hold
	deeper and shadow hits harder (`fields/night.lua`).

## What the sky and ground can be

- Sky: clear, sunny, heat, overcast, fog, drizzle, rain, downpour, thunderstorm, snow, blizzard.
- Ground: dry, wet, mud, snow on the ground, ice.
- The map is cut into cells ten tiles square. Each cell has a base sky from its land's climate
	and the time of day, held for about twenty minutes (cells staggered). Storms pass over it.

## The storms

- Every 45 minutes the world may make a storm: it forms 45 times in a hundred, about one storm
	every hundred minutes.
- It forms within 30 tiles of Midworld and travels toward Gilead (200, -200), north-west, with a
	slight wobble on its heading. The crossing takes about **two hours** (a tenth either way).
	Midworld, Bris and the Storm Barrens lie along its road. It grows in the first fifth of its
	life, holds, weakens after seven tenths and breaks over Gilead.
- Sizes: a squall (half of them, 8 to 14 tiles in radius), a storm (35 in a hundred, 16 to 26),
	a great storm (15 in a hundred, 30 to 40).
- Under a storm the rain goes by the distance from its centre: core, body, fringe, one step weaker
	each. A squall's core is a downpour; a storm's and a great storm's core is a thunderstorm.
	The steps are drizzle, rain, downpour, thunderstorm; in the cold north, snow, snow, blizzard,
	blizzard.
- A storm within about 40 tiles that is not overhead is "near": thunder or rain to the
	south-east, say.
- A storm's road is a line from Midworld to Gilead, and it forms within 30 tiles of the hub, so
	the south-east arm lies behind it: the edge of the widest storm never comes within about 70
	tiles of Kalle. No thunder, rain or lightning from a storm is met at Kalle or in the Diggings;
	its own sky is only fog, heat, drizzle, cloud, sun and clear (see `continuity.md`).
- After rain the road is **mud** for twenty minutes (times the land's mud factor). Where snow
	fell it lies for forty minutes, and the second half of that is ice.

## The climates

How each land leans the sky (the numbers are chances; the Midlands are the baseline):

| Land | Fog (dawn, night) | Heat by day | Drizzle | Overcast | Sun | Mud |
|---|---|---|---|---|---|---|
| Midlands | 4% | none | 6% | 20% | 35% | 1x |
| Copper Downs | 4% (dawn +10) | 5% | 10% | 22% | 35% | 1.5x |
| Salt Shoals | 6% (dawn +25, night +5) | none | 12% | 25% | 30% | 1.25x |
| Diggings | 4% | 4% | 4% | 15% | 45% | 0.8x |
| Greymoor | 6% (dawn +50, night +15) | none | 10% | 30% | 25% | 1.5x |
| Hambry Weald | 10% (dawn +20, night +5) | none | 10% | 30% | 25% | 1x |
| Storm Barrens | 6% (dawn +5) | none | 8% | 30% | 20% | 1x, storms a step harder |
| Ashlands | 2% | 60% | 2% | 10% | 30% | 0.5x |
| Dry Country | 2% | 45% | 2% | 8% | 45% | 0.4x |
| Thornbog | 12% (dawn +30, night +10) | none | 15% | 25% | 20% | 2x |

The lands themselves are in the chunks under `lands/`.

## Snow lines

- Falling weather is snow north of a land's snow line, and on any **peak** whatever its latitude.
- The line is latitude 150 in the Midlands, the Downs, the Shoals, the Diggings, the Greymoor and
	the Thornbog; latitude 100 in the Hambry Weald and the Storm Barrens (so Hambry at 170 and
	Gilead at 200 lie in the snow); and nowhere in the Ashlands and the Dry Country, which have
	rain instead, peaks included.
- The Storm Barrens rain a step harder: a squall's core there is a thunderstorm, and a storm
	may be a blizzard.

## Weather by town

- **Midworld**: sunshine, mild and mixed, and the place storms are born (`towns/midworld.md`).
- **Roma**: drizzle, cloud, dawn mist and mud that lasts; and an afternoon heat the people
	there blame on Endworld (`towns/roma.md`).
- **Bris**: sea mist at dawn, drizzle and the storms' road (`towns/bris.md`).
- **Kalle**: dry and bright, and no storm reaches it: they come no nearer than about 70 tiles (`towns/kalle.md`).
- **Narcissa**: fog off the low ground at dawn, about half the dawns (`towns/narcissa.md`).
- **Hambry**: snow, fog off the marsh-forest and ice on the north roads (`towns/hambry.md`).
- **Gilead**: the worst blizzards; the storms end here (`towns/gilead.md`).
- **Endworld**: heat for six days in ten, and no snow (`towns/endworld.md`).

## What the weather fields say

The weather also sets the battlefield (`magic/elements.md` has the numbers).

- **Sunshine**: "the weather most people in Midworld would pick". Fire and holy light burn a
	little hotter and shadows thin out. The Paladins pray on the chapel steps when the day is fine.
- **Heat**: "rolls in from the edge of the world in the afternoon and is gone again by dusk." Roma says
	it is what Endworld breathes out and shuts its shutters.
- **Fog**: comes off the low ground about Narcissa at dawn; carters wait at the crossroads and the
	innkeepers sell cheap ale to them. The bandits there call a morning fog the best business of
	the year.
- **Rain**: "the common weather of Roma and Bris"; farmers there would not know a dry year. The
	Mages of Roma keep Rain Call for the long summer days.
- **Downpour**: the heart of a squall; the carters of Bris say a wet road is worse than a long one.
- **Thunderstorm**: the heart of a storm; "storms form near Midworld and drift north-west toward
	Gilead in about two hours." A bolt picks its target at random.
- **Snow and blizzard**: snow falls on Hambry and Gilead for half the year, and the people have
	stopped complaining. Blizzards come out of the north in the cold months and Gilead gets the
	worst; the Hambry guards ring a bell at the gate on bad nights.
- **Mud**: the price of rain. The street children of Roma say the mud is theirs by right.
- **Ice**: forms on the north roads after the snow has lain; Hambry's old hands walk with their
	feet turned out.
- **Gale**: a Mage's wind on a clear day; the Mages of Hambry say it is the only part of the
	weather a man can hire.

## Weather and trade

The towns sell against their weather: storm charms and storm ward draughts in Kalle, Narcissa,
Hambry and Gilead, "the wardens there buy the charm before every season of high winds" (Kalle
sells them to those who go out to the storm road, not against its own sky); frost
charms and draughts toward Hambry; fire wards toward Endworld. See each town.
