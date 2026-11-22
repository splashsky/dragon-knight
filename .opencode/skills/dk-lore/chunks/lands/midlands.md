---
id: lands/midlands
summary: The Midlands, Midworld's farmland: hedgerows and stubble, no battlefield field, the weather's plain numbers, the first monsters, and no objects.
related: [towns/midworld, towns/roma, lands/copper-downs, lands/waters-and-heights, world/overview, world/weather-and-time, monsters/slimes, monsters/beasts, monsters/others, peoples/trades, peoples/roads-and-outlaws]
sources: [app/lib/terrain_lines.lua, app/lib/terrain.lua, app/lib/terrain/world.lua, app/lib/weather.lua, app/content/monsters/blue_slime.lua, app/content/monsters/critter.lua, app/content/monsters/troll.lua, app/content/items/herb.lua, app/content/items/sparrow_feather.lua, app/content/classes/warrior.lua, docs/plans/elements-and-weather.md, docs/plans/interactables.md, continuity.md#Decided]
---

# The Midlands

Soft farmland round Midworld. It is where everyone starts, and the game keeps it mild on
purpose: the weather's own numbers, no battlefield field, no objects. Everything else in
the world is harder than this.

## Where it lies

- Midworld (0, 0) sits in its middle. The main tract runs from latitude -120 to 85 and
	longitude -105 to 105, about 8% of the map, and is the one land that is almost all one
	piece (755 of its 829 cells).
- Two small outliers: a patch north-west of Midworld toward Bris (latitude 35 to 80,
	longitude -45 to -5) and a strip far west (latitude 15 to 35, longitude -130 to -110).
- Neighbours: the Copper Downs to the north and east (Roma, see lands/copper-downs.md), the Salt
	Shoals to the west (Bris, see lands/salt-shoals.md), the Greymoor to the south-west and the
	Diggings to the south-east (Kalle, see lands/diggings.md).
- Woods stand to the north of Midworld, where the Call Bear lore says a bear can be called out of the trees.
	They are timber, not the Weald's Woods field: the Midlands have no field on plain ground.
- Nothing but plain lies within 16 tiles of Midworld. Beyond that the land has hills (45 cells
	of its main tract), lakes (64) and a few peaks (6) like any other: the nearest are a hill and
	a peak about 30 and 35 tiles north of the town, and a lake 35 tiles to the west. See
	lands/waters-and-heights.md.

## Underfoot

Stubble fields and brown hedgerows run beside a rutted but firm road. Ditches run full of
cress, hawthorn lines the lanes, field gates stand open and the paths between them are worn
pale. The earth is soft and keeps a boot-print.

Sounds and sights the game uses: sparrows lifting off the stubble, a farm dog that barks and
gives up, a chimney smoking a mile off, a rook in an elm, a cow lowing unconcerned, a carter's
whistle, thatched roofs over the hedges. Edges read "hedgerows and quiet fields", "plough land
and stubble", "farm tracks between the hedges".

## Climate

The Midlands keep the weather's own numbers (see world/weather-and-time.md): fog 4%, drizzle 6%,
overcast 20%, sun 35% of what is left by day, a snow line at latitude 150 (so no snow in the
Midlands), mud lasting its plain 20 minutes. Sunshine "is the weather most people in Midworld
would pick". Storms form here, within 30 tiles of Midworld, and leave it for Gilead.

## The battlefield

No terrain field on plain ground. A hill, a lake or a peak inside the Midlands brings its own
field (Rough Ground, Shallows, High Peaks); see lands/waters-and-heights.md. The calm place the
tests fight at, near (-3, 3), is plain Midlands.

## Objects

None. Objects never appear in the Midlands, nor within 12 tiles of Midworld; see
things/battlefield-objects.md.

## Monsters and levels

Levels grow with distance from Midworld, not with the land: level 1 at the town, and across
the Midlands' main tract the band runs from level 1 to about 25 (half its cells are level 14
or under). Roma's band is 5 to 7.

What the lore puts on these roads (families in monsters/slimes.md, monsters/beasts.md and
monsters/others.md):

- Blue Slime (1), hopping along the roads near Midworld; Red Slime (1), in damp cellars and
	ditches around it. The Warrior's lore: "the slimes are many and the inns are few".
- Critter (1), nesting in the hedgerows (farmers set traps, a pelt sells at the market);
	Creature (2), a shaggy thing in the scrub past the Midworld road, named by a blank box on a
	guard's report.
- Scamp (4), a mischievous imp of the woods and fields; Raven (4), on the dead trees along the
	road beyond Midworld.
- Shadow (2), at dusk along the old walls of Midworld; Ghost (6), of someone who died on the
	road between Midworld and Kalle, in old graveyards and ruined inns.
- Drake (2), a small scaled lizard on the hills between Midworld and Roma; Troll (17), under the
	bridges and along the old road between Midworld and Roma.

Lore homes and level bands do not always agree (a level 17 troll on a 42-tile road). The
mechanics win and the lore stays; see continuity.md#where-monsters-live.

## People

Farmers and their children, tanners, tailors, carters and shopkeepers: see peoples/trades.md.
Training yards in Midworld teach Cleave and the Mage's towers teach the first spells (see
towns/midworld.md). Roads and who walks them: peoples/roads-and-outlaws.md.

## From the land

- Herb: bitter green leaf that "grows wild along the roads around Midworld"; every shopkeeper
	sells it.
- Life Pebble and Magic Pebble: small stones left by vermin near Midworld (the lore says rats,
	and "wisps and bats"; no such monster has a file).
- Sparrow Feather: lies in the stubble fields after the harvest; boys who want to be runners
	collect them.
- Fortune Drop: a holed copper coin dropped by cutpurses on the roads near Midworld.
- Wolf Fang: a grey wolf out of the hills that took three sheep; farmers on the Midworld road
	hang the fangs by the door.
- Sticks, branches and clubs are cut from the hedges.
