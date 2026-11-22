---
id: magic/elements
summary: The eleven kinds of harm (physical, fire, frost, lightning, water, wind, earth, holy, shadow, arcane, poison): what each is in the world, its spells and gear, its weather, who fears it.
related: [magic/mages, magic/paladins, magic/warriors, magic/afflictions, monsters/others, monsters/elementals, things/gear, things/consumables, world/weather-and-time]
sources: [app/lib/elements.lua, docs/plans/elements-and-weather.md, app/content/fields/brimstone.lua, app/content/fields/miasma.lua, app/content/fields/consecrated.lua, app/content/spells/hurt.lua, app/content/spells/inferno.lua, app/content/spells/frostbite.lua, app/content/spells/spark.lua, app/content/spells/dawnstrike.lua, app/content/items/ember_ring.lua, app/content/items/halo_charm.lua, app/content/items/shade_charm.lua, app/content/items/serpent_ring.lua]
---

# The elements

Every blow has a kind. The world knows eleven, and every monster, shield and field has views
on them. A creature resists a kind by some percent; below nothing it is weak to it; at 100 it
is immune; above 100 it drinks the harm and is healed (an elemental in its own element). A
**ward** is a separate thing: the chance that a state (sleep, poison, burning) does not take hold
(`magic/afflictions.md`).

Weather and ground change the kinds: fire gutters in the rain, frost bites harder in snow
(`world/weather-and-time.md`; the lands' own ground is in `lands/waters-and-heights.md`).

## The eleven

- **Physical.** Steel, clubs and claws: every weapon unless it says otherwise, and the warrior's
	strikes. Wraiths and phantoms resist half of it; the fey (nymph, sylph, nisse) take extra
	from iron. Mud and ice and the Warrior's Mire (`magic/warriors.md`) are about footing, not
	this.
- **Fire.** Forges, kilns, foundries, torches. Ember, Scorch and Inferno burn a target for ticks;
	Cinder Lash and the Fire Breath hit at once; Solar Beam gathers light into fire. Fire Flasks,
	the Cinder Blade, the Ember Staff are its gear. Heat, sun, brimstone, cinders and the woods feed
	it; rain, snow, shallows and storms put it out. Resisted by fire kin, devils, hellhounds and
	red slimes; feared by trolls, ghouls, scorpions, nightshade, the dead and the frost-bound.
	Guards: Ember Ring, Flame Charm, Fire Ward, Fire Ward Draught, the Cinder Shield (at a cost
	in frost).
- **Frost.** Snow, ice, the cold passes and the deep ice pits under Kalle. Frostbite (and the
	Frost Staff and Frost Fang), Hail, Whiteout, Frost Breath. Snow, blizzard, ice and peaks feed
	it; heat and brimstone weaken it. Frost can numb a target to sleep. Resisted by frost ravens
	and wyrms, blue dragons, bears; feared by fire kin, hellhounds, drakes and the Demon King.
	Guards: Rime Ring, Frost Charm, Frost Ward, Frost Ward Draught, the Rimefur Coat (at a cost in fire).
- **Lightning.** The storms that form near Midworld and drift toward Gilead; open ground where it
	falls. Spark, Thunderbolt, Lightning Lance (and the Spark Rod, Storm Lance). Rain, downpour,
	thunderstorm, shallows and peaks strengthen it; a thunderstorm strikes at random. Feared by wet
	things (slimes, drakefins, aquatic kin, the silver ones), ravens, wyverns, giants, knights in
	plate. Guards: Spark Ring, Storm Charm, Storm Ward, Storm Ward Draught.
- **Water.** Rain, shoals, lakes, the divers' pearl beds. Torrent, Water Jet, Deluge. It puts out fire and
	leaves a target Soaked (more lightning, less fire). Resisted by slimes, drakefins, nymphs and
	aqua elementals; the leviathan drinks it; fire kin fear it.
- **Wind.** Ridges, passes, gales. Gust, Cyclone, Gale. Gale, peaks, hills and sand strengthen it;
	woods turn it. Wyverns, ravens, sylphs and aero elementals ride it (aero elementals drink it);
	earth kin fear it.
- **Earth.** Rockfall, Mire, mud, hills, the rock of quarries and mines. Resisted by trolls, dawks,
	giants, titans, colossi; the terra elemental drinks it; wind and lightning undo them.
- **Holy.** Dawnstrike, Judgement, Radiance, the Blessed Mace and the Dawn Mace, the temples and the
	oaths of Paladins (`magic/paladins.md`). Strong in sunshine and on consecrated ground; thinned
	by night, brimstone and miasma. Everything dead, devilish or lycan is weak to it; "silver" is
	holy in the old tongue. Guard: the Halo Charm.
- **Shadow.** Night, crypts, the cold under the north ice. Withering and Curse, Doom, the Shadow
	Breath, the bites of ghosts and wraiths. Strong at night and in miasma; weak on consecrated
	ground. Resisted by the dead, shades and the dark dragons; light and holy hurt them.
	Guard: the Shade Charm.
- **Arcane.** The mages' raw force: Hurt, Pain, Maim, Rend, Chaos, Magic Bolt, Hyper Beam, Sap Mind,
	Starfall. It ignores armor. Shades, shadows, figments, illusions, mirages, daemons and
	the great dragons are **immune to the hurt spells**; elementals of earth, wind and water too.
- **Poison.** Bog, miasma, the apothecaries' back shelves. Poison, Venom, Plague, Venom Breath, Acid
	Vial. Marsh and miasma deepen it. Scorpions, nightshade and the green dragon turn it back; the
	dead do not feel it. Guards: Serpent Ring, Viper Charm, Antidote.

## Auras

Three fields are **auras**, the mark of a kind of creature, and a new one drives out the old:

- **Brimstone**: the demon lords' sulphur (fire +30, frost -30, holy weaker).
- **Miasma**: the liches' grave-fog (poison and shadow stronger, holy weaker, poisons bite half again as hard).
- **Consecrated ground**: the Paladin's blessing (holy +25, shadow -25). It clears the other two.

## What monsters know

A monster's file says what it resists, fears or drinks, and what it wards off. The families'
chunks give these in words; `monsters/others.md` has the rules they all share.
