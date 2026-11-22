---
id: monsters/elementals
summary: The elementals of fire, earth, wind and water: what shaped them, where they gather, and the weather each one calls.
related: [magic/elements, magic/mages, monsters/drakes-and-dragons, monsters/demons, things/battlefield-objects, world/weather-and-time]
sources: [app/content/monsters/fire.lua, app/content/monsters/flame.lua, app/content/monsters/blaze.lua, app/content/monsters/fira_elemental.lua, app/content/monsters/terra_elemental.lua, app/content/monsters/aero_elemental.lua, app/content/monsters/aqua_elemental.lua, continuity.md#where-monsters-live]
---

# Elementals

An element that has taken a shape and found a purpose. Seven are met, from level 24 to 34, all
past Roma's hills: four of fire, one each of earth, wind and water. Each is untouched by its own
element (Fire and Flame are immune to it; the rest absorb it, and your blows heal them) and has
its undoing: water and frost for the fire kin, wind for earth, earth for wind, lightning for
water. The Fira, Terra, Aero and Aqua Elementals cannot be hurt by the hurt spells (arcane
immunity: see `magic/elements.md`), so those are fights for steel and patience.

Most **call their own weather** (`world/weather-and-time.md` for the fields): the Aero
Elemental a thunderstorm, the Aqua Elemental rain, the fire kin heat.

## Fire

Fire is the old kind that starts in a ruined mill and ends in a town. Water and frost hurt it,
earth slows it, and a fire that has eaten a village is hard to put out. Its field is heat and
sun; fire elementals ward off burning, so a Fire Flask does nothing to them.

- **Fire** (`fire`, 24). Living flame that gathers in the ash fields near Endworld where old
	battles left the ground warm. It leaps from torch to thatch to tree with no sense of
	direction and grows when it is fed (it mends in the heat). Lights you with Ember, but not in
	the rain. Endworld scouts carry wet sacks as a matter of habit.
- **Flame** (`flame`, 28). The small mean sort that gets out of a forge or a burning barn and
	looks for dry thatch. Smiths in Bris keep a barrel of water by the door for them, and most
	of the time it is enough. They burn quickly and go out just as quickly, if you can hit them
	before they get started. Warms the field (Sunfire), lights you.
- **Blaze** (`blaze`, 31). The fire kin grown big and angry: a column of heat with a face that comes
	and goes in the smoke; seen working its way along the road from Roma to Bris. Warms the field,
	lays a Cinder Lash for double damage while you are at full life, keeps you burning (not in a
	downpour), rages under a third. Water helps, but a Blaze is rarely near enough to a well.
- **Fira Elemental** (`fira_elemental`, 34). A knot of living flame that gathers wherever a fire
	spell has been cast badly and left burning too long; drifts over the scorched ground near
	Narcissa and feeds on what still smoulders. Immune to the hurt spells and to sleep. Warms the
	field and keeps you burning; under two thirds it flares with a Hyper Beam (and must recharge a
	turn after); under a third a Fury. Bring steel, or boots and a long stick.

## Earth

- **Terra Elemental** (`terra_elemental`, 25). A knot of stone and earth given a will, usually by a
	mage who wanted a guard and got something worse. Lives in old quarries and mine galleries east
	of Bris. Turns the ground to mud (Mire), hardens under two thirds (Fend). Weak to wind.

## Wind

- **Aero Elemental** (`aero_elemental`, 29). A whirl of wind in the shape of a man bent over
	against a gale. Gathers on the bare ridges east of Hambry where the wind never stops, and comes
	down on a party that has stopped to rest. Calls a thunderstorm, and in the storm fires a Hyper
	Beam (and recharges a turn) and throws sparks. Weak to earth.

## Water

- **Aqua Elemental** (`aqua_elemental`, 31). A body of water that has come loose from its lake and
	found a purpose. Rises out of the deep pools below Hambry and the flooded mines past Gilead
	and can pull a grown man under before he shouts. Cold and clear; steel does better than any
	spell. Calls the rain, mends while it rains, weakens you, and douses a steam vent with a Water
	Jet (the scalding water is a drink to it) while you have more than 40 percent life. Weak to
	lightning.

## Notes for fighters

- The Terra Elemental's mud and the Aero Elemental's storm are both fields a Warrior or a Mage
	can answer with a field of their own (`magic/warriors.md`, `magic/mages.md`).
- Dragons and wyrms of the same element are in `monsters/drakes-and-dragons.md`; the Red Daemon
	is a fire spirit of the pits (`monsters/demons.md`).
