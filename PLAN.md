# Dragon Knight → C + Lua rewrite plan

Branch: `c-lua-rewrite`. The original PHP 4 / MySQL game (v1.1.11) lived in `legacy/` as
the reference implementation during the rewrite and is deleted after the QA phase.

**Status: all phases complete** (engine, app foundation, features, integration & QA).
Developer documentation: `README.md` (overview, CLI, workflow) and `docs/APP.md` (app
conventions).

## Goals

- One self-contained binary `./dk`: a hand-written HTTP/1.1 server in C, embedding
	**Lua 5.5.1** and **SQLite 3.54.1** (both vendored under `vendor/`, unmodified).
	Those are the only two dependencies. No libc extras beyond POSIX + Linux syscalls
	(getrandom, inotify, eventfd are fine).
- All game behavior lives in Lua under `app/`; all markup lives in templates under
	`templates/`. **Editing either takes effect on the next browser refresh** — no rebuild,
	no restart.
- **Fresh Lua VM per request** (share-nothing, like PHP), served from a pool of
	pre-warmed spare VMs, so the hot path never pays for VM construction.
- Clean URLs + modern HTML5/CSS, same look & feel (three-column layout, original image
	assets) and **identical game mechanics** (formulas, odds, data).
- Fix the original's security problems: parameterized SQL everywhere, HTML escaping by
	default, PBKDF2 passwords, server-side sessions, CSRF tokens on every POST.

## Repository layout

```
Makefile              builds ./dk; `make test`; BUILD=dir / BIN=path for isolated builds
config.example.lua    runtime config template (copy to config.lua, gitignored)
vendor/lua/           Lua 5.5.1 src/ (+ doc/manual.html — §8 lists 5.4→5.5 changes)
vendor/sqlite/        sqlite3.c / sqlite3.h amalgamation
vendor/VERSIONS       provenance + checksums
src/                  C engine
  util.[ch]           sbuf, url/html encode, logging, time, read_file
  crypto.[ch]         sha256, hmac, pbkdf2, getrandom, ct_equal, hex
  tmpl.[ch]           template -> Lua source compiler
  config.[ch]         loads config.lua in a sandboxed throwaway state
  http.[ch]           poll() I/O thread + worker threads + static files
  codecache.[ch]      bytecode cache + inotify watcher + generation counter
  vmpool.[ch]         warm spare VMs, warmer/reaper thread
  bind.h              dk Lua API (bind_dk.c), SQLite binding (bind_db.c), db.c
  app.c               dk_hooks glue: worker_init opens DB; handle = acquire VM → bind_handle → release
  main.c              CLI: `dk serve`, `dk install`, `dk migrate`, `dk content`, `dk user`, `dk check`,
                      `dk version`
app/                  Lua application (hot-reloaded)
  main.lua            returns handler(req) -> res (session, routing, CSRF, errors, HEAD)
  routes.lua          route table assembly (requires the route modules listed in it)
  routes/             thin route modules: auth, home, town, fight, community, admin
  lib/                router, session, cookie, csrf, auth, view, game, php, mail, dbcount,
                      news, paging, migrations (schema versions), leveling, classes,
                      spells, items, inventory, stats (derived stats), effects (the
                      effects engine), content/ (content loader, schemas, sync)
  content/            content files: classes/, spells/, items/ <key>.lua (synced into the DB)
  town/               inn, shop, inventory, maps, travel, explore, heal, character/map, babble
  fight/              combat.lua: the dice and formulas (pure functions, unit-tested)
  community/          forum (boards), news archive, help pages, changelog
  admin/              admin control panel (settings, news, classes, spells, items, generic CRUD editor)
  cli/user.lua        `dk user`
  cli/migrate.lua     `dk migrate`: runs lib/migrations.lua steps on an existing database
  cli/content.lua     `dk content sync|status`; cli/check.lua: content part of `dk check`
  install.lua         `dk install`: schema + seed data + admin user
  sql/schema.sql      SQLite schema
  sql/seed.sql        default game data ported 1:1 from legacy install.php
templates/            *.html templates (hot-reloaded): layout/ (main, minimal, admin, head,
                      nav), auth/, home/, town/, fight/, community/{forum,help}/, admin/, errors/
public/               served at /static/ (images/, css/, js/)
tests/c/              C unit tests (one main() per file, built by `make test`)
tests/lua/            Lua unit tests (run inside a dk VM by tests/run.sh)
tests/run.sh          end-to-end harness + core checks (bash + curl against a temp server)
tests/e2e/            feature scripts sourced by run.sh (admin, community, content, fight,
                      inventory, migrate, news, playthrough, town, ...)
tests/fixtures/       schema_v0.sql (pre-versioning) .. schema_v5.sql, seed_v3/v4/v5.sql: frozen
                      old schemas and data for the migration test
data/                 runtime (gitignored): dk.db, outbox/
```

## Architecture

```
            ┌──────────── I/O thread (poll) ────────────┐
 client ──▶ │ accept · read · parse · keep-alive · write │──▶ /static/* served directly
            └───────┬───────────────────────▲───────────┘
          request queue                 response + wakeup (eventfd)
            ┌───────▼───────────────────────┴───────────┐
            │ worker thread × N (own sqlite3* each)       │
            │  vm = vmpool_acquire()   ← ready queue      │
            │  bind_handle(vm, db, req, resp)             │
            │  vmpool_release(vm)      → reaper           │
            └───────▲───────────────────────┬────────────┘
                    │ warm VMs          retired VMs
            ┌───────┴───────────────────────▼────────────┐
            │ warmer thread: build spares from codecache, │
            │ lua_close retired VMs, rebuild on generation │
            └───────▲────────────────────────────────────┘
                    │ generation++ / cache drop
            ┌───────┴────────────────────────────────────┐
            │ watcher thread: inotify app/ templates/ cfg │
            └────────────────────────────────────────────┘
```

- **Per-request transaction**: `bind_handle` wraps the handler in `BEGIN IMMEDIATE …
	COMMIT` (ROLLBACK on error). This serializes writers (fine: handlers are sub-ms) and
	makes every request atomic, which the original's read-modify-write fight logic needs.
- **DB connections** are per worker and persistent (WAL). VMs are ephemeral; `dk.db`
	is bound to the worker's connection only for the one request. Statements are
	finalized before `db:query` returns (no statement objects escape to Lua). An optional
	per-connection prepared-statement cache keyed by SQL text is welcome.
- **RNG**: `lua_newstate(alloc, ud, seed)` gets a getrandom() seed (5.5 API has a seed
	param) and `math.randomseed` is called with getrandom values on every VM build.
- **Errors**: Lua errors → 500 with traceback when `config.dev`, otherwise a generic
	page; always logged with traceback.
- **Templates are compiled to Lua by C** (`tmpl.c`), then cached as bytecode like modules.

## Lua API (contract between C engine and Lua app)

Global `dk` table installed in every VM:

| API | Description |
|---|---|
| `dk.db:query(sql, ...)` | array of rows; each row `{colname = value}`. `?` positional params. |
| `dk.db:first(sql, ...)` | first row table or `nil` |
| `dk.db:value(sql, ...)` | first column of first row or `nil` |
| `dk.db:exec(sql, ...)` | returns `changes, last_insert_rowid` |
| `dk.db:exec_script(sql)` | run multiple `;`-separated statements, no params (install only) |
| `dk.render(name, ctx)` | render `templates/<name>.html` with ctx; returns string |
| `dk.html(s)` | HTML-escape (`nil` → `""`, non-strings via `tostring`) |
| `dk.urlencode(s)` / `dk.urldecode(s)` | percent encoding |
| `dk.crypto.sha256(s)` | raw 32 bytes |
| `dk.crypto.hmac_sha256(key, msg)` | raw 32 bytes |
| `dk.crypto.pbkdf2(pass, salt, iters, len)` | raw bytes |
| `dk.crypto.random(n)` | n CSPRNG bytes |
| `dk.crypto.hex(s)` | lowercase hex |
| `dk.crypto.eq(a, b)` | constant-time string equality (false if lengths differ) |
| `dk.now()` | unix seconds (integer) |
| `dk.clock()` | monotonic seconds (float) |
| `dk.request_start` | `dk.clock()` value when the request began (page timing) |
| `dk.log(level, msg)` | level: `"info"|"warn"|"error"` |
| `dk.config` | the table returned by config.lua (re-read per VM build → hot) |
| `dk.vmstats()` | table of vmpool stats, `generation` (code cache) and `boot_id` (random per process) |
| `dk.list_modules(prefix)` | sorted module names of the `*.lua` files directly under `app/<prefix as path>` (`"content.classes"` → `{"content.classes.mage", ...}`); read live, so new files count at once |
| `require(name)` | loads `app/<name with . → />.lua` from codecache; `package.path`/`cpath` disabled |

DB value mapping: `nil`→NULL, boolean→0/1, integer→INTEGER, float→REAL, string→TEXT;
results: INTEGER→integer, REAL→float, TEXT/BLOB→string, NULL→`nil` (absent key).
SQL errors raise a Lua error with the SQLite message and the SQL text.

**Request** passed to the handler:

```lua
req = {
	method = "POST", path = "/shop/buy/3", target = "/shop/buy/3?x=1",
	query = { x = "1" },          -- decoded; duplicate keys: last wins
	form = { ... },               -- decoded application/x-www-form-urlencoded body
	cookies = { name = "value" },
	headers = { ["user-agent"] = "..." },   -- lowercase names
	remote = "127.0.0.1",
	body = "raw body",
}
```

**Response** returned by the handler:

```lua
return {
	status = 200,                                    -- default 200
	headers = { {"Content-Type", "text/html; charset=utf-8"}, {"Set-Cookie", "..."} },
	body = "...",
}
```

The C side adds `Content-Length`, `Date`, `Server: dk`, `Connection`, and drops HEAD
bodies. Bodies other than
urlencoded (e.g. multipart) → the C side passes `form = {}`; the app doesn't need uploads.

## Template language (`templates/**/*.html`)

```
{{ expr }}          HTML-escaped output of a Lua expression (nil → "")
{{{ expr }}}        raw output (trusted HTML only)
{% stmt %}          Lua statements: {% if x then %} … {% elseif y then %} … {% else %} … {% end %}
                    {% for _, it in ipairs(items) do %} … {% end %}   {% local n = #items %}
{# comment #}       dropped
{%- / -%}           trim: '{%-' strips whitespace before the tag back to and including the
                    previous newline; '-%}' strips whitespace after the tag through the next
                    newline. Same for '{{-' / '-}}'.
```

- Name resolution inside a template: `ctx` first, then helpers `h`, then nothing (globals
	like `ipairs`, `string`, `math`, `os.date`, `tostring`, `dk` are included in `h` by the
	Lua view layer). Assigning to a bare name writes to a template-local scratch table.
- Helpers provided by `app/lib/view.lua` (`h`): `include(name [, ctx])` (renders another
	template, defaulting to the current ctx), `url(...)`, `csrf_field()`, `number(n)`
	(thousands separators, like PHP `number_format`), `date(ts)` ("F j, Y"),
	`nl2br(s)` (escapes, then converts newlines), plus the Lua globals above.
- Generated Lua must keep line numbers aligned with the template and use the chunk name
	`@templates/<name>.html`; a syntax error reports `<name>:<line>: message`.
- Layout pattern: handlers call `view.page(req, title, "town/index", ctx)` which renders
	the inner template then `layout/main` with nav columns. Popup-style pages use
	`layout/minimal`.

## URL map (legacy → new)

All player actions are POST with a CSRF token. GETs that change state by design (kept
from the original; guarded by game state so a reload is harmless):

- every authenticated request touches `users.onlinetime` and slides the session expiry;
- `GET /fight` picks the monster when an encounter has just started (`currentfight = 1`),
	runs the monster's first strike, and bumps the `currentfight` counter;
- `GET /victory` pays the rewards (exp, gold, level-up or drop roll) once: it then resets
	`currentfight`/`currentmonster`, so a reload redirects.

HEAD is routed like GET, but `main.lua` rolls the request's transaction back (and drops
queued cookies), so HEAD never changes state.

| Legacy | New |
|---|---|
| `index.php` | `GET /` (town / exploring / redirect to `/fight`) |
| `login.php?do=login` | `GET/POST /login` |
| `login.php?do=logout` | `POST /logout` |
| `users.php?do=register` | `GET/POST /register` |
| `users.php?do=verify` | `GET/POST /verify` |
| `users.php?do=lostpassword` | `GET/POST /lostpassword` |
| `users.php?do=changepassword` | `GET/POST /changepassword` |
| `index.php?do=inn` | `GET/POST /inn` |
| `do=buy` / `buy2:id` / `buy3:id` | `GET /shop`, `GET /shop/buy/:id` (confirm), `POST /shop/buy/:id` (keep / sell the old item; qty for bag items) |
| `do=sell` | (dead in legacy — towns.php has no `sell()`); new: `POST /shop/sell/:id` (a bag entry, qty) |
| (new) | `GET /inventory`, `POST /inventory/equip/:id` (slot for accessories), `POST /inventory/unequip/:slot`, `POST /inventory/use/:id`, `GET/POST /inventory/discard/:id` |
| `do=maps` / `maps2:id` / `maps3:id` | `GET /maps`, `GET /maps/buy/:id`, `POST /maps/buy/:id` |
| `do=gotown:id` | `POST /travel/:id` |
| `do=move` | `POST /move` (button name north/south/east/west) |
| `do=fight` / `victory` / `drop` / `dead` | `GET/POST /fight` (fight, spell, item, run), `GET /victory`, `GET/POST /drop` (take, leave), `GET /dead` |
| `do=spell:id` | `POST /spell/:id` (heal spells out of combat) |
| `do=showchar` | `GET /character` (minimal layout, popup-friendly) |
| `do=onlinechar:id` | `GET /character/:id` |
| `do=showmap` | `GET /map` |
| `do=babblebox` | `GET/POST /babble` (iframe-able minimal page) |
| `do=ninja` | `GET /ninja` → 302 to the original shirt-ninja URL (keep the easter egg) |
| `forum.php` | `GET /forum` (boards), `GET /forum/:board[?start=n]`, `GET/POST /forum/:board/new`, `GET /forum/thread/:id[?start=n]`, `POST /forum/reply/:id` (`/forum/new` → `/forum/1/new`) |
| (new) | `GET /news[?start=n]`, `GET /news/:id` (news archive) |
| `help.php`, `help_items.php`, … | `GET /help`, `/help/items`, `/help/spells`, `/help/monsters`, `/help/levels` |
| `admin.php?do=…` | `/admin`, `/admin/settings`, `/admin/{towns,monsters,users}[/:id]`, `/admin/classes[/:id]` (was levels), `/admin/spells[/:id]`, `/admin/items[/:id]` (was items and drops; content overrides), `/admin/news` |
| `install.php`, `upgrade_*.php` | `./dk install` CLI; legacy upgrades dropped (fresh SQLite schema); `./dk migrate` for schema changes since |

Guard order for game routes (port of index.php header): not logged in → `/login`;
game closed → closed page; `verifyemail` on and not verified → `/verify`; banned
(authlevel 2) → blocked page.

## Data model

- Port every legacy table to SQLite without the `dk_` prefix: `babble, control, forum,
	items, monsters, news, spells, towns, users` (and `levels` until schema version 4,
	`drops` until 6), keeping column names so porting is mechanical. Add `sessions`.
- Forum boards: `forums(id, name, description, position, admin_threads)`, seeded with
	1 General and 2 News (`admin_threads = 1`: only admins start threads). `forum` gains
	`board` (→ `forums.id`, replies copy their thread's) and `author_id` (→ `users.id`,
	`author` keeps the charname for display). Index `forum (board, parent, newpostdate)`.
- `news` gains `title`, `author_id` (→ `users.id`) and `thread_id` (→ `forum.id`, the
	post's discussion thread in the News board, created with the post). References to users
	are `ON DELETE SET NULL`; foreign keys are enforced.
- No difficulty levels: `control.diff1name`…`diff3mod` and `users.difficulty` are dropped
	(schema version 2); everyone plays at the original Easy difficulty (no scaling).
- Content (schema version 4, `docs/APP.md` "Content"): character classes are Lua data
	files `app/content/classes/<key>.lua`, synced into `classes(id, key UNIQUE, name,
	description, sort, playable, start_hp, start_mp, start_tp, start_strength,
	start_dexterity, exp_base, exp_stages, retired)`, `class_levels(class_id, level, hp, mp,
	strength, dexterity)` (levels 2-100) and `class_spells(class_id, level, spell_id)`.
	`users.charclass` holds `classes.id` (1-3 are the original Mage, Warrior, Paladin).
	Rows are never deleted (a missing file retires its row). `content_overrides(kind, key,
	field, value)` are admin values that win over the files; `content_adopt` carries values
	of a migration into overrides; `meta(key, value)` holds the content fingerprint, the
	last check (`content_seen`) and error. Experience, TP gains and the milestone HP bonus
	are formulas in `app/lib/leveling.lua` (the first experience step per class, the stages
	global unless a class file sets `exp_stages`; an empty value means global); version 3
	dropped the old levels table's `_exp`/`_tp` columns, version 4 the table and
	`control.class1name..class3name`.
- Spells (schema version 5, `docs/APP.md` "Spells"): content files
	`app/content/spells/<key>.lua` synced into `spells(id, key UNIQUE, name, description,
	mp, usable_in ('town' | 'fight' | 'both'), effects, retired)`; `effects` is the spell's
	effect list as text (`app/lib/effects.lua`, e.g. `heal_hp amount=10`), replacing the
	old `type` and `attribute`. The original 19 spells keep ids 1-19. Class files list spell
	keys; `class_spells.spell_id` references `spells.id`. The spells a character knows are
	`user_spells(user_id → users ON DELETE CASCADE, spell_id → spells, learned_level)`
	(NULL level: unknown), replacing the `users.spells` comma list.
- Items (schema version 6, `docs/APP.md` "Items", "Inventory", "Derived stats"): content
	files `app/content/items/<key>.lua` synced into `items(id, key UNIQUE, name, description,
	category, slot, price, attack, defense, modifiers, use_effects, max_stack, drop_level,
	sellable, droppable, retired)` (`modifiers`/`use_effects`: effect lists as text). Items
	1-33 are the original items, 34-65 the original drops (accessories, `drop_level` = the
	old mlevel), 66-68 Herb, Potion, Ether; the `drops` table is gone. `town_items(town_id,
	item_id)` replaces `towns.itemslist`. `user_items(id, user_id → users ON DELETE CASCADE,
	item_id, qty, equipped)` (equipped: weapon, armor, shield, accessory1-3, or NULL for the
	bag; UNIQUE (user_id, equipped)) replaces weaponid..slot3id and the names;
	`control.inventory_size` (12) is the bag size. `users` keeps base stats: `base_maxhp`,
	`base_maxmp`, `base_maxtp` (were maxhp, maxmp, maxtp), `strength`, `dexterity`,
	`base_attack`, `base_defense`, `base_exp_bonus`, `base_gold_bonus` (attackpower,
	defensepower, expbonus, goldbonus are gone: derived from the equipment, `lib/stats.lua`).
	`users.dropcode` holds a pending drop's item id.
- Schema versions: `PRAGMA user_version` = `migrations.VERSION` (`app/lib/migrations.lua`);
	0 is the original port. `dk install` creates the latest schema, `dk migrate` upgrades
	older databases, and the app answers 503 while the versions differ.
- Times: store unix seconds INTEGER (`regdate`, `onlinetime`, `postdate`, `newpostdate`,
	`posttime`). Format in Lua.
- `users.password` = `pbkdf2$<iters>$<salt hex>$<hash hex>` (iters default 210000,
	overridable via `dk.config.pbkdf2_iterations` so tests can use a low value).
- CSRF: logged in, the token is the per-session random `sessions.csrf`; logged out
	(login/register/verify/lostpassword forms), a signed double-submit: HttpOnly cookie
	`dk_csrf` (random) plus `hmac_sha256(config.secret, "csrf:" .. cookie)` in the form.
	`main.lua` verifies every POST (field `csrf` or header `X-CSRF-Token`) before guards run.
- `sessions(token_hash TEXT PRIMARY KEY, user_id INTEGER, csrf TEXT, created INTEGER,
	expires INTEGER, remember INTEGER)`. Cookie `dk_session=<random 32-byte hex>`,
	`HttpOnly; SameSite=Lax; Path=/`, `Max-Age` 1 year when "remember me", else a
	session cookie (server-side expiry 1 day, sliding). Store only `sha256(token)`.
- Seed data in `app/sql/seed.sql` plus the class, spell and item content files match the
	original install.php "complete setup" exactly (all rows of drops, items, levels,
	monsters, spells, towns, control), minus the difficulty settings and the levels values
	that became formulas, plus the new consumables (Herb, Potion, Ether) in the shops.
- Email (registration verification, lost password) is written to
	`<outbox_dir>/<unix>-<rand>.eml` and logged; `control.verifyemail` defaults to 0.

## Mechanics fidelity

Game logic must match legacy PHP exactly. Helpers in `app/lib/php.lua`:

- `php.rand(min, max)`: PHP casts float args to int (truncate toward zero), and swaps if
	`min > max`; inclusive range via `math.random`.
- `php.ceil`, `php.number_format(n)`, `php.nl2br`, `php.prettydate(ts)` ("F j, Y").
- Preserve comma-list columns (`users.towns`) and their semantics (`users.spells` became
	`user_spells` in schema version 5, `towns.itemslist` became `town_items` and the item
	specials / drop attributes `"stat,value"` became stat modifiers in version 6, migrated
	with the same matching).
- When legacy has an obvious bug that affects gameplay, the behavior is kept unless it
	is a security hole or breaks the game, with a comment at the spot ("legacy: …" /
	"fixed: …").
- Deliberate gameplay changes (requested):
	- Bris sells its full item list.
	- In the shop the sell-back value of the replaced item counts toward the price.
	- Heal spells are refused when HP is already at or above max, also in fights (no MP
		cost, no monster turn).
	- Running away can fail ("blocked in front": monster turn, damage saved, normal death
		handling); a successful run clears the fight state.
	- `currentuberdamage`/`currentuberdefense` reset on a new fight, a successful run and
		death (as on victory).
	- `goldbonus` is a percentage of the gold gained; the gold cap warning mentions gold.
	- Death saves `currentmp` (no refund for a spell cast on the fatal turn).
	- A victory grants several levels when the experience covers them (up to 100).
	- Any equipment change clamps current HP/MP/TP to the new maxima.
	- The drop message only shows when a drop was picked.
	- The character sheet shows the next level's experience at level 99.
	- Unknown spell types are refused in fights (no MP cost, no monster turn).
	- Strength/dexterity from items count toward attack/defense power in any slot (stats
		are derived from base stats + equipment since schema version 6).
	- Inventory (version 6): a 12-slot bag, keep-or-sell when buying gear, selling bag
		items, drops into the bag, consumables (usable in fights, costing the turn).
- Dropped: the admin "page compression" switch (the server doesn't gzip). The internal
	forum is only reachable when `control.forumtype = 1`.

## Coding rules

- C11, `-Wall -Wextra` clean (warnings are bugs), no new dependencies, check every
	allocation and syscall result, no global mutable state without a mutex (except
	I/O-thread-only state). Keep functions small; comment only the non-obvious.
- Lua 5.5: `global` is a **reserved word**; for-loop control variables are **read-only**.
	Use `local` everywhere; modules return tables; no globals from app code.
- Never build SQL with string concatenation of user data. Always `?` params.
	(Identifiers like the level column `1_hp` may be chosen from a whitelist.)
- Templates escape by default; use `{{{ }}}` only for HTML built by trusted code.
- Indent with tabs.

## Phases

1. ✅ **Engine**: E1 base (`util`, `crypto`, `tmpl` + tests), E2 server (`config`, `http`
	 + tests), E3 runtime (`codecache`, `vmpool`, `bind_*`, `db`, `app`, `main` + tests).
2. ✅ **App foundation**: schema + seed, `dk install`, router, sessions, CSRF, auth pages,
	 layouts/nav, CSS, static assets, `lib/php.lua`, home dispatcher, `tests/run.sh`,
	 `docs/APP.md`.
3. ✅ **Features**: F1 town/explore/heal/character/map/babble, F2 fight, F3 forum/help/news,
	 F4 admin.
4. ✅ **Integration & QA**: playthrough + concurrency e2e, mechanics review against legacy,
	 HEAD made read-only, hot-reload checks, ASan/UBSan run, README rewrite, `.gitignore`;
	 `legacy/` deleted last.

## Definition of done

- `make && make test` green with `-Wall -Wextra` and no warnings; `make DEBUG=1 test`
	green under ASan/UBSan.
- `./dk install --admin <user> <email> <password>` then `./dk serve` gives a fully
	playable game: register, log in, explore, fight, level up, drops, inn, shop, maps,
	travel, heal spells, babble box, forum, help, admin panel.
- Editing any `app/**/*.lua`, `templates/**/*.html`, or app keys in `config.lua` is
	visible on the next refresh without restart.
- No SQL built from user input; every POST checks CSRF; output escaped by default.
