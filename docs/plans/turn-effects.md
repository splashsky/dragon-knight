# Plan: Phase E — multi-turn effects: statuses, multi-stage spells, summons (2.2)

Status: approved direction, starts after Phase D (scripted spells and items).

Version: Phase E is **2.2**. It starts by setting `view.GAME_VERSION = "2.2.0-dev"` (and
`DK_VERSION` in src/main.c) and adding a new top changelog entry `version = "2.2.0",
date = "unreleased"`; its changelog lines go there. Closing the 2.1.0 entry (giving it a
release date) is the project owner's call when Phase D is done. Phase D must already shape
its action API so this phase only adds to it (see "Requirements on Phase D" at the end).

## Goals

- Effects that last several turns: damage over time (poison, burn), heal over time
	(regen), buffs/debuffs with a duration.
- Multi-stage actions: charge-then-release ("Solar Beam": charge a turn, fire the next) and
	act-then-recover ("Hyper Beam": fire now, must recharge next turn).
- Summons: allied combatants that fight alongside the player for a while.
- Behaviour written as Lua functions (inline or free-standing), like Phase D; numbers and
	texts as data.

## Concepts

### Statuses (new content kind `statuses`)

A status is a reusable, named, timed effect attached to a combatant (player, monster or
summon). It is its own content kind so any spell, item or monster can apply it.

```lua
-- app/content/statuses/burn.lua
local function tick(t)                 -- t: status context
	local dmg = t:roll(t.data.min, t.data.max)
	t.bearer:hurt(dmg)
	t:say("%s burns for %d damage.", t.bearer.name, dmg)
end

return {
	name = "Burning",
	description = "Takes fire damage every turn.",
	kind = "harmful",              -- harmful | helpful (display, cleansing)
	tick_on = "turn_end",          -- turn_start | turn_end (of the bearer)
	on_tick = tick,                -- or inline function
	-- optional hooks: on_apply, on_expire, on_remove, modify_damage_dealt,
	-- modify_damage_taken, blocks_action (function or boolean)
}
```

Re-applying a status always **overrides** the existing instance on that bearer: the new
duration and params replace the old ones, even when the old one would have lasted longer
(a poison with 5 turns left becomes a 2-turn poison if a 2-turn poison is applied). The old
instance is removed without its `on_expire` (its `on_remove` hook runs), then the new one
is applied (`on_apply`). There is no additive stacking.

Applying, from any action context: `s.target:afflict("burn", { turns = 3, min = 2, max = 4 })`.
`t.data` is the params table given when applied (persisted), `t.turns_left`, `t.bearer`,
`t.source` (who applied it), plus the Phase D helpers (`roll`, `say`, `refuse`...).

### Multi-stage actions

Expressed with statuses that lock the bearer's actions:

- **Recharge (Hyper Beam)**: `cast` deals the damage, then
	`s.caster:afflict("recharging", { turns = 1 })`; `recharging` has `blocks_action = true`
	— the player's next turn is skipped (fight page shows only "Continue") and the monster
	still acts.
- **Charge (Solar Beam)**: `cast` applies `s.caster:afflict("charging", { turns = 1,
	release = "solar_beam_release" })`; on expiry the status calls the release step. Release
	steps are named functions exported by the spell file (`stages = { release = fn }`) and
	referenced by name, because persisted state can only hold names and data, never
	functions.

Sugar on the action context: `s:charge(turns, "release")` and `s:recharge(turns)`.

### Summons (new content kind `summons`)

```lua
-- app/content/summons/wolf.lua
local function act(a)                  -- a: combatant action context
	local dmg = a:roll(a.self.attack // 2, a.self.attack)
	a.target:hurt(dmg)
	a:say("Your wolf bites for %d damage.", dmg)
end

return {
	name = "Wolf", hp = 30, attack = 12, defense = 5,
	act = act,                       -- runs once per round on the ally phase
	-- optional: on_summon, on_death, on_expire
}
```

From a spell: `s:summon("wolf", { turns = 5 })`. Allies act after the player, can be
targeted by the monster (see "Monster AI"), and are removed when their HP hits 0, when
`turns` run out, or when the fight ends. A cap of active summons per fight (default 1,
`control` setting).

## Fight model changes

- **Combatants**: the fight state moves from `users.current*` columns to
	`fight_combatants(id, user_id, side, kind, key, hp, maxhp, data)` (`side`: player, ally,
	enemy; plus `wave` for enemies — see "Encounters"; one monster for now) and
	`fight_statuses(id, user_id, combatant_id, status_id, turns_left, data, applied_round,
	source)`. A `fights(user_id, round, ...)` row holds the round counter and fight-level
	state. All loaded and saved once per request in the request transaction.
- **Round pipeline** (`app/fight/round.lua`), deterministic and unit-testable with an
	injected rng:
	1. player turn start: statuses `tick_on = turn_start` on the player; if any status blocks
		 the action, the player's action is "Continue" (skip);
	2. player action (attack / spell / item / run / continue);
	3. allies act (in summon order);
	4. each enemy of the current wave in order: turn-start ticks, then it acts unless blocked
	   (sleep becomes a status), choosing action and target by weight (see "Monster AI");
	5. turn-end ticks for everyone; decrement durations; expire (on_expire hooks);
	6. death checks after every step that changes HP (same victory/death flow as now).
- **Existing mechanics become statuses**: monster sleep (wake chance per turn) and the uber
	damage/defense buffs move to `app/content/statuses/{sleep,uber_damage,uber_defense}.lua`
	with identical behaviour and identical rng call order (equivalence tests prove the
	original spells and fights are unchanged).
- **Outside fights**: statuses may set `scope = "world"` and tick on map moves instead of
	rounds (e.g. a regen potion for the next 10 moves); default `scope = "fight"`, cleared
	when the fight ends. World statuses live in `fight_statuses` with `combatant_id` NULL
	(or a `user_statuses` table — implementer's call, documented).
- **UI**: the fight page lists active statuses (name, turns left) for player, allies and
	monster, the allies with their HP, and the locked "Continue" state; the character page
	shows world statuses.
- **Robustness**: errors in status/summon code are caught and logged; the failing status or
	summon is removed; the round continues. A hard cap on statuses per combatant and on
	ticks per round prevents runaway content.

## Monster AI: weighted actions

- `app/fight/ai.lua` chooses each enemy's action and target by weight. A weighted choice
	helper (`ai.pick(weights, rand)`) is shared by both decisions.
- Actions: a monster has a list of actions with weights; today every monster has exactly
	one action, the existing attack (unchanged formula). The structure is there so monster
	content can later add actions (special attacks, statuses, healing) with weights; tuning
	comes later.
- Targets: every living opponent (the player and each summon) gets weight 1, so with one
	summon the monster attacks you or your summon 50/50. When the player is the only
	possible target, no roll is made at all, so fights without summons consume exactly the
	same random numbers as before (equivalence).
- A summon hit by the monster takes the same damage formula with the summon's defense in
	place of the player's.

## Monsters as content: MP, equipment, items, spells (Phase E2)

Phase E is implemented in two steps, both 2.2: **E1** the fight engine (combatants, round
pipeline, encounters, statuses, multi-stage actions, summons, weighted AI framework) and
**E2** monsters as content with loadouts. E2 needs E1's pipeline and AI.

- **Monsters become a content kind** (`app/content/monsters/<key>.lua`, ids 1–151 kept,
	keys from names, generated once from the seed; same hybrid sync and admin overrides as
	the other kinds; the monster admin editor moves to the content admin pages).
- **MP for every monster**: new fields `maxmp` and `uses_mp` (boolean). Every existing
	monster gets `maxmp` = the Mage's total MP at the monster's level (minimum 5), written
	into its file; `uses_mp = true` by default. When `uses_mp` is false, spells cost the
	monster nothing (MP is still shown/available to scripts). Monster MP starts full each
	encounter; spells with `uses_mp` deduct `mp` like the player's and are unavailable when
	MP is short.
- **Equipment**: `equipment = { weapon = "broadsword", armor = "chain_mail", ... }` (item
	keys, same slots as players). Equipped items' modifiers add to the monster's base stats
	(`attack` → damage, `defense` → armor, `maxhp`, ...), via the same derived-stats code as
	players. Existing monsters get no equipment, so their numbers are unchanged.
- **Items**: `items = { { item = "potion", weight = 3, stock = 2, when = low_hp }, ... }`.
	`stock` is a number (finite, per encounter; decremented on use) or `nil` for infinite.
	Items are used through the same `use`/`can_use` code as the player's (Phase D), with the
	monster as caster.
- **Spells**: `spells = { { spell = "hurt", weight = 2 }, { spell = "heal", weight = 1,
	when = function(m) return m.hp < m.maxhp // 3 end } }`, cast through the Phase D spell
	code with the monster as caster (MP rules above).
- **`when` conditions**: optional functions (inline or free-standing, like everywhere else)
	receiving the monster's AI context (`m.hp`, `m.maxhp`, `m.mp`, `m.round`, `m.target`,
	`m:has_status(key)`, ...); an entry whose `when` returns false is not eligible this turn.
- **Choosing an action** (`app/fight/ai.lua`): each turn the monster's eligible actions are
	the basic attack (weight `attack_weight`, default 1) plus every spell it can afford and
	every item it has in stock whose `when` passes and whose `can_cast`/`can_use` doesn't
	refuse; one is picked by weight, then the target by weight (players/summons as above;
	self for self-targeted spells/items). If exactly one action is eligible no roll is made,
	so existing monsters (attack only) consume the same random numbers as before.
- **Not now**: monsters dropping their equipment or items, and AI tuning of the weights.

## Encounters: one monster now, ready for more

- A fight is an **encounter**: an ordered list of **waves**, each wave a list of enemy
	combatants. Today every encounter is one wave with one monster (the current random
	monster pick), so gameplay is unchanged.
- The data model and round pipeline already iterate over all enemies of the current wave
	(each acts in order, each gets its own status ticks), and victory means "the current
	wave is defeated and no waves remain"; otherwise the next wave enters. Rewards are per
	defeated enemy (exp/gold summed) with the drop roll once per encounter (as now).
- Player targeting: with a single enemy the player's actions target it implicitly; the
	action API takes an optional target so a target picker can be added to the fight page
	later without changing spell files (`s.target` stays "the current target").
- Not in this phase: multi-monster or multi-wave encounter content (how encounters are
	defined), the target picker UI, and AI tuning.

## Content and sync

- New kinds `statuses` and `summons` follow the Phase A/D rules (data synced and
	overridable, functions only in files, fingerprint includes the source hash).
- References by key are validated by `dk check` where they are static (e.g. a spell file
	declaring `uses = { statuses = { "burn" } }` — optional declared dependencies so
	`dk check` can catch typos); dynamic references fail at runtime with a logged error.

## Examples shipped with the phase

New content (in addition to the originals, which stay unchanged):
- spells: `poison` (DoT), `regen` (HoT, usable in town as a world status), `hyper_beam`
	(big hit + recharge), `solar_beam` (charge + release), `call_wolf` (summon);
- items: `antidote` (removes harmful statuses), `regen_potion` (world regen).
New spells are learned by no class by default (admins/content authors add them to class
schedules); tests use a test class.

## Migration (schema v8 for E1, v9 for E2)

- **v8 (E1)**: create the fight tables, move any in-progress fights (current monster, hp,
	sleep, immune, uber values) into them, drop the old `current*` fight columns. A player
	mid-fight before the migration continues the same fight after it.
- **v9 (E2)**: the `monsters` table becomes the content table (key, maxmp, uses_mp,
	attack_weight, loadout columns or child tables for equipment/items/spells, retired);
	admin edits to monster stats are carried over as overrides (content_adopt); in-progress
	fights keep their monster (ids are preserved).

## Tests

- E2: loadout validation (unknown item/spell keys fail `dk check`), weighted choice over
	many trials, `when` conditions, finite stock running out per encounter and resetting in
	the next, `uses_mp` on/off, equipment changing monster stats, monster-cast spells and
	monster-used items with enemy messages, and no extra rng calls for attack-only monsters
	(existing fight tests unchanged).

- Unit: round pipeline order, tick timing, override on re-apply (shorter replaces longer),
	expiry vs remove hooks, blocked actions, weighted AI picks (no roll when the player is the
	only target; 50/50 with one summon over many trials), wave progression,
	charge/release and recharge, summon actions and death, caps, error containment, world
	statuses on moves.
- Equivalence: all existing fight tests unchanged in substance; the original spells produce
	the same rng call sequence and results.
- E2E: each example spell/item through HTTP, mid-fight migration.

## Requirements on Phase D (so this phase only adds)

- The action context is a proper object (metatable "class") with combatant handles
	(`s.caster`, `s.target`) that are objects too (`:hurt`, `:heal`, ...), so `:afflict`,
	`s:summon`, `s:charge`, `s:recharge` and allies can be added without changing spell
	files.
- Changes are recorded as an ordered list of events (`hurt`, `heal`, `say`, ...) and
	applied by the caller, so later phases can add new event types and route them to
	combatants other than the player/monster.
- Fight code that runs a spell or item turn goes through one function (e.g.
	`fight.act(state, action)`), the seed of the Phase E round pipeline.
- Content loading supports functions in any kind and exposes the loaded module per key,
	so statuses and summons can reuse it.
