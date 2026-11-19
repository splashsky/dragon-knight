# Plan: Phase E — multi-turn effects: statuses, multi-stage spells, summons (2.2)

Status: **done**: E1 (the fight engine, schema version 8) and E2 (monsters as content with
MP, equipment, items, spells and weighted loadouts, schema version 9); see "Phase E1 as
implemented" and "Phase E2 as implemented" at the end. The developer documentation is
docs/APP.md, "Fight engine" and "Monsters"; changelog lines are in the top 2.2.0 entry.

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

## Phase E1 as implemented

- **Modules**: `app/fight/state.lua` (the model and its tables; `state.load/save/clear/
	begin`, `state.world` for the player outside fights; `state.encode/decode`: data as
	typed "name=i:5" lines, functions refused), `app/fight/engine.lua` (handles for content
	code, `engine.apply` for every event type, statuses, summons, damage modifiers, release
	steps, caps), `app/fight/round.lua` (`round.start`, `round.play`, `round.locked`),
	`app/fight/ai.lua` (`ai.pick`, `ai.targets`, `ai.actions`, `ai.choose`, providers),
	`app/fight/act.lua` (now the actions of a turn: the player's attack/spell/item and
	`act.enemy_attack`), `app/lib/{statuses,summons}.lua` (rows, cached per request),
	`app/lib/world.lua` (world statuses: out-of-fight actions and map moves),
	`app/admin/effects.lua` (`/admin/statuses`, `/admin/summons`). `lib/actors.lua` is gone
	(the engine maps every combatant). The route keeps picking the monster and checking the
	player's choice; the monster's turn moved into the pipeline.
- **Tables (v8)**: `fights(user_id PK, round, wave, data)`, `fight_combatants(user_id,
	id, side, kind, entity_id, wave, hp, maxhp, turns_left, data)` with ids 1..n per fight
	(player 1; PK (user_id, id), so a save rewrites the rows with the same numbers),
	`fight_statuses(user_id, combatant_id, status_id, position, turns_left, data,
	applied_round, source)` with PK (user_id, combatant_id, status_id) (the override rule
	in the schema), `user_statuses(user_id, status_id, position, turns_left, data)` for
	world statuses (a separate table rather than NULL combatant ids), content tables
	`statuses` and `summons`, `control.max_allies` (1). `fights.round` keeps the original
	`currentfight` semantics (1: monster not picked yet; +1 per fight page, max 255), so
	`GET /fight` and `/victory` behave as before. The player's HP stays in `users`
	(`fight_combatants.hp` is NULL for the player).
- **Statuses** have `kind` (harmful / helpful / **neutral**: recharging and charging aren't
	cured by an antidote), `tick_on`, `scope` (fight / world / **both**: regen works in
	fights and on the map), `turns` (default duration, 0 = none: sleep and the buffs),
	`blocks_action` (bool data or a function), messages (`blocked` / `blocked_other` are
	said for a blocked turn) and data. Timing: a status counts the bearer's turns that
	begin after it was applied (marked at the bearer's turn start), ticks at `tick_on` of
	those turns, counts down at their end and expires at 0. Override: `on_remove` of the
	old instance, then `on_apply`. Hook errors remove the status; `MAX_STATUSES` 10 per
	combatant, `MAX_TICKS` 100 code runs per round (on_apply chains included).
- **Action API additions** (no content file changed): handles have `id`, `side` and their
	statuses (`:afflict`, `:cure(key or kind)`, `:has_status`, `:status`, `:statuses`);
	`:buff` / `:sleep` record the old events, applied as the statuses `uber_*` / `sleep`
	(0 removes them), and work on anyone; contexts have `s:summon`, `s.summon_room`,
	`s:charge(turns, step)`, `s:recharge(turns)`, and in status hooks `t:expire()`,
	`t:remove()`, `t:release()`; `action.call` runs any content function (hooks, `act`,
	stages) with a context; statuses' and summons' lines are never worded for a monster
	(`plain`). Content files may declare `stages = { name = fn }` and `uses = { statuses =
	{...}, summons = {...} }` (checked by `dk check` as references).
- **Multi-stage**: `charging` ticks at turn start and, on its last turn, expires; its
	`on_expire` calls `t:release()`, so the stage is the action of the turn after the cast
	(the page showed only "Continue"). `recharging` simply blocks for its turns. Locked
	turns: the route turns any command into `continue` while the player has a blocking
	status; "Continue" without one only shows the page.
- **Refusals** run on a copy of the model (`state.copy`), so a refused action undoes even
	the turn-start ticks (nothing changes, as in 2.1).
- **Summons** act after the player (also in the round they arrive), count their rounds
	down at the round's end, leave at 0 HP ("Your X has been defeated." or `on_death`) or
	when their rounds run out (`on_expire`, else "Your X leaves the fight."). Monsters
	target them by weight 1 like the player (50/50), with the summon's defense and
	dexterity in the original formula (lines "The monster attacks your Wolf for N
	damage.").
- **Waves**: enemies have a wave; the next one enters when the current one is defeated
	("Another monster appears: the X."); `/victory` sums each defeated enemy's rewards and
	rolls the drop once, at the highest enemy level. Encounters are still one monster.
- **World statuses** tick on every map move before the roll for a fight (no extra dice
	without world statuses), can't take the last HP, and their lines aren't shown (the move
	redirects to the map).
- **Equivalence**: `tests/lua/fight_original.lua` freezes the 2.1 fight (combat formulas and
	the route's turn structure; verified against the 2.1 code before the refactoring);
	`tests/lua/test_round.lua` plays 1,000 seeded fights (about 3,000 rounds: attacks,
	runs, the 19 original spells through the frozen effects engine, the three consumables,
	ambushes; with sleep and buffs) through both and compares every roll (arguments and
	order), every line, the outcome and the state; `test_action.lua`'s 4,500 spell/item
	cases now run through the fight model; the fight unit and e2e tests keep their dice and
	expectations.
- **Fixed** in passing: a won fight's page redirects to `/victory` (legacy showed the
	defeated monster until then).

### Notes for E2

- Add monster actions as AI providers (`ai.provide(function(f, c) ... end)`) returning
	candidates `{ kind = "spell" | "item", weight, target = "opponent" | "self", perform }`;
	`perform` runs `action.perform` with `engine.handle(f, c)` as caster (enemy wording is
	already automatic) and `engine.apply(f, r.events, c)`. Filter by `when` and
	`can_cast`/`can_use` in the provider; with a single eligible candidate `ai.pick` makes
	no roll. The attack candidate already reads `row.attack_weight`.
- Monster MP: `engine.handle` gives monsters mp 0 and `engine.apply` ignores their MP/TP
	(`add_stat`); store `mp`/`maxmp` in `fight_combatants` (columns or `data`) and handle
	them there. Finite item stock per encounter fits `c.data` (saved with the fight).
- Monster stats come from `c.row` (`maxdam`, `armor`, `name`, `level`); equipment
	modifiers belong in `engine.handle` and `act.enemy_attack`.
- `fight_combatants.entity_id` is the monster id (kept by E2's content kind, so fights in
	progress survive v9). `state.add_monster(f, row, wave)` + `round.start(f)` start an
	encounter of any size; only the route's monster pick is one monster.
- Not done: showing world-status lines after a move, a target picker, multi-monster
	encounter content, AI tuning.

## Phase E2 as implemented

- **Content kind `monsters`** (`app/lib/content/kinds/monsters.lua`, synced after items, the
	last kind): the 151 originals were generated once from the seed (ids 1-151, keys from
	the names; no duplicates), with the same stats and `maxmp` = the Mage's total MP at
	their level (start + gains of `classes/mage.lua`, at least 5) as a literal. Fields:
	`name`, `description`, `level`, `maxhp`, `maxdam`, `armor`, `maxexp`, `maxgold`,
	`immune`, `maxmp`, `uses_mp` (default true), `attack_weight` (default 1, 0: only as the
	fallback), **`roams`** (default true: picked by random encounters; new, so the examples
	can stay out of the level bands), `equipment` (slot -> item key), `items` (`{ item,
	weight, stock, when }`), `spells` (`{ spell, weight, when }`). Flat form:
	"equipment.weapon", "items.1.item"/".weight"/".stock"/".when" (1: has a condition),
	"spells.1.spell"/... `dk check`: keys must be files, weights >= 1, stock >= 1 or absent,
	`when` a function, slots valid, equipment of the slot's category, items consumables
	usable in fights, spells usable in fights (a new optional kind hook,
	`validate_refs(flat, all, err)`, run by `load.all`). `load.FORMAT` is "dk-content-6".
- **Tables**: `monsters(id, key, name, description, maxhp, maxdam, armor, level, maxexp,
	maxgold, immune, maxmp, uses_mp, attack_weight, roams, retired)` plus child tables
	`monster_equipment(monster_id, slot, item_id)`, `monster_items(monster_id, position,
	item_id, weight, stock, has_when)`, `monster_spells(monster_id, position, spell_id,
	weight, has_when)` (written by the kind's `write_children`); `when` functions stay in the
	file and are found by list and position (`monsters.condition`).
	`fight_combatants.mp`/`maxmp` hold a monster's MP (NULL: full on load).
- **Runtime**: `lib/monsters.lua` (rows, `roaming(min, max)` for the route's pick, loadouts
	read in three queries per request, `effective(row)`); `fight/monster.lua` (the AI
	provider `monster.candidates`, the `when` context, using spells and items);
	`stats.monster` (equipment by the players' rules: maxdam is the base attack, armor the
	base defense, maxhp/maxmp the base maxima, strength and dexterity 0; so a monster
	without equipment keeps its numbers). `c.row` of a monster combatant is the effective
	row (with `base`), so the HP roll, who swings first, running away, its attack and the
	player's attack use the equipment; `engine.handle` gives monsters `mp`/`maxmp`,
	`strength`/`dexterity`; `engine.apply` changes a monster's MP (TP still ignored).
	`action.perform` takes `free` (no MP cost: `uses_mp = false`); `action.check` runs only
	`can_cast`/`can_use` with dice that error, for eligibility without rolls.
- **AI**: candidates in order: the attack (`attack_weight`), each spell (usable in fights,
	affordable with `uses_mp`, `when` passes, `can_cast` doesn't refuse on the default
	target), each item (stock left, usable, `when`, `can_use`); `ai.pick` by weight (no roll
	for one), then the target (self for `target = "self"`, else an opponent by weight). A
	use refused after all (another target than the checked one) becomes an attack. With no
	eligible candidate of weight > 0 the attack is the fallback (no roll). Stock is
	`stock_<position>` in the combatant's data, set at `state.add_monster` (lazily for
	fights without it), so a new encounter starts full. A monster can't summon (no room).
- **Examples** (`roams = false`, ids after 151 in key order: 152 `bandit_captain`, 153
	`bog_witch`, 154 `goblin_shaman` on a fresh install): the Goblin Shaman (Hurt; Heal
	below half HP, inline `when`; two Potions below a third, free-standing `when`; a
	Dagger), the Bog Witch (`uses_mp = false`: Sleep unless you sleep, Poison unless you
	are poisoned, Pain) and the Bandit Captain (Broadsword, Chain Mail, Small Shield, Life
	Stone; Craze once, a Herb when hurt). Tests put them in fights directly.
- **Admin**: `/admin/monsters` is the shared content admin (`admin/effects.lua`, which now
	also serves monsters): stats, MP, `uses_mp`, `attack_weight`, `roams` overridable, the
	loadout read-only ("edit app/content/monsters/<key>.lua"); the list keeps the level vs
	map size note (roaming monsters). The old CRUD monster editor is gone.
- **Help**: `/help/monsters` lists non-retired monsters with their effective stats and a
	Max MP column; monsters with a loadout get a line with their spells, items (stock) and
	equipment; non-roaming ones say "not met at random". The fight page shows "Monster's
	MP" for monsters with spells.
- **Migration 9**: rebuilds `monsters` (plain rowid ids, `key` UNIQUE), keys the originals
	by id from the frozen list of original names (partial installs get the 151 ids), puts
	their stats into `content_adopt` (the sync turns edits into overrides), keeps other rows
	under `monster_<id>` (retired by the sync, reported; their fights go on; maxmp from a
	frozen Mage MP table), creates the loadout tables, adds `fight_combatants.mp`/`maxmp`.
	`tests/fixtures/schema_v8.sql` + `seed_v8.sql` are the frozen version 8;
	`tests/e2e/migrate.sh` checks v0 -> 9 and v8 -> 9 against a fresh install (layout,
	monsters and loadouts), the overrides, a retired hand-made monster's fight and an
	original monster's fight going on (asleep, MP full).
- **Equivalence**: `tests/lua/test_round.lua` plays its 1,000 seeded fights against the
	151 original monsters (its query now names them, `id <= 151`, as the examples act
	differently by design) through the pipeline with the loadout provider in place: the
	same rolls, lines and state as the frozen 2.1 fight. `tests/lua/test_monsters.lua`
	asserts no extra roll for attack-only monsters.
- Not done: monsters dropping their equipment or items, encounter content placing the
	non-roaming monsters, enemy wordings for every original spell (Hurt says "on you" even
	when a monster casts it at a summon), AI tuning.
