---
id: monsters/drakes-and-dragons
summary: Drakes, wyrms, wyverns and the six dragons: where each kind lairs, what it fears, and the tell before its breath or dive.
related: [monsters/elementals, magic/elements, magic/afflictions, things/legendary-sets, legends/upper-echelon, world/overview, monsters/beasts]
sources: [app/content/monsters/drake.lua, app/content/monsters/drakelor.lua, app/content/monsters/drakemal.lua, app/content/monsters/drakefin.lua, app/content/monsters/wyrm.lua, app/content/monsters/frost_wyrm.lua, app/content/monsters/fire_wyrm.lua, app/content/monsters/lesser_wyvern.lua, app/content/monsters/wyvern.lua, app/content/monsters/greater_wyvern.lua, app/content/monsters/greatest_wyvern.lua, app/content/monsters/green_dragon.lua, app/content/monsters/blue_dragon.lua, app/content/monsters/red_dragon.lua, app/content/monsters/shadow_dragon.lua, app/content/monsters/dark_dragon.lua, app/content/monsters/black_dragon.lua, app/content/spells/fire_breath.lua, app/content/spells/heavy_blow.lua, app/content/statuses/charging.lua, continuity.md#where-monsters-live]
---

# Drakes, wyrms, wyverns and dragons

Four lines of one family, grown by size and by the weather they favour. The drakes are the
first dragon kin a hero meets and the first to be mistaken for the real thing; the wyrms are
dragons that never grew up; the wyverns have no fire, only a tail; the dragons keep hoards,
names and grudges. Levels are met by distance (see `world/overview.md`): drakes near Midworld
and Roma, wyrms and wyverns from level 28, dragons from level 36.

## How they fight

Everything in the family that breathes or dives **gathers first**. The breath spells (Fire,
Frost, Venom and Shadow Breath: see `magic/elements.md`) draw a breath for one turn (the
status Charging, `magic/afflictions.md`), then land on every foe on the field. The dive of
the wyverns and the Heavy Blow of the knights work the same way. The tell is one whole turn
long; carters say the snow goes quiet just before the frost breath, and wardens say nobody
argues about how long the warning took.

Weather bends the rhythm. Fire kin breathe sooner in heat and sun and later in rain; frost
kin sooner in snow and later in heat; the green dragon sooner in fog; shadow kin sooner in
the dark. The wyverns will not dive in rain, storm or snow.

## Drakes

- **Drake** (`drake`, 2). A small scaled lizard with a bad temper and a taste for sheep, on
	the hills between Midworld and Roma. Cold-blooded: weak to frost. Its hide makes plain
	leather armor that keeps out the wind, if not much else.
- **Drakelor** (`drakelor`, 3). An older, sly drake on the road between Roma and Bris, dull
	grey-green and seen only when it bites. Poison sometimes fails to take on it. Bris guards
	pay a bounty for its claws, which are sharp enough to serve as needles.
- **Drakemal** (`drakemal`, 6). Big, heavy, rough black hide. Guards the caves in the hills
	near Bris and will follow a hero a mile. Gathers a fire breath every third turn: smoky and
	short, but it singes a cloak. Resists fire, weak to frost.
- **Drakefin** (`drakefin`, 8). A drake with long fins, quick in water, in the river marshes
	near Hambry. Fires a jet of water every other turn, and bites between. Fishers say it
	takes a line when hungry and rarely lets go. Resists water, weak to lightning.

## Wyrms

Dragons that never grew up: long, thin, small wings that cannot lift them.

- **Wyrm** (`wyrm`, 28). Lives in the caves under the cliffs north of Roma. Its breath is
	smoke, which blinds for a minute: it raises a fog, then saps your strength and throws Pain
	through it. Resists fire and frost a little.
- **Frost Wyrm** (`frost_wyrm`, 30). The colour of old ice, in the high snow; hunts the passes
	above Narcissa in deep winter and freezes its prey where it stands. Makes snow (Cold
	Snap), breathes frost on its 3rd, 7th, 11th turns, mends in the snow and numbs with
	Frostbite. Immune to frost, weak to fire. The snow around its lair never fully melts.
- **Fire Wyrm** (`fire_wyrm`, 32). A belly that glows like a forge through its scales; nests
	in the lava vents under the hills by Endworld and comes up at night to burn the
	grazing land. Heats the field (Sunfire), breathes fire on its 3rd, 7th, 11th turns, keeps
	you burning, rages at night and goes into a Fury under a third of its life. Immune to
	fire, weak to frost and water. Its fire melts plate; the wise go in with a plan to get out.

## Wyverns

Two-legged dragon kin with a barbed tail and no fire. Resist wind and poison, weak to
lightning, and ward off poison and venom in part.

- **Lesser Wyvern** (`lesser_wyvern`, 32). Hunts the open plains between Bris and Kalle,
	swooping on herds and the carts behind them. Keep the horses under a roof and your head down.
- **Wyvern** (`wyvern`, 33). Nests on the cliffs above the road between Bris and Kalle and
	hunts a cart a whole day to get at the horses. Climbs out of reach on its 3rd, 7th, 11th
	turns and plunges the next (the dive of Heavy Blow); stings with Venom. Carters paint
	their wagons with pitch, which the wyverns hate and which does not always work.
- **Greater Wyvern** (`greater_wyvern`, 34). Fat on the sheep of the high pastures past
	Hambry; shepherds count flocks twice a day and carry a bell. It waits out of sight on its
	first turn and dives the next; again every third turn, every second under half life.
- **Greatest Wyvern** (`greatest_wyvern`, 37). The eldest, copper-coloured, wings wider than
	the road is long; has outlived three generations of cart-drivers on the road past Gilead.
	Hunts only from the high ridges, so a party that reaches the ridge road is half through the
	fight. Its sting is poison.

## Dragons

They sleep on hoards, collect names, and wake slowly. Each has one breath and one weather
that feeds it.

- **Green Dragon** (`green_dragon`, 36). Lairs in the marsh-forest beyond Hambry, where the
	fog hides it until it is overhead. Venom breath on every 4th turn, every 3rd in fog: a sour
	cloud that clings to armor and lungs. Immune to poison, weak to fire. Hunters say it takes
	only the gold it is owed.
- **Blue Dragon** (`blue_dragon`, 39). High in the cold peaks above Kalle, where snow lies half
	the year. Patient; hunts the passes like a judge hunts debtors. Frost breath every 4th
	turn, every 3rd in snow, every 5th in heat or sun; the cold numbs your arms. Resists
	frost, weak to fire.
- **Red Dragon** (`red_dragon`, 41). Sleeps on a hoard beneath the mountains past Endworld and
	has never shared a coin. Fire breath every 4th turn, every 3rd under half life or in heat,
	every 5th in rain; goes into a Fury under a quarter of its life. Its fire melts plate and
	runs down the cave walls in streams. Resists fire, weak to frost and water.

The three below are of the upper echelon (see `legends/upper-echelon.md`).

- **Shadow Dragon** (`shadow_dragon`, 44). Hunts in the hours after dusk when the roads
	outside Narcissa empty and the watchmen light no lamps. Brings the night on its first turn;
	shadow breath every 4th turn, every 3rd in the dark or under half. Its scales drink light:
	a torch shows only where it has been. Few see it clearly; most remember the cold wind
	before the bite. Resists shadow, weak to holy.
- **Dark Dragon** (`dark_dragon`, 45). Sleeps in a mountain under Hambry and wakes about once a
	generation. It does not care for gold: it collects names, and knows every name of everyone
	who came looking. Saps your strength early ("your name grows fainter"), breathes shadow,
	and drains you under half life. Immune to shadow and the hurt spells; withering fails on it.
- **Black Dragon** (`black_dragon`, 47). The oldest dragon the road-wardens know, over the
	marshes beyond Narcissa since before the towns were walled. Fouls the field with miasma,
	then breathes venom. Its breath eats steel faster than fire melts it. Wardens say it leaves
	a traveller alone if he leaves something shiny. Immune to poison and the hurt spells.

## What they leave

Dragon's Claw, Scale, Tooth, Plate, Tear and Wing are drops (`things/legendary-sets.md`); the
Dragonhide Shield is cut from the hide of a hillside beast, and few hunters can afford to bring
a dragon back whole (`things/gear.md`).
