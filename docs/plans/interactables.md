# 3.3: interactables and targeting

The plan for 3.3.0. Objects on the battlefield that can be hit, set off and used: an
explosive barrel a player buys or a monster rolls out, a beehive in the trees that swarms
whoever knocks it down. They need a **target picker**, so the player can aim at a monster
or an object, and **area abilities** that hit everything on a side of the field.

Decisions (agreed with the owner):

- The player aims with a **target picker** on the fight page (an enemy or an object; it
	stays chosen until it is gone).
- **Monsters use objects on purpose** through their patterns (place a barrel, set it off),
	and their area attacks hit objects by accident like anyone's.
- This is 3.3.0; 3.2.0 is released.

## Invariants (carried over from 3.2)

- **Equivalence**: a fight with no objects, no fields, no statuses and no timeouts still
	rolls the original game's dice. A fight's default target is the first living enemy, as
	before, so nothing changes until the player picks another.
- **Pure GETs**; the server tick and every action advance a fight through the one code
	path (`encounter.advance`); saved fight data is names and plain values only.
- **Declarative where it can be shown** (an object's HP, resistances, where it appears),
	code only for behaviour (what it does when hit, lit or destroyed).

## 1. Targeting

- A fight remembers the player's **target** (a combatant's id in its data). Actions aimed
	at "the enemy" go to it while it is alive and targetable, otherwise to the first living
	enemy (today's rule). Self-targeted spells and items are unchanged.
- **The page**: each enemy and object on the fight page is a choice of one radio group
	(`target=<id>`) in the fight's form, styled as the combatant's card; the chosen one is
	marked. With the live client a click chooses it without a request (the next action
	sends it); without JavaScript it is an ordinary radio button. The keyboard reaches it
	like any form control, and the hotbar keys work as now.
- **Monsters** choose targets as now (`fight/ai.lua`), plus objects where a loadout entry
	aims at one (below).

## 2. Interactables

A new content kind, **interactables** (`app/content/interactables/<key>.lua`, table
`interactables`, synced and overridable like the others):

- **Data**: `name`, `description`, `lore`, `icon`, `hp`, `resist`, `ward`, and where it
	appears by itself (`spawn`: terrain fields, biomes or features at or near the player's
	tile, and a chance), all shown on the help pages and in tooltips.
- **Behaviour** (hooks, run like a status's, with a context `o`: `o.self`, the fight's
	combatants and objects as handles, `o:roll`, `o:say`, `o.wind`, `o:has_field`):
	`on_place`, `on_damage(o, amount, element)`, `on_status(o, key)` (a status put on it),
	`on_status_near(o, key, bearer)` (a status put on anyone in the fight: how a fire
	spreads to a barrel in a high wind), `on_tick(o)` (a lit fuse burning down),
	`on_destroyed(o)` (its HP ran out: a barrel's blast, a hive's swarm).
- **In a fight** an object is a participant that never takes a turn: it has HP and
	statuses, can be targeted and hurt, is never counted for victory or defeat, and leaves
	the field when its HP runs out (after `on_destroyed`). At most a few per fight.
- **Getting there**: `s:place(key, params)` from a spell or an item (the player's or a
	monster's), or by itself when an encounter begins, by the files' `spawn` rules (read from
	the land: `lib/terrain.lua`).
- **Hitting everyone**: a blast is `o:hurt_all(n, element)` (every combatant and object on
	the field, the one who placed it included: chain reactions are allowed, each object
	destroyed once).

## 3. Wind

Fields get a **wind** level (0 calm to 3 gale), declarative like their damage numbers:
the thunderstorm and the blizzard high, the peaks windy, the rest calm unless their file
says otherwise. A fight's wind is the highest of its fields. Content reads it as `o.wind`
(and `s.wind`, `t.wind`), so "burning applied in a high wind may light the barrel" is a
few lines of the barrel's file.

## 4. Area abilities

A spell or an item may be an **area** action (`area = true`): its code gets `s.targets`,
every opponent of the caster and every object on the field, and hurts or afflicts each.
The fight's target doesn't matter to it. Some existing spells become area actions (the
content phase picks them: the falling-rock and falling-star kind, and the monsters'
breaths), and that is how a beehive gets knocked down by accident.

## 5. Monsters and objects

- A loadout entry may **place** an object (an item or spell that calls `s:place`), and an
	entry may **aim** at one: `aim = "<interactable key>"` sends that action at an object of
	that key when one is on the field (and makes the entry ineligible when none is).
- Conditions see the field: `m:has_object(key)`, and the objects as handles
	(`m.objects`). `tests/lua/test_patterns.lua` plays states with objects on the field.

## 6. Shown

- The fight page lists the objects on the field with their icon, HP and statuses and a
	tooltip, as target choices; the Battlefield line stays as it is.
- Fight events gain `object = { { change = "place" | "leave" | "blast", id, key, name,
	hp, max } }`; `fight.js` animates them (a blast flashes; nothing moves with
	`prefers-reduced-motion`).
- `/help` gets a page for the objects (where they appear, what they do).

## 7. Content (designed, then written)

- **The examples**: an **Explosive Barrel** (an item to buy, Kalle's miners' blasting
	powder; monsters carry it too): placed on the field; destroyed or lit, it blasts
	everyone with fire after a short fuse; burning applied anywhere in a high wind may
	light it. A **Beehive** (by itself, in or near the Weald's trees and forest ground):
	knocked down (destroyed, often by an area attack), it puts **Swarm** (a new harmful
	status: stings every tick) on one participant.
- **More, by land**: a designer proposes a few objects per biome from the lore (the
	Diggings, the Shoals, the Ashlands, the Thornbog, ...), each with a reason to target it
	or avoid it.
- **Monster patterns** that use them (bandits and goblins with barrels; who would kick a
	hive), lore and flavor lines.

## 8. Decisions from the design

The object design (Phase J: ten objects by land, four statuses, area actions, monsters
that use objects) settled these engine questions:

- **Hooks know the blow**: `on_damage(o, amount, element, source)` and `on_destroyed(o,
	element, source)` get the element and the source of the hit; `on_damage` runs on a
	fully resisted hit too (amount 0: water dousing a fuse).
- **Objects' handles**: `o.data` kept with the fight (plain values), `o.level` (the
	placer's, or the land's band for one that appeared by itself), `o.self:afflict`,
	`:cure`, `:destroy`; `key` and `over` (the side of the field it stands over:
	`"player"` or `"enemy"`, for objects that fall or swarm onto one side) on every
	object's handle, in `m.objects` too.
- **A blast hits everyone in full**, the placer included (the barrel's numbers are tuned
	for it).
- **Wind**: the thunderstorm and the blizzard 3, the peaks 2, the hills, the sand and the
	cinders 1, the rest 0; a **Gale** field spell (wind 3, no rain) so a fire can spread in a
	wind at all (the storms put fires out).
- **Thunderstorm bolts strike objects** as well as combatants.
- **Appearing by itself** is decided by the fight's voice hash (like speech), never the
	dice: at most one object by itself, at most three on the field; none in the Midlands,
	within 12 tiles of Midworld or at the tests' calm place.
- `aim = "<key>"` names an object's key; which side it stands over is a condition.

## Phases

| Phase | Who | Owns |
|---|---|---|
| I. Targeting, interactables, wind, area actions, aim | Opus | the fight engine and model, the kind, the AI, the fight page and events, `/help`, schema, tests, docs |
| J. Object design | Sonnet (no repo edits) | a design of the objects per biome, the area spells, the monsters that use them |
| K. Content | Sonnet | the objects, Swarm, the barrel item and its shops, area spells, monster patterns |
| L. Lore and flavor | Haiku | lore and lines for the new content |
