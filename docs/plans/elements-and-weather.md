# 3.2: elements, resistances, weather and fields

The plan for 3.2.0. Five parts, built in this order:

1. **Elements**: typed damage (fire, frost, ...) with resistances and weaknesses.
2. **Wards**: per-status resistance chances. These replace the old 0/1/2 `immune`.
3. **Clock and weather**: a global clock and a grid of weather computed from it. Storms
	 form around Midworld and drift toward Gilead, and open pages update when the weather
	 where the player stands changes.
4. **Fields**: effects on the whole battlefield (rain, heat, mud, night, or a spell's),
	 which combine with elements and statuses.
5. **Content**: monster fight patterns (weighted loadouts, spells, items, classes), new
	 spells, statuses, fields and items, then lore and flavor text.

Decisions (agreed with the owner):

- Weather is **computed from the clock**: a seeded, pure function of time and place, with
	no stored state. GETs stay pure, every worker agrees, nothing runs in the background,
	and the C engine doesn't change.
- A storm crosses from Midworld to Gilead in **about 2 hours** of real time.
- `immune` is **replaced** by `resist` and `ward` tables. The original monsters convert
	exactly, so the original game's fights stay equivalent (`tests/lua/test_round.lua`).
- Commits: one cohesive milestone at a time on `main`, in the history's `3.2: ...` style.
	The integrator alone commits.
- **One global clock, server-authoritative** (added during the work): a base tick of 10 s.
	The server runs the game's tick itself (a timer in the engine sending an internal
	request), so nothing a browser does (a refresh, a dropped connection, a closed tab)
	drives the clock or works around it. Fights run on it: a 30-second turn timer, a
	**Guard** action (also what a timed-out turn does), and statuses and allies that last
	ticks instead of turns, blocking ones (sleep, charging, recharging) included. Fights are
	**fully real time**: turns missed while away are guarded when their time comes, whether
	a page is open or not. This gives up the original game's dice match for fights with
	sleep; the tests switch to checking the new rules there.

## Invariants every part keeps

- **Equivalence.** A fight with no fields, no affinities and no new statuses rolls exactly
	the original game's dice in the same order, with the same lines. Neutral damage with
	no resistance and no field is multiplied by exactly 1, and nothing rolls a die unless
	the outcome is uncertain: a ward of 0 or 100 rolls nothing, and only 1-99 rolls.
	`tests/lua/test_round.lua`, `test_action.lua` and `test_spells.lua` stay green.
- **Pure GETs** (`tests/e2e/pure.sh`). Weather is never written. A GET only computes it.
- **Saved fight data is names and plain values only** (`state.encode`), never code.
- **Content stays declarative where it can be displayed**: resistances, wards and field
	modifiers are data, so the help pages, tooltips and admin can show and override them.
	Code (hooks) is only for behaviour that can't be data.
- Monster dice stay out of speech and weather: weather is hashed, never rolled.

## 1. Elements

`app/lib/elements.lua` (pure; `lib/action.lua` and `fight/*` both use it).

- `elements.LIST`: `neutral`, `fire`, `frost`, `lightning`, `water`, `wind`, `earth`,
	`holy`, `shadow`, `arcane`, `poison`, each with a display name. `neutral` is the
	default. Weapons, armor and melee attacks are neutral unless they say otherwise.
- **Resistance** is a percent per element, clamped to -100..200: positive resists,
	negative is a weakness, 100 is immunity, and above 100 absorbs (the excess heals). It
	is summed from every source: the monster or summon file's `resist = { fire = 50,
	frost = -50 }`, gear modifiers `{ kind = "resist", element = "fire", amount = 25 }`,
	and statuses' declarative `resist = { ... }` field (a buff like a fire ward).
- **The damage formula**, the only one, used by attacks, spells and status ticks:

	```
	field_pct = sum of the active fields' damage[element] (percent, may be negative)
	scaled    = floor(n * (100 + field_pct) / 100)          (never below 0)
	dealt     = floor(scaled * (100 - resist) / 100)          (resist < 100)
	          = 0                                             (resist = 100: immune)
	healed    = floor(scaled * (resist - 100) / 100)          (resist > 100: absorbs)
	```

	A hit that dealt at least 1 before resistance and isn't resisted fully deals at least
	1. With `field_pct = 0` and `resist = 0` the result is `n`: equivalence.
- **The API for content**: `target:hurt(n [, element])` returns what it really dealt (0
	when immune; an absorbing target heals instead and it returns 0). Spells print the
	returned amount. `h:resist(element)` returns the summed percent, and
	`h:immune_to(element)` returns `resist >= 100`. Status hooks
	`modify_damage_dealt(t, damage, element)` and `modify_damage_taken(t, damage, element)`
	get the element as their third argument.
- **Attacks**: weapons may set `element = "fire"` (gear field). The player's attack is the
	weapon's element. Monsters may set `attack_element`, and summons `element`.
- **Lines**: an attack or spell against a weakness or a resistance adds a short line
	after its damage line ("It is weak to fire!", "It resists frost.", "It absorbs the
	lightning!"). The words come from `elements.lua`, never rolled.

## 2. Wards (status resistance) and the end of `immune`

- **A ward** is a percent chance, 0-100 (clamped), that a status doesn't take hold, keyed
	by status key: `ward = { sleep = 100, poison = 30 }` on a monster or summon file, gear
	modifiers `{ kind = "ward", status = "sleep", amount = 25 }`, and statuses' declarative
	`ward = { ... }`. 0 never resists and 100 always does, both without a roll; 1-99 rolls
	`rand(1, 100) <= ward` with the action's dice.
- `h:afflict(key, params)` and `h:sleep(chance)` return true when the status took hold,
	false when a ward or a field stopped it. `h:ward(key)` reads the percent. Spells say
	"resisted" lines from the return value.
- **`immune` goes away**: from monster files, the monsters kind, handles, help and admin.
	The originals convert exactly: `immune = 1` becomes `resist = { arcane = 100 }`, and
	`immune = 2` becomes `resist = { arcane = 100 }, ward = { sleep = 100 }`. The original
	hurt spells (Hurt, Pain, Maim, Rend, Chaos, Magic Bolt) are `arcane` and say their
	"immune" message when `target:immune_to("arcane")`. The sleep spells say theirs when
	the ward stops them. A schema step drops the column (or keeps it unused if dropping
	isn't possible) and turns admin overrides of `immune` into `resist`/`ward` overrides.
- The 3.1 spells that checked `immune ~= 0` get real elements: Ember, Inferno, Cinder
	Lash and Fire Flask are fire; Frostbite and Whiteout frost; Spark and Lightning Lance
	lightning; Rockfall earth; Dawnstrike and Judgement holy; Withering and Curse shadow;
	Poison, Venom, Plague and Acid Vial poison; Magic Bolt, Starfall and the hurts arcane.
	Physical warrior strikes (Cleave, Reaver, Blood Strike, Finishing Blow) are neutral and
	no longer check immunity. Status ticks are typed too: burning is fire, poison and venom
	are poison, and withering is shadow.
- **Monster classes**: a monster may say `class = "mage"`. Its loadout then gains every
	spell that class learns at or below the monster's level and that is castable in fights
	(weight 1 each, `when` none). Its own `spells` entries for the same keys override the
	weight and `when`. It still pays MP from `maxmp` unless `uses_mp = false`.

Where it shows: `/help/monsters` (resistances, weaknesses and wards instead of
"Immunity"), monster tooltips, the character sheet (the player's resistances and wards
from gear and statuses), item lines ("Fire Resistance +25%", "Sleep Ward +25%"), and the
admin monster editor (`resist.<element>` and `ward.<status>` overridable).

## 3. Clock and weather

`app/lib/clock.lua` and `app/lib/weather.lua`: pure functions of `(latitude, longitude,
now)` plus a fixed seed. Nothing is stored and nothing runs in the background.

- **The clock** (`clock.lua`, the game's one source of time): a base tick of 10 s
	(`clock.TICK`); the weather moves every 6 ticks (a minute). A game day lasts 2 real
	hours, in four phases: `dawn`, `day`, `dusk`, `night` (night about a quarter of it).
- **The grid**: the map (-250..250, `control.gamesize`) in cells of 10 x 10 tiles. Each
	cell has a base climate from its place (fog more likely at dawn in the low south-west
	toward Narcissa; heat by day toward Endworld; snow instead of rain north of latitude
	150, around Hambry and Gilead) and the time of day.
- **Storms**: every 20 minutes there is a storm slot. A hash of the seed and the slot
	decides whether a storm forms (about 3 in 5), its size (squall, storm or great storm:
	a radius of roughly 8 to 40 tiles), its origin (within 30 tiles of Midworld) and a
	slight wobble on its heading. It travels toward Gilead (200, -200) at a speed that
	crosses in about 2 hours. It grows for its first part, holds, then weakens and breaks
	over Gilead. Storm positions are closed-form functions of time, so `weather.at` looks
	only at the few slots whose storms can be alive (about 6), with one hash each.
- **Weather at a tile**: `weather.at(lat, lon, now)` returns `{ sky, ground, time, storm,
	near }`. Sky is one of `clear`, `sun`, `heat`, `overcast`, `fog`, `drizzle`, `rain`,
	`downpour`, `thunderstorm`, `snow`, `blizzard`; inside a storm it goes by distance from
	the centre over the radius (core, body, fringe), and snow replaces rain in the cold
	north. Ground is one of `dry`, `wet`, `mud`, `snow`, `ice`: mud where rain or worse
	passed within the last ~20 minutes (closed-form closest approach), and snow or ice
	where snow fell. Time is the phase. `storm` is the storm overhead (`{ size, name }`)
	or nil, and `near` is the nearest storm within ~40 tiles that isn't overhead (`{
	direction = "south-east", distance }`), for "thunder rumbles to the south-east".
- **Changes**: `weather.change(lat, lon, now)` compares the weather step before with now
	and returns a flavor line when something changed (the sky, the ground, the phase, a
	storm coming near or going). `weather.describe(w)` is the standing description. The
	server tick asks whether a tile's weather changed between two times. The words live in
	`app/lib/weather_lines.lua`: several variants per transition, picked by hash (no
	dice), so a reload shows the same line.
- **Showing it**: the Location box (`loc` region) shows the weather and the time of day
	(an icon, a label and a tooltip with the description). The exploring page shows the
	change line when the weather changed this tick, or when the player stepped into
	different weather. The fight page shows the battlefield (part 4).
- **Real time**: the server tick (section 6) publishes `stale` to each online player whose
	tile's weather changed, and live.js already turns that into `DK.refresh()`, so only what
	changed comes. No client timer: the server decides when.
- **Cost**: `weather.at` must stay cheap enough to run on every page (a few
	microseconds). Measure it in its unit test.

## 4. Fields

A **field** is an effect on the whole battlefield, for everyone in the fight. It is a
content kind (`app/content/fields/<key>.lua`, table `fields`, synced and overridable like
statuses; `lib/content/kinds/fields.lua`).

```lua
-- app/content/fields/downpour.lua
return {
	name = "Downpour",
	description = "Hard rain: fire is weak, lightning strong, and no fire can catch.",
	lore = [[...]],
	icon = "downpour",
	group = "sky",                    -- sky | ground | time | aura: one field per group
	damage = { fire = -40, lightning = 25, water = 15 },   -- percent, by element
	statuses = {                      -- how statuses behave under it
		burning = { blocked = true },   -- can't take hold
		-- other forms: { ticks = -1 } (lasts 1 tick less, at least 1),
		-- { scale = { amount = 150 } } (a data value at 150%),
		-- { chance = 50 } (takes hold 50% of the time: rolls)
	},
	stats = { dexterity = -10 },      -- percent on every combatant's stat (attack, defense, strength, dexterity)
	messages = { begins = "...", ends = "...", blocked = "The rain puts the fire out before it can catch." },
	on_tick = function(e) ... end,    -- optional code on each tick it is up (a storm's lightning)
}
```

- **The fields of a fight** come from two sources. The world's: the weather at the
	player's tile, followed on every tick (`sky` -> the field of the same key for `sun`,
	`heat`, `fog`, `rain`, `downpour`, `thunderstorm`, `snow`, `blizzard`; ground `mud`
	-> `mud`, `ice` -> `ice`; time `night` -> `night`). And spells': `s:field(key, {
	ticks = n })` (a field spell, by the player or a monster), which displaces the world's
	field of the same group for its ticks. After it ends, the weather's field comes back.
	`aura` fields come only from spells (`consecrated`, `miasma`, ...).
- **Weather moving mid-fight**: on each tick the fight compares the world's fields with
	those it has (`f.data`). The differences become lines (the field's `begins` / `ends`,
	or the weather's change line) with `field` events for `fight.js`. A field spell in
	effect hides the change in its group until it ends. Because every action first catches
	the fight up to now, a spell cast just as the rain clears meets a clear sky: its burn
	takes hold.
- **Combinations** (all in one place, `fight/fields.lua`): damage multiplies through the
	element formula's `field_pct`. Statuses: `blocked` stops a status from taking hold (with
	the field's `blocked` line), a ward is rolled only after that, then `ticks` and `scale`
	adjust the params it is applied with. The status keeps its adjusted values: rain
	starting later doesn't shorten a burn already burning. `stats` adjusts the handles'
	numbers that formulas read (`combat.lua` sees the adjusted dexterity). Equivalence
	holds with no fields.
- **Shown**: on the fight page, a "Battlefield" line under the monster with each field's
	icon and name and a tooltip (description, modifiers as lines: "Fire damage -40%",
	"Burning can't take hold"); the help pages list fields (`/help/fields`); fight events
	gain `field = { { key, name, change = "add" | "remove" } }`.
- **The first fields** (content, part 5): `sun`, `heat`, `fog`, `rain`, `downpour`,
	`thunderstorm`, `snow`, `blizzard`, `mud`, `ice`, `night`, and aura fields for spells.

## 5. Content

- **Monster affinities** (`resist` / `ward` for every monster, consistent by family: slimes,
	ravens, elementals, dragons, liches, demons, ...).
- **Fight patterns**: weighted loadouts with `when` conditions (HP thresholds, round
	rotations, the player's statuses, the battlefield), spells, items, equipment, and
	classes for monsters that would plausibly have them (`magician`, `sorceror`, `wizard`,
	`warlock` as mages; knights as paladins or warriors). Not every monster needs unique
	mechanics. Each pattern should be readable from its file.
- **New spells, statuses, fields and items** to support them: elemental spells, field
	spells (Rain Call, Sunfire, Consecrate, ...), elemental ward statuses, resistance gear,
	and the 11 world fields.
- **Lore and flavor**: lore for every new entity, speech touches for new mechanics, and the
	weather lines (several variants per transition and per standing state).

## 6. The server tick and fights in real time

- **The server tick** (C: `src/app.c`, `src/http.c`): every 10 s, on the tick boundary,
	the engine sends an internal request down the ordinary request path (a pool VM, the
	transaction and its write lock, events published after the commit, errors logged), so
	the tick needs no machinery of its own. The C side marks it internal (`req.internal`,
	say), so no network request can pose as it, and its route refuses anything else. The
	Lua side, `app/lib/tick.lua` `tick.run(now)`, advances everything due: fights, world
	statuses, and weather pushes. Its work per run is bounded; what is left over continues
	on the next run. After the server was down, the next runs catch up, because time ran
	on.
- **Fights on the clock**: each fight saves the last tick it processed and the player's
	turn deadline. Advancing a fight to tick n plays every tick in order: the fields follow
	the weather; statuses tick and run out; allies count down and leave; a charge releases
	when its ticks are up, even between the player's turns; sleep rolls to wake. A turn
	whose deadline passed is played as a **Guard** round at its deadline ("You hesitate,
	and raise your guard."), whether a page is open or not. That is fully real time: a
	player who walks away keeps guarding, every 30 seconds, until the fight ends.
- **Turns**: the player's turn starts when the previous round ends, and its deadline is 30
	s later (`3 ticks`). A turn the player can't act in (asleep, charging, recharging) ends
	at the next tick instead of waiting out the 30 s. Monsters act in the round after the
	player's action, guard or skipped turn, as before.
- **Actions catch up first**: `POST /fight` advances the fight to now (the same code the
	tick runs), then plays the action. So a spell cast just after the rain cleared meets the
	clear sky, whether or not the tick has run yet.
- **Durations are ticks**: statuses and allies last `ticks`, not turns (the content field
	and the params are renamed: `turns` becomes `ticks`). Their hooks run on each tick
	(`on_tick`), which replaces `tick_on` (`turn_start`, `turn_end`). The status chips show
	time left. World statuses (outside fights) tick on the clock too, not on map moves.
	They still can't take the last hit point. As a start one turn becomes one tick, and the
	content phases tune the numbers.
- **Guard**: a fight action, on the hotbar's key 9 (fixed, like 1 Attack and 0 Run; the
	player's own keys become 2-8, and what sat on 9 moves to a free key or off the bar in a
	schema step). It costs the turn and puts on `guarding` (helpful: damage taken -25%,
	until the player's next turn begins). A timed-out turn is a Guard.
- **The turn timer on the page**: the fight page carries the deadline and the server's
	time (`data-turn-ends`, `data-now`: the page works out its clock's offset). From 20 s
	on, `fight.js` shows a quiet warning (a thin bar draining under the hotbar, say), and
	nothing more. It is display only: the page never sends the timeout. The server does.
- **Pushing**: when the tick changed a fight, or the weather at an online player's tile,
	it publishes `stale` on `user:<id>`. live.js refreshes the page, and the fight page
	shows the lines the tick added (kept in the fight's log). GETs stay pure: they show the
	fight as the tick last left it, at most one tick old.
- **Tests**: the clock can be pinned (test routes only). `POST /__test/tick` runs the
	server tick at a given time, so e2e tests step time exactly. A C test checks that the
	timer fires and that a network request can't pose as the tick.
- **Equivalence**: fights without statuses and without timeouts still roll the original
	game's dice. Sleep's match with the original is retired: its tests check the new rules.

## Phases and ownership

| Phase | Who | Owns |
|---|---|---|
| A. Elements, wards, monster classes | Opus (worktree `3.2-elements`) | `lib/elements.lua`, `lib/action.lua`, `lib/stats.lua`, `fight/*` (combat, engine, act, state, monster), content kinds (monsters, items, statuses, summons), every content file that used `immune`, the help and admin pages for monsters, migrations, their tests |
| B. Clock and weather | Opus (worktree `3.2-weather`) | `lib/clock.lua`, `lib/weather.lua`, `lib/weather_lines.lua`, `templates/layout/nav_left.html` (`loc`), `templates/home/explore.html`, CSS for them, their tests |
| D0-D3. Monster design | Sonnet (no repo edits) | design documents in `/tmp/opencode/dk-design/` |
| T. The server tick, fights in real time, Guard | Opus, after A and B | the C timer, `lib/tick.lua`, the fight's clock (durations in ticks, catch-up, timeouts), Guard and the hotbar's key 9, the turn timer on the page, pushes |
| C. Fields | Opus, after T | `fields` kind, `fight/fields.lua`, fields on the tick, fight page and events, `/help/fields` |
| E. New spells, statuses, fields, items | Sonnet, after C | new content files from the designs' wish lists |
| D'. Monster files | Sonnet, after E | `app/content/monsters/*.lua` patterns |
| F. Lore and flavor | Haiku, last | `lore` fields, `weather_lines.lua` variants, speech touches |

Each phase documents itself in `docs/APP.md` (its own section) and keeps `make test`
green. The integrator reviews each diff, writes the changelog entry
(`app/community/changelog.lua`, version `3.2.0-dev`) and commits.
