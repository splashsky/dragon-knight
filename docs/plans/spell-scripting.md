# Plan: Phase D — scripted spells and items (2.1)

Status: approved, starts after Phase C (items, inventory, derived stats) is committed.
Changelog lines go to the top 2.1.0 entry.

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
