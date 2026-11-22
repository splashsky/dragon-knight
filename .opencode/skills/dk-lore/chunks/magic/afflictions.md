---
id: magic/afflictions
summary: The states a fight leaves on people (burning, poison, sleep, doom, wards, marks, rage), as the world knows them, and what cures them.
related: [magic/elements, magic/mages, magic/paladins, magic/warriors, things/consumables, monsters/others, things/battlefield-objects, world/weather-and-time]
sources: [app/content/statuses/burning.lua, app/content/statuses/charging.lua, app/content/statuses/doom.lua, app/content/statuses/fire_ward.lua, app/content/statuses/frost_ward.lua, app/content/statuses/storm_ward.lua, app/content/statuses/fuse.lua, app/content/statuses/guarding.lua, app/content/statuses/marked.lua, app/content/statuses/poison.lua, app/content/statuses/rallied.lua, app/content/statuses/recharging.lua, app/content/statuses/regen.lua, app/content/statuses/sleep.lua, app/content/statuses/soaked.lua, app/content/statuses/swarm.lua, app/content/statuses/uber_damage.lua, app/content/statuses/uber_defense.lua, app/content/statuses/venom.lua, app/content/statuses/weakened.lua, app/content/statuses/withering.lua, app/lib/elements.lua]
---

# Afflictions and states

What a fight leaves on a body. Each is felt every ten seconds (a "turn" in the lore). Harmful ones
can be cured: Antidote, Cure-All, Herb for poison; Cleanse, Mend, Renewal, Dawn from the
Paladins' and Mages' books (`magic/paladins.md`, `things/consumables.md`). A **ward** is the
chance that a state does not take: sleep, poison, venom, burning, weakening and withering can all
be warded, in part or entirely (`magic/elements.md`; the Wakeful Ring, Serpent Ring and Sentinel
Charm are the common wards).

## Of the blood

- **Poisoned.** A poison from a bite, a barbed spine or a cup from the wrong stall. Wears off on its
	own in a few turns; an Herb or a cure ends it sooner. "Nobody in Midworld has ever died of a
	single dose, only of three."
- **Venomous.** Worse than poison, from the fangs of the deeper beasts: it eats the blood and dulls
	the strength, so the venomed creature hits softer and bleeds on. Herb-wives say a bundle of
	leaves will not cure it; the cure takes longer and costs more.
- **Withering.** A dark working that pulls life out of a creature into the caster. Old libraries say it "was
	banned for a reason, and that the reason is still standing in the road to Endworld". Mages learn it at
	54, Paladins at 53.
- **Doom.** A sentence with a date: forty seconds, then the shadow falls. A cure for harmful effects is
	the only way out of the book, and priests in Gilead keep one ready. The doomers do not wait for
	belief (`monsters/undead.md`).

## Of fire, water and cold

- **Burning.** Fire on the clothes or the skin: the same damage each turn until it burns out.
	Rolling on the ground helps. Mages who cast fire at close range carry a wet cloak. Rain, snow, shallows
	and downpours put it out; a marsh makes it burn out sooner; heat, woods and cinders feed it.
- **Soaked.** Wet through: fire is as good as out, a fuse cannot be lit, but lightning bites harder.
	Fishermen of the Shoals say "a wet man is hard to burn and easy to shock".
- **Fire, Frost and Storm Ward.** A thin ward worn about a minute (a spell, or a draught): half the
	damage of its element. It does not put out a fire already burning or thaw a numbed arm; carry a
	warm cloak as well. Smiths in Roma call it cheap insurance; guides above Kalle never rely on one alone.

## Of mind and limb

- **Asleep.** A creature lies down where it stands; sleep takes hold quickly and lets go slowly, with a
	small chance of waking each turn. A sleeping adventurer is the first thing a bandit looks for.
	Night and blizzard deepen it. "Strong sleepers are harder to put down, and some never sleep at all."
- **Weakened.** The limbs go heavy and the grip loose: blows land softer for a few turns. Enfeeble and
	Curse do it (Venom and Plague do the same through the blood). "It feels like hitting through wet sand."
- **Marked.** A hunter's mark: weapon blows land harder; spells and allies ignore it. Fades after a few
	turns, hit or not.
- **Swarmed.** Bees in the hair and down the collar: a sting each turn and blows come out soft. A torch or a
	gale drives them off. (A hive over the fight: `things/battlefield-objects.md`.)
- **Lit Fuse.** A rag soaked in tallow that burns twenty seconds, then the keg goes off; water puts it out.

## Of battle

- **Damage Up** (Craze, Rage, Fury, War Cry). "A battle fury that fills the arms and the voice"; the cost
	comes after, when the body remembers every blow. Bris has a saying about men who fight angry and
	lose their heads.
- **Defense Up** (Ward, Fend, Barrier, the Guard Tonic). A shimmer that blunts blows for the rest of the
	fight; priests of Midworld teach it as a plain prayer for little.
- **Guarding.** Shield up, feet set, head low: no way to win, but it takes the edge off.
- **Rallied.** The shout down the line when a standard goes up; every blade on that side bites harder while
	the banner stands, and a moment after (`monsters/people.md`).
- **Regenerating.** A warm, steady healing from a prayer, a salve or a spell left running; works on the road
	too, so old travellers did not need an inn for the first few days. Does not stack.
- **Charging** and **Recharging.** The stillness before a big spell, the slack arms after. Everyone can see
	the first coming, which is why the wise keep a healer close (`monsters/drakes-and-dragons.md`).
