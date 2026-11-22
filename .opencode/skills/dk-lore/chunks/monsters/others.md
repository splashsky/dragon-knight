---
id: monsters/others
summary: The monsters of the sea beyond Endworld, and the rules every monster family shares: where levels are met, resistances, tells, who never roams.
related: [monsters/slimes, monsters/drakes-and-dragons, monsters/undead, monsters/demons, monsters/beasts, monsters/elementals, monsters/fey-and-spirits, monsters/giants, monsters/people, magic/elements, magic/afflictions, world/overview, legends/upper-echelon]
sources: [app/content/monsters/leviathan.lua, app/content/monsters/siren.lua, app/lib/monsters.lua, app/fight/combat.lua, docs/plans/elements-and-weather.md, continuity.md#where-monsters-live]
---

# Other monsters, and what all monsters share

## The sea beyond Endworld

The land ends at Endworld; its sea, its lake and its mountains lie past the map's edge. Two
things are told of the water, both of the upper echelon (`legends/upper-echelon.md`).

- **Leviathan** (`leviathan`, 46). Lives in the deep water of the lake beyond Endworld; its back is
	sometimes taken for an island. Boatmen who pass over it at night leave a lantern in the bow and
	do not look down. It rises only when something disturbs the water, and has never once rushed a
	boat that kept still. In a fight the lake rises: a downpour on its 1st, 5th, 9th turn, and under
	half life it mends in the deep. Absorbs water; weak to lightning; cannot be burned.
- **Siren** (`siren`, 50). Sings from the rocks of the sea-coast beyond Endworld, and sailors who
	hear her row toward the sound. Immune to the hurt and sleep spells, so the fight is fought with
	steel: she has few hit points (68) but armor 800 and a blow of 400. Her verse is a Sleep on every
	even turn and a blow on every odd one. It is never quite the same twice; "those who survive say
	she only ever sang one verse, and it was about them."

## Where levels are met

A monster is met by its level, not by its home. A level L monster turns up from 5L-5 to 5L+9 tiles
from Midworld in any direction (the player's furthest axis, latitude or longitude), three levels
at a time (`world/overview.md`). The towns lie on those rings: Midworld 0, Roma 30, Bris 70, Kalle
100, Narcissa 130, Hambry 170, Gilead 200, Endworld 250. The places a monster's lore names say
where its kind is told of; they are not a map of the encounters
(`continuity.md#where-monsters-live`). New lore should name a town whose ring fits the level.

Three monsters are never met on the road: the **Goblin Shaman**, the **Bandit Captain** and the
**Bog Witch** keep their places, and appear only where content puts them
(`monsters/people.md`).

Levels 42 and up speak and are told of in a grander voice (`legends/upper-echelon.md`); everything
else is ordinary life.

## Natures

- **Resist, weak, absorb.** Every monster resists or fears some elements (`magic/elements.md`).
	Immune to arcane means immune to the hurt spells (Hurt, Pain, Maim, Rend, Chaos, Magic Bolt,
	Hyper Beam, Starfall, Sap Mind); the dead, the shapes and the elementals mostly are.
- **Wards.** A ward is a chance that a status does not take (sleep, poison, venom, burning,
	weakening, withering). The dead and the dread are warded against sleep and poison; fire kin
	against burning (`magic/afflictions.md`).
- **Holy and silver.** Everything dead, devilish or lycan is weak to holy light. Silver hurts them
	because it is, in the old tongue, holy light ("silver, in the old tongue", says the Werewolf's file).

## Tells

A monster that does a big thing says so a turn before:

- **Charging**: breaths and dives (`monsters/drakes-and-dragons.md`), the knights' Heavy Blow,
	the Titan's stomp, the Black Daemon's blow.
- **Phases**: bosses change at fractions of their life: two thirds, half, a third, a quarter
	(the Demon King, the Liche King, Lucifuge, the Dark Knight).
- **Weather**: dragons and wyrms breathe sooner in the weather that feeds them.
- **Counts**: doomers name a time; the Siren sings on even turns; the Liche Master takes
	elements in order.

## The families

- Slimes: `monsters/slimes.md`. Drakes, wyrms, wyverns, dragons: `monsters/drakes-and-dragons.md`.
- The dead and the dread: `monsters/undead.md`. Ghosts, shapes and fey: `monsters/fey-and-spirits.md`.
- Imps, devils, demons, daemons: `monsters/demons.md`. Animals: `monsters/beasts.md`.
- Elementals: `monsters/elementals.md`. Orcs, brutes, trolls, giants: `monsters/giants.md`.
- Bandits, knights, casters and the pleaders: `monsters/people.md`.
