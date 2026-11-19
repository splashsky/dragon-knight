# Plan: Phase D — scripted spells and items (2.1)

Status: **done** (schema version 7); see "Phase D as implemented" at the end. The
developer documentation is docs/APP.md, "Scripting spells and items". Changelog lines are in
the top 2.1.0 entry.

## Goal

Spell and consumable behaviour is written as Lua code against a small action API instead
of effect objects (`{ kind = "damage", max = 15 }`). Numbers and texts stay data (synced to
the DB, admin-overridable); behaviour lives only in the content file.

Functions are ordinary Lua values: a content table's `cast` (spells) / `use` (items) /
message fields may hold an inline `function ... end` or a reference to a free-standing
local function defined anywhere in the file. Both forms must work identically, and the
docs/examples should show both.

## Spell file

```lua
-- app/content/spells/hurt.lua
local messages = {
	hit = "You have cast the %s spell for %d damage.",
	immune = "The monster is immune to the %s spell.",
}

local function cast(s)
	if s.target.immune >= 1 then return s:say(messages.immune, s.name) end
	local dmg = s:roll(s.power * 5 // 6, s.power)   -- same roll as the original Hurt
	s.target:hurt(dmg)
	s:say(messages.hit, s.name, dmg)
end

return {
	name = "Hurt",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	mp = 5,
	power = 15,              -- data: available to cast() as s.power, admin-overridable
	usable_in = "fight",
	messages = messages,     -- strings are data (overridable); functions allowed too
	cast = cast,             -- or: cast = function(s) ... end
}
```

Optional `can_cast(s)` returns nil or a refusal (`return s:refuse("Your Hit Points are
already full.")`); refusals never cost MP or the turn. MP is deducted by the framework
after a successful `cast`.

## Item file (consumable)

```lua
local function use(u)
	local healed = u.caster:heal("hp", u.power)
	u:say("You drink the %s and recover %d Hit Points.", u.name, healed)
end

return {
	name = "Potion", category = "consumable", price = 60, max_stack = 10,
	usable_in = "both", power = 100,
	can_use = function(u) if u.caster.hp >= u.caster.maxhp then return u:refuse("Your Hit Points are already full.") end end,
	use = use,
}
```

Gear stays declarative: passive `modifiers` (stat bonuses while equipped) remain data
tables, since they are summed, displayed and overridden, not executed.

## Action API (`app/lib/action.lua`)

One context object type for spells and items (`s` / `u`), built per cast/use:

- Spells and items are written in terms of **`caster`** (who acts) and **`target`** (who
	it's aimed at), never "player"/"monster": in Phase E monsters cast the same spells and use
	the same items (see docs/plans/turn-effects.md, "Monsters"). For a self-targeted effect
	(Heal, buffs, potions) `target == caster`.
- Data: `name`, `power`, other numeric data fields of the entity (after overrides),
	`messages`, `in_fight`, `caster`, `target` (nil out of combat for offensive spells),
	`by_player` (true when the player is the caster).
- Combatant handles (`caster`, `target`): `name`, `is_player`, `hp, mp, tp, maxhp, maxmp,
	maxtp`, `immune`, `asleep`, `:heal(stat, n) -> healed` (capped), `:hurt(n)`,
	`:spend(stat, n)`, `:buff(kind, pct)` (uber damage/defense), `:sleep(chance)`, read-only
	derived stats (attack, defense, ...).
- Messages are written for the player's point of view; a spell/item may also give
	`messages.enemy` variants (used when a monster is the caster); otherwise a generic
	"The <monster> casts <spell>." / "uses <item>" line plus the numbers is shown.
- `:roll(min, max)` (php.rand semantics; injected rng for tests), `:say(fmt, ...)`,
	`:refuse(msg)`.
- Changes are recorded on the context and written by the caller (fight/town code), so
	content code never touches the DB. Errors in content code are caught: log, show a
	generic "Something went wrong with that spell" message, no state change, no MP spent.

## Content loading and sync

- Content files run in a restricted environment that exposes only safe globals (`math`,
	`string`, `table`, `ipairs`, `pairs`, `next`, `select`, `type`, `tostring`,
	`tonumber`, `assert`, `error`, `pcall`) — no `dk`, `require`, `io`, `os`.
- Validation: `cast`/`use`/`can_*` must be functions when present; a spell needs `cast`, a
	consumable needs `use`. Message fields: string or function.
- Sync stores only data fields (functions are skipped; message strings are stored and
	overridable). The fingerprint covers data fields plus a hash of the file source, so
	behaviour edits are noticed too.
- At runtime the behaviour is taken from the loaded content module by key (per VM, cached
	for the request), the data from the DB row (with overrides).

## Migration (schema v7)

Replace the stored `effects` / `use_effects` columns by the data fields the new files use
(`power`, message overrides as needed); map existing overrides (e.g. effect amounts →
`power`) via content_adopt. Migrated DB equals a fresh install; tests from the v6 fixture.

## Equivalence

The 19 original spells and the example consumables must behave exactly as before (same
rolls with the same arguments, same numbers, same messages, same refusals, same turn
structure). Existing fight/town/item tests stay green; `effects.lua` is removed once
nothing uses it (keep the `stat` modifier summing wherever Phase C put it).

## Forward compatibility with Phase E

Phase E (docs/plans/turn-effects.md: statuses, damage/heal over time, multi-stage spells,
summons) builds on this API. Read its "Requirements on Phase D" section and design for it:
object-style context and combatant handles, an ordered event list applied by the caller,
one entry point for running an action in a fight, and function-capable content loading
for any kind.

## Phase D as implemented

- **Action API** (`app/lib/action.lua`): `action.combatant(t)` builds read-only combatant
	handles (fields `name`, `is_player`, `level`, `hp`/`mp`/`tp` and their maxima, `attack`,
	`defense`, `strength`, `dexterity`, `immune`, `asleep`, `sleep_chance`, `uber_damage`,
	`uber_defense`; methods `:heal(stat, n) -> restored`, `:hurt(n)`, `:spend(stat, n)`,
	`:buff(kind, pct)`, `:sleep(chance)`), `action.new(o)` the context (metatable class;
	`name`, `description`, `key`, `kind`, `power`, `mp`, `data`, `messages`, `caster`,
	`target`, `in_fight`, `by_player`, `:roll`, `:say`, `:refuse`) and `action.perform(o)`
	runs can_cast/can_use, cast/use and the MP cost and returns the ordered event list
	(`heal`, `hurt`, `spend`, `buff`, `sleep`, `say`; each with `who` and `side`) plus the
	lines, or a refusal (`reason` "cannot" / "refused" / "error"). Handles change their own
	numbers as they go; nothing reaches the game state unless the caller applies the events.
	Capabilities per handle (`can = { buff, sleep }`): the player can be buffed, the monster
	put to sleep; the other way round is an error until Phase E gives monsters buffs and the
	player statuses.
- `app/lib/actors.lua` maps the game state (the users row copy holding the fight) to
	handles (`actors.player(st)`, `actors.monster(st, monster)`) and applies events
	(`actors.apply(st, events)`; monster MP/TP changes are ignored: monsters have none yet).
- **One fight entry point**: `app/fight/act.lua` `act.run(state, action)` for the attack,
	spell and item turns (`state = { st, monster, rand }`, `action = { kind = "attack" |
	"spell" | "item", spell/item = row }` -> `{ lines, killed }` or `{ refused }`); the
	monster's turn stays in the route for now. Town casting and the inventory's Use call
	`action.perform` with the player as caster.
- **Messages**: `s:say(msg, ...)` takes a message key (the stored text, after overrides),
	a format text or a function. Messages may use only `%s`, `%d` and `%%`; an override must
	keep the file's placeholders in order (refused by the admin form, skipped by the sync).
	A monster caster uses `messages.enemy[key]`, else a generic "The X casts Y." / "The X
	uses the Y." line followed by descriptions of the events since the previous line.
	Refusal texts differ between fights and town in the original game, so the original
	files pick their key by `s.in_fight` (`full` / `full_town`).
- **Errors** are caught by `lib/content/sandbox.lua` (`sandbox.call`: xpcall plus an
	instruction budget, `sandbox.BUDGET` = 10M; once spent every instruction fails, so
	`pcall` can't swallow it), logged as warnings with the traceback; the player gets a
	generic "Something went wrong with the X spell." and nothing changes.
- **Loading**: every content kind runs in `sandbox.env()` (the plan's safe globals, with
	`math.random`/`randomseed` left out so dice come from `s:roll`; unknown globals are
	errors). `lib/content/scripted.lua` validates the function fields (`cast` required for
	spells, `use` for consumables, `can_*` optional), messages (strings or functions,
	`enemy` subtable) and `data` (named integers), and stores the strings and numbers as
	`key=value` lines in `messages`/`data` columns. Spells and consumables also store
	`power`, `target` ("enemy" default, "self") and `usable_in` (items: new). Outside fights
	an "enemy" target is nil, so `usable_in` "town"/"both" requires `target = "self"`.
	`load.module(kind, key)` returns the validated module, cached per VM (= per request);
	`load.kind` also returns `modules`. The fingerprint adds a `#source` line per entity
	(sha256 of the file); `load.FORMAT` is "dk-content-4".
- **Content**: the 19 spells and Herb, Potion, Ether are scripted with `power` (the old
	amount/max/chance/pct). Heal and sleep families and the defense buffs and Herb/Ether use
	inline functions; the hurt family, the damage buffs and the Potion free-standing local
	functions. The hurt family has `messages.enemy` wordings.
- **Retired** spells and consumables (file deleted) have no code: they stay known / in the
	bag but are no longer usable (`spells.usable` / `items.usable` check `retired`); before,
	a retired spell's effects stayed castable from the database.
- **Removed**: `app/lib/effects.lua` and its tests. Modifier validation, storage and sums
	moved to `app/lib/stats.lua` (`validate_modifiers`, `encode_modifiers`,
	`decode_modifiers`, `modifiers`); the modifiers format is unchanged.
- **Admin**: spells and consumables override name, description, MP, power, `data.*` and
	message strings; the behaviour, `usable_in` and `target` are shown read-only with a
	note to edit the file. Help pages show spells' cost and power and consumables' power.
- **Migration 7**: `ALTER TABLE` adds `power`, `target`, `messages`, `data` to spells and
	`usable_in`, `target`, `power`, `messages`, `data` to items, and drops `effects` /
	`use_effects` (the tables can't be rebuilt with foreign keys on, so the new columns
	follow `retired`). Rows without a file get power/target/usable_in from their old
	effects. Overrides and pending adoptions of an effect's main amount become `power`
	overrides; others (`min`, a second effect) are dropped with a warning. A version 4
	database's sleep chance 99, which version 5 couldn't keep, is now kept as power.
	`tests/fixtures/schema_v6.sql` + `seed_v6.sql` are the frozen version 6.
- **Equivalence**: `tests/lua/test_action.lua` runs every original spell and consumable
	through a frozen copy of the effects engine (`tests/lua/effects_original.lua`) and
	through the content files, 150 seeded states each, in fights and (heals) in town, and
	compares refusal texts, lines, kills, the rand call ranges in order and the whole state
	afterwards (4,500 cases).
