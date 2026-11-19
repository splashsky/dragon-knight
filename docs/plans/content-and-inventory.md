# Plan: content entities (classes, spells, items) and inventory

Status: approved design, implemented in three phases (A classes + content sync, B spells +
effects, C items + inventory). Each phase is one schema migration with tests, admin pages,
help pages and changelog lines.

Version: all of this is **2.1** (in development until the project owner says otherwise),
together with the earlier 2.1 work (difficulty removal, leveling formulas), which already
created the top changelog entry `version = "2.1.0", date = "unreleased"` and set
`view.GAME_VERSION = "2.1.0-dev"`. Every phase adds its changelog lines to that 2.1.0
entry, never to 2.0.0.

## Goals

- Classes, spells and items are content entities authored as Lua data files in git,
	hot-reloaded like the rest of the app, and synced into the database (the hybrid model).
- New classes can be added without code changes.
- Items cover gear (weapon, armor, shield, accessories), consumables, quest items and misc.
- A simple slot-based inventory with a soft cap of 12 bag stacks.

## Content files

```
app/content/classes/<key>.lua     return { name = "Mage", ... }
app/content/spells/<key>.lua
app/content/items/<key>.lua
```

- The file name is the entity's stable `key` (`[a-z0-9_]+`). Keys never change once
	players may reference them; renaming = new entity + retiring the old one.
- Files return plain data tables (no DB access, no side effects). A schema module per kind
	(`app/lib/content/schema.lua`) validates fields and types and reports errors with the
	file name; `./dk check` validates all content.
- Listing files needs a small engine binding: `dk.list_modules("content.items")` returning
	module names under that app directory (C, `bind_dk.c`, via the code cache's directory
	walk).

## Sync (files → database)

- Each kind has a DB table with `id INTEGER PRIMARY KEY` (used by foreign keys), a UNIQUE
	`key`, the content columns, and `retired INTEGER NOT NULL DEFAULT 0`.
- `meta(key TEXT PRIMARY KEY, value TEXT)` stores `content_fingerprint` (sha256 of the
	canonical serialization of all content) and `content_seen` (process id + code-cache
	generation, from `dk.vmstats()`; add `boot_id` to vmstats if needed).
- Per request (inside the request transaction): if `content_seen` differs from the current
	process/generation, recompute the fingerprint; if it differs from the stored one, run the
	sync; store both. Cost when nothing changed: one small query.
- Sync = upsert every file entity by key (insert new ids, update columns), mark DB rows whose
	key has no file as `retired = 1` (never delete: players may hold references), un-retire
	keys that come back, then re-apply admin overrides. `dk content sync` (CLI) and
	`dk content status` run the same code; `dk install` and `dk migrate` sync at the end.
- Admin overrides: `content_overrides(kind, key, field, value)`. Admin edit pages write
	overrides (only whitelisted fields per kind), show the file value next to the override and
	offer "reset to file" (delete override). Overrides survive syncs.
- Seed data: the original classes, spells, items and drops become content files (generated
	once from the current seed, values identical). The SQL seed keeps only towns, monsters,
	control and news.

## Phase A: classes (schema v4)

- `classes`: `id, key, name, description, sort, playable, start_hp, start_mp, start_tp,
	start_strength, start_dexterity, exp_base, exp_stages` (stages as text `"2x2,1.5x8,..."`
	or JSON-ish; parsed by `leveling.lua`), `retired`.
- `class_levels(class_id, level, hp, mp, strength, dexterity)` — per-level gains (the
	levels table data), PRIMARY KEY (class_id, level).
- `class_spells(class_id, level, spell_id)` — learn schedule; several spells per level are
	allowed. (Spell ids come from the existing spells table in phase A; phase B moves spells
	to content and the class files reference spells by key.)
- Class content file: name, description, sort, playable, starting stats, exp curve
	parameters, `levels = { [2] = { hp=2, mp=5, strength=0, dexterity=1, spells={"heal"} }, ... }`.
	The TP rule and HP milestones stay global in `leveling.lua`.
- `users.charclass` references `classes.id` (ids 1–3 preserved for Mage, Warrior, Paladin);
	`control.class1name..class3name` and the `levels` table are dropped.
- Registration lists playable, non-retired classes in `sort` order; help, character sheets,
	admin user editor use class names from the table.
- Admin: class list + detail (overrides for name/description/playable/start stats; per-level
	gains read-only from file with a note) and a "new class" hint (copy a file).
- Migration v4: build classes/class_levels/class_spells from control names + levels data +
	leveling.lua parameters; verify totals equal the pre-migration values.

## Phase B: spells and effects (schema v5)

- Effects engine `app/lib/effects.lua`: effect specs are small tables, applied to a context
	(`player`, optional `monster`, `in_fight`) and returning messages:
	`heal_hp`, `heal_mp`, `heal_tp`, `damage` (range), `sleep` (chance), `buff_attack_pct`,
	`buff_defense_pct`, `stat` (passive modifiers for gear: maxhp, maxmp, maxtp, strength,
	dexterity, attack, defense, exp_bonus_pct, gold_bonus_pct). Spell type 1–5 semantics and
	numbers are ported exactly (current fight rules, including the fixes already made).
- `spells`: `id, key, name, description, mp, effects (serialized), usable_in` (`town`,
	`fight`, `both`), `retired`. Content files per spell.
- `user_spells(user_id, spell_id, learned_level)` replaces `users.spells`; class files
	reference spells by key.
- Fight and town spell code go through the effects engine; behavior unchanged (tests prove
	it: existing fight/heal tests must pass unchanged except for URLs/ids if any).
- Migration v5: map spell types to effects, explode `users.spells` into rows.

## Phase C: items, inventory, derived stats (schema v6)

- `items`: `id, key, name, description, category` (`weapon`, `armor`, `shield`,
	`accessory`, `consumable`, `quest`, `misc`), `slot` (`weapon`, `armor`, `shield`,
	`accessory`, NULL), `price`, `attack`, `defense`, `modifiers` (effects of kind `stat`,
	active while equipped), `use_effects` (consumables), `max_stack` (1 for gear),
	`drop_level` (NULL = never dropped), `sellable`, `droppable`, `retired`.
- The original 33 items keep ids 1–33 (keys from names, e.g. `destiny_blade`); the 32 drops
	become accessory items 34–65 with `drop_level = mlevel` and their two attributes as
	modifiers. A couple of example consumables (e.g. Herb: heal 30 HP; Potion: heal 100 HP;
	Ether: heal 30 MP) and no quest items yet.
- `town_items(town_id, item_id)` replaces `towns.itemslist` (Bris already fixed).
- `user_items(id, user_id, item_id, qty, equipped)` where `equipped` is NULL (in the bag) or
	one of `weapon`, `armor`, `shield`, `accessory1..3`; UNIQUE (user_id, equipped).
- Inventory cap: `control.inventory_size` (default 12) bag stacks. Equipped items don't
	count; a stack counts once; quest items never count, so quests can't be blocked. Adding
	to an existing stack (below `max_stack`) is always allowed.
- Derived stats: users keep base stats (`base_maxhp, base_maxmp, base_maxtp, strength,
	dexterity`) grown by level-ups; effective stats = base + equipped modifiers, with
	attack = strength + Σ attack, defense = dexterity + Σ defense, exp/gold bonus = Σ.
	Computed once per request (`game.stats(user)`), shown everywhere, used by combat.
	current HP/MP/TP are clamped to the effective maxima after any equipment change.
	Fight uber buffs stay as they are.
- Shop (buy gear): the confirm page offers **"Buy (keep my <old> in the bag)"** and
	**"Buy and sell my <old> for N gold"** (sell-back = ceil(price/2); with the sell option the
	sell-back counts toward the price, as now). Keeping the old item needs a free bag slot.
	Buying a consumable puts it in the bag (stacking). Shops also buy any sellable bag item
	for ceil(price/2): a Sell section on the shop page.
- `/inventory`: equipped slots + bag grid (12, shows free slots), actions equip (accessories
	pick slot 1–3 or first free), unequip (needs a free bag slot), use (consumables, town-
	usable effects), discard (not quest items; confirm). Link from the left nav.
- Drops: victory drop roll picks a droppable item with `drop_level <= monster level` (same
	1-in-30 odds and level rule as now); the drop page offers "Take it" (into the bag) or
	"Leave it"; if the bag is full, it lists bag items to discard first or leave the drop.
- Fight: "Use item" select of usable consumables (fight-usable effects); costs the turn like
	a spell, monster acts after.
- Migration v6: create items rows for drops (34+), map weaponid/armorid/shieldid and
	slot1..3id + dropcode to user_items / new ids, towns.itemslist → town_items, and convert
	stored stats to base stats by subtracting the equipped items' contributions (verify:
	recomputed effective stats equal the stored ones for every user before dropping columns).

## Tests (every phase)

- Content validation and sync: add/change/remove a content file in the test's app copy →
	next request sees it (hot sync), retired rows keep references, overrides survive sync,
	reset-to-file works, invalid content reported by `dk check`.
- Migration from the previous frozen fixture and from v0 → latest equals a fresh install
	layout; data preserved; for phase C, effective stats before == after for seeded users.
- Gameplay equivalence: existing fight/town/playthrough tests keep passing (updated only for
	intentional UI/URL changes), plus new e2e for inventory, cap, consumables, shop options,
	drops, accessories.
