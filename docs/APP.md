# App developer guide

How the Lua app under `app/` and the templates under `templates/` fit together. Read
`PLAN.md` for the engine API, URL map, data model and fidelity rules, and `README.md` for
building and running. Game messages, formulas and data follow the original PHP game
v1.1.11; where the port deliberately differs, the code says so in a comment
(`legacy: …` for kept quirks, `fixed: …` for changes).

## Module layout

| Area | Lua | Templates / assets | Tests |
|---|---|---|---|
| Core | `app/main.lua`, `app/routes.lua`, `app/lib/*` | `templates/layout/{main,minimal,head,nav_left,nav_right}.html`, `templates/errors/*`, `public/css/dk.css`, `public/js/dk.js`, `public/images/*` | `tests/run.sh` (core checks), `tests/lua/test_{php,router}.lua` |
| Accounts | `app/routes/auth.lua`, `app/lib/{auth,session,csrf,mail}.lua` | `templates/auth/*` | `tests/run.sh` |
| Home (town / exploring view) | `app/routes/home.lua` | `templates/home/*` | `tests/run.sh` |
| Town, shop, explore, heal, character, map, babble | `app/routes/town.lua`, `app/town/*` | `templates/town/*`, `public/css/town.css` | `tests/e2e/town.sh` |
| Items, inventory, derived stats | `app/content/items/*.lua`, `app/lib/{items,inventory,stats}.lua`, `app/town/{inventory,shop}.lua`, `app/admin/items.lua` | `templates/town/{inventory,inventory_discard,shop,shop_buy}.html`, `templates/fight/drop*.html`, `templates/admin/item{,s}.html` | `tests/e2e/{inventory,town,fight}.sh`, `tests/lua/test_{items,stats,inventory}.lua` |
| Fight, victory, drops | `app/routes/fight.lua`, `app/fight/{combat,act}.lua`, `app/lib/leveling.lua` | `templates/fight/*`, `public/css/fight.css` | `tests/e2e/fight.sh`, `tests/lua/test_{fight,leveling}.lua` |
| Content (classes, spells, items) | `app/content/{classes,spells,items}/*.lua`, `app/lib/content/*`, `app/lib/{classes,spells,items}.lua`, `app/cli/{content,check}.lua`, `app/admin/{classes,spells,items,content}.lua` | `templates/admin/{class,classes,spell,spells,item,items,content_form,content_status}.html` | `tests/e2e/content.sh`, `tests/lua/test_{content,items}.lua` |
| Scripted spells and items (what they do) | `app/lib/{action,actors}.lua`, `app/lib/content/{sandbox,scripted}.lua`, `app/fight/act.lua` | | `tests/lua/test_action.lua` (+ `effects_original.lua`), `tests/e2e/content.sh` |
| Forum (boards), help, changelog | `app/routes/community.lua`, `app/community/{forum,help,changelog}.lua`, `app/lib/paging.lua` | `templates/community/{forum,help}/*`, `templates/community/changelog.html`, `public/css/community.css` | `tests/e2e/community.sh` |
| News (town box, `/news`, News board threads) | `app/lib/news.lua`, `app/community/news.lua`, `app/admin/news.lua` | `templates/community/news/*`, `templates/home/town.html`, `templates/admin/news.html` | `tests/e2e/news.sh`, `tests/lua/test_news.lua` |
| Admin panel | `app/routes/admin.lua`, `app/admin/*` | `templates/admin/*`, `templates/layout/admin.html`, `public/css/admin.css` | `tests/e2e/admin.sh` |
| Install / CLI / migrations | `app/install.lua`, `app/cli/{user,migrate}.lua`, `app/lib/migrations.lua`, `app/sql/*` | `templates/errors/503.html` | `tests/run.sh`, `tests/e2e/migrate.sh` (`tests/fixtures/{schema_v*,seed_v3,seed_v4,seed_v5,seed_v6}.sql`), `tests/lua/test_db.lua` |
| Whole game | | | `tests/e2e/playthrough.sh` |

Route modules (`app/routes/*.lua`) stay thin: they register routes and guards and call
into the feature's modules (`app/<feature>/*.lua`). Keep game rules that don't need the
database in pure functions (like `fight/combat.lua`) so they can be unit-tested. Shared
helpers belong in `app/lib/`: add one there rather than copying code between features.
Every layout links all five stylesheets, so prefix feature CSS classes to avoid clashes.
The project indents with tabs.

## Request lifecycle

`main.lua` handles each request (fresh Lua VM per request, so module-level state lives
for one request only):

1. The database's schema version (`PRAGMA user_version`) must be `migrations.VERSION`;
	 otherwise every request gets a 503 page saying to run `dk migrate` (or `dk install`).
2. `content_sync.check()` syncs the content files into the database when they changed
	 (one query when they didn't; see [Content](#content)).
3. `session.load(req)` reads the `dk_session` cookie. It sets `req.user` (the full `users`
	 row) and `req.session`, and updates `users.onlinetime`.
4. The router matches the method and path. No match gives a 404 page; the wrong method
	 gives a 405 page with an `Allow` header.
5. **Every POST must pass CSRF verification**, or the response is a 403 page. This check
	 runs before any guard or handler.
6. Guards run, then the handler runs. The handler returns a response table (or an HTML
	 string).
7. HEAD requests: the transaction is rolled back and queued cookies are dropped.
8. Cookies queued on `req.out_headers` are added to the response.

The whole request runs in one SQLite transaction (`BEGIN IMMEDIATE`). If a Lua error
escapes, `main.lua` rolls the transaction back, logs the traceback and renders a 500 page
(with the traceback when `dev = true`). Don't catch errors just to hide them, and never
issue `BEGIN`/`COMMIT` yourself.

## Routes

```lua
-- app/routes/town.lua (excerpt)
local auth = require("lib.auth")
local common = require("town.common")
local inn = require("town.inn")
local shop = require("town.shop")

return function(r)
	r:route({ "GET", "POST" }, "/inn", auth.game, common.not_fighting, inn.handle)
	r:get("/shop/buy/#id", auth.game, common.not_fighting, shop.confirm)   -- params.id
	r:post("/shop/buy/#id", auth.game, common.not_fighting, shop.buy)
end
```

- `r:get(pattern, guard..., handler)`, `r:post(...)`, `r:route({"GET","POST"}, ...)`.
	A trailing `/` is ignored. HEAD requests run the GET route, then `main.lua` rolls the
	transaction back and drops queued cookies, so HEAD never changes state.
- GETs should not change state. The deliberate exceptions are guarded by game state, so
	a reload is harmless: the `onlinetime`/session touch, `GET /fight` (monster pick, first
	strike, `currentfight` counter) and `GET /victory` (pays out once).
- Pattern segments: `:name` matches any one segment (string). `#name` matches digits
	only and gives an **integer**, so `/shop/buy/abc` is a 404. Params arrive as the
	handler's second argument and also as `req.params`.
- A guard is `function(req) -> nil | response`. Guards run left to right, and the first
	response stops the chain.
- Route modules run once at VM warm-up: **do not touch `dk.db` at module load or route
	registration time**.

### Guards (`lib/auth.lua`)

| Guard | Behaviour |
|---|---|
| `auth.login` | not logged in → 302 `/login` |
| `auth.game` | legacy index.php chain: not logged in → `/login`; `control.gameopen == 0` → "Game Closed" page; `verifyemail == 1` and not verified → `/verify`; `authlevel == 2` → 403 blocked page |
| `auth.admin` | not logged in → `/login`; `authlevel ~= 1` → 403 |

Use `auth.game` for every game page (town, fight, character, babble, news). The forum
routes use `forum.guard`, which wraps it.

### Request table

`req.method, req.path, req.target, req.query, req.form, req.cookies, req.headers`
(lowercase), `req.remote`, `req.body`, plus `req.user`, `req.session`, `req.params`.
Form and query values are raw strings. Validate them, and convert them with
`math.tointeger(tonumber(x))` or `php.intval(x)`. Checkbox and button presence:
`req.form.north ~= nil`.

## Responses (`lib/view.lua`)

| Call | Result |
|---|---|
| `view.page(req, title, "town/inn", ctx [, opts])` | renders `templates/town/inn.html` with `ctx`, then the layout |
| `view.message(req, title, html [, opts])` | layout around a **trusted HTML** snippet (port of legacy `display("text…")`); escape interpolated data with `dk.html()` |
| `view.error(req, status, title, text [, opts])` | error page; `text` is escaped |
| `view.not_found(req)`, `view.csrf_failed(req)`, `view.method_not_allowed(req, allow)` | stock error pages |
| `view.unavailable(req, text)` | standalone 503 page (no DB access; used for the schema check) |
| `view.redirect(url [, status])` | 302 (legacy `header("Location: …")`) |
| `view.text(body [, status])` | text/plain |
| `view.render(name, ctx, req)` | a rendered template string (for building fragments) |
| `view.layout(req, title, html, opts)` | wraps already-rendered HTML |

`opts`:

- `nav`: show the side columns and the logged-in top nav. Defaults to true when logged
	in. Legacy pages called with `display(..., false, false, false)` pass `nav = false`.
- `layout`: `"main"` (default) or `"minimal"`. Use `"minimal"` for popup and iframe
	pages (`/character`, `/map`, `/babble`). Any other name uses
	`templates/layout/<name>.html` (the admin panel uses `layout = "admin"`).
- `body_class`: extra class(es) on `<body>` for page-specific CSS. The help pages pass
	`{ layout = "minimal", nav = false, body_class = "help" }` for a full-width minimal
	page (`body.minimal.help` in `community.css`).
- `status`: the HTTP status.
- `headers`: extra `{name, value}` pairs.

The layout re-reads `req.user` from the DB before drawing the nav, so stats changed by
the handler show up straight away (legacy `display()` did the same). A handler that renders
stats itself after changing them reads the row again (`game.user(id)`).

Layout ctx, if you write your own layout: `title`, `content` (HTML), `body_class`,
`gamename`, `nav` (table or nil), `logged_in`, `version`, `build`, `elapsed()`,
`queries()`. Include
`{{{ include("layout/head") }}}` in `<head>` to get the CSS links (`dk.css` + the four
feature stylesheets) and `dk.js`.

## Templates

Syntax: see PLAN.md. Names resolve in this order: template locals, then `ctx`, then the
helpers `h`. `ctx` and `h` are not names you can use in a template, and identifiers
starting with `__` are reserved.

- `{{ expr }}` escapes the value; `nil` prints as an empty string. Use `{{{ expr }}}` only
	for HTML your own code built.
- **HTML-returning helpers need triple braces**: `{{{ csrf_field() }}}`,
	`{{{ include("x") }}}`, `{{{ nl2br(text) }}}`.
- Every POST form needs `{{{ csrf_field() }}}`, including the babble iframe form.
- Popups: `<a href="/character" target="_blank" data-popup="210x500">` (`dk.js` opens a
	sized window; without JS it's a normal link).
- Images: `/static/images/<file>`. A link-styled submit button:
	`<form class="inline" method="post" action="/x">{{{ csrf_field() }}}<button class="link">Text</button></form>`.
- Low numbers blink with `<span class="highlight blink">`. The CSS animation replaces
	`<blink>`.
- Shared CSS classes: `.title`, `.box` / `.box-body`, `.small`, `.light`, `.highlight`,
	`.error`, `.copyright`, `button.link`, `form.inline`.

### Helpers `h`

| Helper | |
|---|---|
| `escape` | `dk.html` |
| `include(name [, ctx])` | renders another template (defaults to the current ctx) → HTML |
| `csrf_field()` / `csrf_token()` | hidden input / raw token |
| `url(path, seg..., [query_table])` | `url("/forum/thread", 7, {start = 15})` → `/forum/thread/7?start=15` (segments urlencoded) |
| `number(n)` | PHP `number_format($n)`: `1234567` → `1,234,567` |
| `date(ts)` | PHP `date("F j, Y")` (legacy `prettydate`) |
| `datetime(ts)` | `Y-m-d H:i:s` (what legacy printed for raw MySQL datetimes) |
| `nl2br(s)` | escapes, then adds `<br />` → HTML |
| `req` | the request (`req.user`, `req.path`, …) |
| `php` | the `lib.php` module |
| `ipairs pairs next select type tostring tonumber string table math utf8 os.date os.time dk` | Lua builtins |

## Game helpers (`lib/game.lua`)

| Function | Returns |
|---|---|
| `game.control()` | control row (id 1), cached per request; `game.reload_control()` after updating it |
| `game.user(id)` | fresh users row |
| `game.town_at(lat, lon)`, `game.current_town(user)` | town row or nil (by coordinates) |
| `game.class_name(n)` | the class's name for a `users.charclass` value (nil if unknown); `lib/classes.lua` has the rest |
| `game.stats(user)` | the effective stats of a users row: `{ maxhp, maxmp, maxtp, strength, dexterity, attack, defense, exp_bonus_pct, gold_bonus_pct }` (see [Derived stats](#derived-stats)) |
| `game.player(user)` | a copy of the row with the effective stats under the original column names (`maxhp`, `attackpower`, `defensepower`, `expbonus`, `goldbonus`, ...): what the fight code and the spell and item actions (`lib/actors.lua`) take |
| `game.user_towns(user)` | town rows in `users.towns`, ordered by id |
| `game.latitude_str(n)`, `game.longitude_str(n)` | `5N`/`5S`, `3E`/`3W` |
| `game.statbar(cur, max)` | `{pct, height, color}` |
| `game.is_low(cur, max)` | `cur <= max / 5` |
| `game.forum_link()` | `/forum`, the external address, or nil |
| `game.online_users()` | users seen in the last 10 minutes (`id, charname`) |
| `game.nav(user)` | the table the side columns render |

## Classes (`lib/classes.lua`)

Rows of the `classes` table (synced from `app/content/classes/*.lua`, see
[Content](#content)), cached per request. `users.charclass` holds a `classes.id`.

| Function | Returns |
|---|---|
| `classes.playable()` | playable, non-retired classes in `sort` order (registration) |
| `classes.active()` | non-retired classes in `sort` order (help pages) |
| `classes.all()` | every class, retired ones too (admin) |
| `classes.get(id)`, `classes.find(id_or_key)`, `classes.name(id)` | a class row / its name, or nil |
| `classes.start_stats(c)` | the `users` columns of a new character of class `c` |
| `classes.levels(c)` | `{ [level] = { hp, mp, strength, dexterity, spells = { spell id, ... } } }` for levels 2-100 |
| `classes.reload()` | forget the cache (after a sync in the same request) |

## Leveling (`lib/leveling.lua`)

The experience needed per level, the TP gained per level and the HP bonus at milestone
levels are formulas, fitted to the original 1.1.11 levels table. The experience curve's
first step and the other per-level gains (base HP, MP, strength, dexterity, spells) are
per class, in the class content files; the admin panel shows them read-only per class.

- **Experience**: `step(n)`, the experience from level n to n + 1, starts at the class's
	`exp_base` (Mage 15, Warrior 18, Paladin 20); every later step is the previous one
	times a stage factor, rounded down, per the stages: `leveling.GLOBAL_STAGES`,
	`"2x2,1.5x8,1.25x5,1.125x28"` (×2 for 2 steps, ×1.5 for 8, ×1.25 for 5, ×1.125 for 28,
	the original Mage curve), then flat. A class file may set its own `exp_stages` (rare;
	`"1x1"` is a flat curve); empty or absent means the global stages, in the files, the
	`classes` table and overrides alike (`leveling.stages_of(class)`). `exp_for(class,
	level)` (`class`: a classes row or anything with `exp_base` and `exp_stages`) is the sum
	of the steps below the level (0 at level 1); level 100 is the cap, 16777215 (rewards
	stop just below it). The Mage is within 0.44% of the original table at every level; the
	Warrior and Paladin match the original up to level 44 and 17 (where the original gave
	them stages of their own) and need up to about 10% more after that.
- **TP** gained on reaching a level: `floor(level / 30) + 2`, except +1 at level 2 (level 1
	shows the table's starting 5, level 100 gains nothing). Exactly the original. The same
	for every class.
- **HP**: the class's gain plus `hp_bonus(level)`: +10 at levels 10/20/30, +15 at
	40/50/60, +20 at 70/80/90, +50 at 99 (the class files hold 0 there). Exactly the
	original. The same for every class.

The global rules are plain data at the top of the module (`leveling.GLOBAL_STAGES`,
`leveling.TP`, `leveling.HP_MILESTONES`); edit them and the next request uses them (hot reload): victory
level-ups (`combat.level_up`), "Next Level" on the character sheets, `/help/levels` and
the admin class pages. `tests/lua/test_leveling.lua` pins them and the stock class files
against a frozen copy of the original table (`tests/lua/levels_original.lua`), so update
its expectations with them. Moving thresholds needs no data fixup: a player whose
experience already covers the next level gets it (or several) on the next victory.

## Content

Classes, spells and items are **content**: Lua files in git, one per entity, hot-reloaded
like the code and synced into the database, where players' rows reference them by id.
Spells and consumables also carry code: what they do (see
[Scripting spells and items](#scripting-spells-and-items)).

```lua
-- app/content/classes/knight.lua: the file name is the key ("knight")
local levels = {}
for level = 2, 100 do levels[level] = { hp = 3, mp = 1, strength = 2, dexterity = 1 } end
levels[4].spells = { "heal" }            -- keys of the spells learned on reaching that level
return {
	name = "Knight",
	description = [[
Slow level-ups
High hit points]],                       -- one line per point on the help page
	sort = 4,                                -- registration/help order (default 0)
	playable = true,                         -- offered when registering (default true)
	start_hp = 20, start_mp = 0, start_tp = 10, start_strength = 6, start_dexterity = 4,
	exp_base = 22,                           -- the first experience step; exp_stages (optional,
	                                         -- "factor x steps,...") replaces the global curve
	levels = levels,                         -- every level 2-100: hp, mp, strength, dexterity
}                                          -- (default 0), spells (default none)
```

- **Files** `app/content/<kind>/<key>.lua` return a table. The key (file name) is
	`[a-z0-9_]+` and never changes once players may reference it: renaming means a new
	entity plus retiring the old one. A file runs in a restricted environment
	(`lib/content/sandbox.lua`: `math`, `string`, `table` and a few safe functions; no
	`dk`, `require`, `io`, `os`, no DB); loops, locals and functions are fine.
	`lib/content/load.lua` lists files with
	`dk.list_modules("content.classes")` (new files count without a restart) and validates
	them with the kind's schema (`lib/content/kinds/<kind>.lua`, field validators in
	`lib/content/schema.lua`): wrong types, missing or unknown fields and missing levels
	are errors naming the file, and so is a reference to an entity of another kind that
	has no file (a class listing an unknown or deleted spell key). `./dk check` validates
	every content file.
- **Sync** (`lib/content/sync.lua`): upsert every file entity by key (a new key gets the
	next id; existing rows keep theirs), mark rows whose file is gone `retired = 1` (never
	deleted: players keep their class), un-retire keys whose file is back, then apply the
	admin overrides. Kinds sync in `schema.KINDS` order (spells, classes, items: spells
	before classes, whose `class_spells` rows need the spell ids). The original classes
	keep ids 1-3, the original spells 1-19 and the items 1-68 (seeded in `seed.sql`).
- **When**: every request (`main.lua`) compares `meta.content_seen` with
	`<boot id>:<code-cache generation>` (`dk.vmstats()`): one query while nothing changed.
	After a restart or any app file change, the files are loaded and fingerprinted (sha256
	of a canonical serialization of the data plus a hash of each file's source, so a
	change of code alone counts too; `meta.content_fingerprint`); only a different
	fingerprint runs the sync, inside the request's transaction (a savepoint). `dk install`,
	`dk migrate` and `dk content sync` sync directly; `dk content status` reports.
- **Invalid content** never breaks the game: the database keeps the last good content,
	the error is logged (warn), stored in `meta.content_error` and shown on every admin
	page, and the next file change checks again. `dk content sync`, `dk migrate` and
	`dk install` fail (and change nothing) instead.
- **Overrides**: `content_overrides(kind, key, field, value)` hold per-server values that
	win over the file and survive syncs. The admin pages (`/admin/classes/#id`,
	`/admin/spells/#id`, `/admin/items/#id`, shared code in `admin/content.lua` and
	`templates/admin/content_form.html`) write them for the kind's `admin_fields` (classes:
	name, description, sort, playable, starting stats; spells: name, description, MP,
	power, numbers and message strings; items: see [Items](#items); a value equal to the
	file's deletes the override) and offer "reset to file". Field names are those of the
	flat form: `name`, `levels.17.hp`, `levels.17.spells` (`"heal,hurt"`), `power`,
	`data.min`, `messages.hit`, `messages.enemy.hit`, `modifiers.2.stat`.
- **Migrations into content**: a migration that turns old rows into content writes the
	old values into `content_adopt(kind, key, field, value)`; the next sync turns those
	that differ from the file (and are valid) into overrides (that is how schema version 4
	kept edited class names and levels data, version 5 edited spell names, MP and amounts,
	version 6 edited items and drops, and version 7 turned edited effect amounts into
	`power`).

Adding a class: copy `app/content/classes/mage.lua` to `app/content/classes/<key>.lua`,
edit it, run `./dk check`; the class shows up on the registration page on the next page
load. Deleting the file retires the class. Adding a kind: a `kinds/<kind>.lua` module
(`fields` with types, `field(name)`, `admin_fields(flat)`, optional
`validate_extra`/`write_children`), its table (`id`, `key` UNIQUE, the field columns,
`retired`) and an entry in `schema.KINDS` (in sync order: kinds others reference first).
A field of type `keys` with `refs = "<kind>"` lists keys of another kind (checked by
`load.all`); `write_children` maps them to ids. A kind with code uses
`lib/content/scripted.lua` (function fields, messages, data; `load.module(kind, key)`
gives the runtime the loaded file). Bump `load.FORMAT` when the flat form changes meaning.

## Spells

Spells are content (see [Content](#content)): `app/content/spells/<key>.lua`, synced into
`spells`. The original 19 keep ids 1-19 (keys from the names: `heal`, `revive`, `life`,
`breath`, `gaia`, `hurt`, `pain`, `maim`, `rend`, `chaos`, `sleep`, `dream`, `nightmare`,
`craze`, `rage`, `fury`, `ward`, `fend`, `barrier`).

```lua
-- app/content/spells/heal.lua (scripted: see Scripting spells and items)
return {
	name = "Heal",
	description = "Restores hit points, in a fight or out of it.",
	mp = 5,                       -- MP it costs (deducted after a successful cast)
	power = 10,                   -- the most HP it restores (what cast makes of it)
	usable_in = "both",           -- "fight" (default), "town" or "both"
	target = "self",              -- "enemy" (default) or "self"
	messages = {
		cast = "You have cast the %s spell, and gained %d Hit Points.",
		full = "Your Hit Points are already full. Please go back and try again.",
		full_town = "Your Hit Points are already full. You don't need to use a Healing spell now.",
	},
	can_cast = function(s)
		if s.caster.hp >= s.caster.maxhp then return s:refuse(s.in_fight and "full" or "full_town") end
	end,
	cast = function(s)
		s:say("cast", s.name, s.caster:heal("hp", s.power))
	end,
}
```

- `usable_in`: where it can be cast. `"town"` and `"both"` need `target = "self"`; they
	are the Fast Spells in the right column (`POST /spell/#id`, `town/heal.lua`), and the
	fight's spell list shows `"fight"` and `"both"` spells.
- The originals: heals (`heal` ... `gaia`: power = the HP restored), hurts (`hurt` ...
	`chaos`: damage `rand(power * 5/6, power)`, none if the monster is immune), sleeps
	(`sleep`, `dream`, `nightmare`: the monster stays asleep while `rand(1, 15) <= power`;
	immunity 2 stops it), damage buffs (`craze`, `rage`, `fury`: +power% damage) and
	defense buffs (`ward`, `fend`, `barrier`: -power% damage taken). Heals use inline
	functions, hurts and damage buffs free-standing ones.
- A class learns a spell when its file lists the key in `levels[N].spells`; victory
	level-ups (`combat.level_up`) add a `user_spells(user_id, spell_id, learned_level)` row.
	The admin user editor edits a character's spells as a list of keys (`learned_level`
	NULL: unknown).
- Deleting a spell file retires the spell: no class file may list it any more (`dk check`
	fails), characters who know it keep it but can no longer cast it (its code was the
	file), and the help page no longer lists it.
- Casting: `fight/act.lua` in fights, `town/heal.lua` outside; both check the spell is
	known (`spells.knows`), affordable and castable there (`spells.usable`), then run it
	(`action.perform`). Messages are the original game's.

`lib/spells.lua`: rows come back with `messages` and `data` decoded into tables.

| Function | Returns |
|---|---|
| `spells.get(id)` | a spells row (retired or not), or nil |
| `spells.active()`, `spells.all()` | non-retired spells (help) / every spell (admin), by id |
| `spells.known(user [, place])` | the spells `user` knows, by id; `place` `"town"` or `"fight"` keeps those castable there |
| `spells.knows(user, id)`, `spells.usable(spell, place)` | booleans (`usable`: per `usable_in`, and not retired) |
| `spells.learn(user_id, id, level)`, `spells.set_known(user_id, ids)` | teach one (known ones keep their level) / set the whole list |

Adding a spell: copy a file in `app/content/spells/` to `<key>.lua` (`hurt.lua` for an
attack, `heal.lua` for a heal, `rage.lua` for a buff), edit its data and code, list the key
in a class file's `levels[N].spells`, run `./dk check`. The next page load syncs both; the
spell appears on `/help/spells` and characters of that class learn it on reaching level N
(existing characters already past N don't get it retroactively; give it to them in the
admin user editor).

## Scripting spells and items

What a spell or a consumable *does* is Lua code in its content file; everything else in the
file is data. The data (name, description, MP cost, `power`, named numbers, message
strings) is synced into the database and admins can override it; the code stays in the
file and runs from there (`lib/content/load.lua` `load.module(kind, key)`, loaded once per
request). Functions are ordinary Lua values: a field may hold an inline `function ... end`
or a local function defined anywhere in the file, the two work the same.

```lua
-- app/content/spells/hurt.lua: a free-standing local function
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)   -- the original's rand(max * 5/6, max)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Hurt",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	mp = 5,
	power = 15,                  -- data: s.power (admin-overridable)
	messages = {                 -- data: said by key, s:say("hit", ...) (admin-overridable)
		hit = "You have cast the %s spell for %d damage.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {                  -- optional: the wording when a monster casts it
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
```

```lua
-- app/content/items/herb.lua: inline functions, a refusal
return {
	name = "Herb",
	description = "Restores 30 hit points, in a fight or out of it.",
	category = "consumable", price = 15, max_stack = 10,
	usable_in = "both",          -- "fight" (default), "town" or "both"
	target = "self",             -- "enemy" (default) or "self"
	power = 30,
	messages = {
		used = "You have used the %s, and gained %d Hit Points.",
		full = "Your Hit Points are already full. Please go back and try again.",
		full_town = "Your Hit Points are already full. You don't need to use the %s now.",
	},
	can_use = function(u)        -- nil, or a refusal: costs nothing
		if u.caster.hp >= u.caster.maxhp then return u:refuse(u.in_fight and "full" or "full_town", u.name) end
	end,
	use = function(u)
		u:say("used", u.name, u.caster:heal("hp", u.power))
	end,
}
```

**Fields.** Data: `power` (integer >= 0, default 0: what the code makes of it), `data`
(named integers, `data = { min = 3 }` → `s.data.min`), `messages` (strings, or functions
`function(s, ...) return text end`; `messages.enemy` holds the monster wordings),
`usable_in`, `target`, plus the kind's own fields (a spell's `mp`; an item's price, ...).
Behaviour: a spell needs `cast(s)`, a consumable `use(u)`; `can_cast(s)` / `can_use(u)` are
optional. Only consumables have these fields; gear stays declarative (modifiers, see
[Derived stats](#derived-stats)). `usable_in = "town"` or `"both"` needs
`target = "self"` (outside fights there is no enemy).

**The context** `s` (`lib/action.lua`, an object built per cast or use):

| | |
|---|---|
| `s.name`, `s.description`, `s.key`, `s.kind` | the entity (after overrides); kind `"spell"` or `"item"` |
| `s.power`, `s.mp`, `s.data.<name>` | its numbers (after overrides) |
| `s.messages` | its messages: the stored strings (after overrides) and the file's functions; `s.messages.enemy` |
| `s.caster`, `s.target` | combatant handles: who acts, who it is aimed at (`target = "self"`: the caster; `"enemy"`: the monster, nil outside fights) |
| `s.in_fight`, `s.by_player` | whether in a fight; whether the player acts (false for a monster) |
| `s:roll(min, max)` | `php.rand` semantics (arguments truncated to integers, swapped when min > max, inclusive); the only dice (`math.random` is not available) |
| `s:say(msg, ...)` | adds a line: `msg` is a message key (`"hit"`: uses the overridable text), a format text or a function; the rest are `string.format` arguments (`%s`, `%d`, `%%`) |
| `s:refuse(msg, ...)` | a refusal (same arguments): `return` it from `can_cast`/`can_use` (or from `cast`/`use`) and nothing happens, nothing is spent |

**Combatants** (`s.caster`, `s.target`; the player and, from Phase E, monsters and summons
alike) have read-only fields `name`, `is_player`, `level`, `hp`, `maxhp`, `mp`, `maxmp`,
`tp`, `maxtp`, `attack`, `defense`, `strength`, `dexterity`, `immune` (0, 1: hurt spells,
2: hurt and sleep), `asleep`, `sleep_chance`, `uber_damage`, `uber_defense`, and methods:

| | |
|---|---|
| `:heal(stat, n)` | restores up to `n` of `"hp"`, `"mp"` or `"tp"`, never above the maximum (and never lowering a value above it); returns what it restored |
| `:hurt(n)` | takes `n` HP (may go below 0; the fight decides who died); returns `n` |
| `:spend(stat, n)` | uses up `n` of a stat (a cost) |
| `:buff(kind, pct)` | `"damage"`: +pct% damage dealt, `"defense"`: -pct% damage taken, until the end of the fight (the player only, for now) |
| `:sleep(chance)` | asleep; stays asleep while `rand(1, 15) <= chance` on each of its turns (monsters only, for now) |

Amounts are whole numbers >= 0; anything else is an error. The handle's numbers follow its
own changes during the action (heal, then read `hp`).

**Running an action** (`action.perform`): the framework checks the place (`usable_in`,
retired; the caller's message), runs `can_cast`/`can_use` (which may only decide: changing
anything there is an error), then `cast`/`use`, then deducts a spell's MP from the caster.
Nothing touches the game state meanwhile: the handles record an ordered list of events
(`heal`, `hurt`, `spend`, `buff`, `sleep`, `say`), and the caller applies them
(`lib/actors.lua` maps the player and the monster to the users row's fight columns) and
saves. A refusal, or an error, returns no events, so nothing changes and no MP, item or
turn is spent. Fights go through one entry point, `fight/act.lua` `act.run(state, action)`
(attack, spell or item: Phase E's round pipeline grows from it); town casting
(`town/heal.lua`) and the inventory's Use (`town/inventory.lua`) call `action.perform`
directly.

**Monsters acting.** Messages are worded for the player. When a monster is the caster,
`s:say("hit", ...)` uses `messages.enemy.hit` if there is one (same arguments); otherwise
the line becomes a generic "The Dragon casts Hurt." (items: "The Dragon uses the Potion.")
followed by what changed since the previous line ("You take 13 damage.", "The Dragon
recovers 10 Hit Points.", ...). No monster casts yet (Phase E); `tests/lua/test_action.lua`
covers both forms with monster casters.

**Errors** in content code (a typo, a bad format, `error(...)`, more than
`sandbox.BUDGET` instructions) are caught: logged as a warning with the traceback, the
player sees "Something went wrong with the Hurt spell. Please go back and try again.",
and nothing changes. A spell or consumable whose file is gone (retired) or invalid has no
code: it can't be cast or used (spells stay known, items stay in the bag).

**The environment.** Content files (every kind) run in a restricted environment
(`lib/content/sandbox.lua`): `math` (without `random`), `string`, `table`, `ipairs`,
`pairs`, `next`, `select`, `type`, `tostring`, `tonumber`, `assert`, `error`, `pcall`; no
`dk`, `require`, `io`, `os`, no database. Reading or setting any other global is an error,
so typos fail early. Each file gets its own copies of the libraries.

**Data, sync and overrides.** The flat form (see [Content](#content)) has `power`,
`data.<name>` and `messages.<key>` / `messages.enemy.<key>` (strings only; functions are
skipped); `lib/content/scripted.lua` validates them and stores messages and data as
`key=value` lines in the `messages` and `data` columns. Message texts may only use the
placeholders `%s`, `%d` and `%%`, and an override must keep the file's placeholders in the
same order (the admin form refuses others; the sync skips stale ones), so the code's
arguments still fit. The fingerprint includes a hash of every file's source, so an edit of
the code alone is noticed too.

Testing: `tests/lua/test_action.lua` runs the original 19 spells and the consumables
through the effects engine they replaced (a frozen copy, `tests/lua/effects_original.lua`)
and through their files over many seeded states, in fights and in town, and compares the
rolls (arguments and order), numbers, messages and refusals; it also covers the API with
fake modules (inline and free-standing functions, refusals, errors, runaway code, monster
casters).

## Items

Items are content (see [Content](#content)): `app/content/items/<key>.lua`, synced into
`items` (`lib/content/kinds/items.lua`). The original items keep ids 1-33 (keys from the
names: `stick`, `battle_axe`, `destiny_blade`, ...), the original drops are accessories
34-65 (`life_pebble` ... `fortune_drop`), and the Herb, Potion and Ether are 66-68.

```lua
-- app/content/items/destiny_blade.lua (gear: equipped in its slot)
return {
	name = "Destiny Blade",
	category = "weapon",        -- weapon, armor, shield, accessory (gear), consumable, quest, misc
	price = 50000,              -- shops sell it for this and buy it back for half (rounded up)
	attack = 250,               -- added to attack power while equipped (defense: to defense power)
	modifiers = { { kind = "stat", stat = "strength", amount = 50 } },   -- while equipped
}

-- app/content/items/demons_sin.lua (a monster drop)
return {
	name = "Demon's Sin",
	category = "accessory",     -- three accessory slots
	drop_level = 35,            -- monsters of level 35 and up may drop it
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = -50 },
		{ kind = "stat", stat = "strength", amount = 50 },
	},
}

-- app/content/items/potion.lua (a consumable: stacks in the bag; scripted like a spell,
-- see Scripting spells and items)
local function can_use(u)
	if u.caster.hp >= u.caster.maxhp then return u:refuse(u.in_fight and "full" or "full_town", u.name) end
end

local function use(u)
	u:say("used", u.name, u.caster:heal("hp", u.power))
end

return {
	name = "Potion",
	description = "Restores 100 hit points, in a fight or out of it.",
	category = "consumable",
	price = 60,
	max_stack = 10,             -- default 1 (gear must be 1)
	usable_in = "both",         -- "fight" (default), "town" or "both"
	target = "self",            -- "enemy" (default) or "self"
	power = 100,
	messages = {
		used = "You have used the %s, and gained %d Hit Points.",
		full = "Your Hit Points are already full. Please go back and try again.",
		full_town = "Your Hit Points are already full. You don't need to use the %s now.",
	},
	can_use = can_use,
	use = use,
}
```

- Other fields: `description`, `slot` (optional; it is the category for gear and absent
	otherwise), `sellable` (default: it has a price and isn't a quest item), `droppable`
	(default true; with a `drop_level`).
- Validation (`dk check`): gear has `max_stack` 1; only gear has attack, defense and
	modifiers; only consumables have `use`/`can_use`, `power`, `messages`, `data`,
	`usable_in` and `target`, and a consumable needs `use`; quest items can't be sellable;
	`sellable = true` needs a price.
- Admins override name, description, price, attack, defense, drop level, sellable,
	droppable, the modifiers' stats and amounts (an override can add a modifier: both its
	`modifiers.N.stat` and `.amount`) and a consumable's power, numbers and message strings
	at `/admin/items`.
- Modifier stats: `maxhp`, `maxmp`, `maxtp`, `strength`, `dexterity`, `attack`, `defense`,
	`exp_bonus_pct`, `gold_bonus_pct` (see [Derived stats](#derived-stats)).
- Use: a consumable can be used in town (from `/inventory`) and in fights ("Use Item",
	costs the turn like a spell; `fight/act.lua`) per its `usable_in`, with the player as
	caster. Refusals (already full, ...) and errors cost nothing; the item is taken from
	the bag only when it was used.
- Shops: `town_items(town_id, item_id)` is what a town sells (the admin town editor takes
	item keys). Weapons, armor and shields are equipped when bought: with an old item in the
	slot the player either keeps it in the bag (needs a free slot) or sells it back (its
	value counts toward the price). Everything else goes into the bag (`qty`, up to the room
	on a stack or a new one, and the gold). The Sell section buys any sellable bag item.
- Drops: a victory without a level-up drops an item 1 in 30 times, picked uniformly among
	the non-retired droppable items with `drop_level` at or below the monster's level (the
	original drops' odds). `users.dropcode` holds it until the player takes it into the bag
	(`/drop`; with a full bag, after discarding a bag item) or leaves it (moving on drops it
	too).
- Deleting an item file retires the item: shops stop selling it and monsters stop dropping
	it; characters keep theirs, and equipped retired items still count (a retired
	consumable can't be used: its code was the file).

`lib/items.lua`: rows come back with `modifiers` decoded into a list (`stats.decode_modifiers`)
and `messages` and `data` into tables.

| Function | Returns |
|---|---|
| `items.get(id)`, `items.by_key(key)` | an items row (retired or not), or nil |
| `items.active()`, `items.all()` | non-retired items (help) / every item (admin), by id |
| `items.town(town_id)`, `items.sold_in(town_id, id)`, `items.set_town(town_id, ids)`, `items.town_keys(town_id)` | a town's shop |
| `items.is_gear(item)`, `items.can_sell(item)`, `items.sell_price(item)`, `items.usable(item, place)` | rules |
| `items.attributes(item)`, `items.special_lines(item)`, `items.use_lines(item)`, `items.stat_line(stat, n)` | display lines (`"Attack Power +250"`, `"Gold Bonus +10%"`, `"Power 30"`) |

Adding an item: copy a file in `app/content/items/` to `<key>.lua`, edit it, run
`./dk check`. The next page load syncs it: give it a `drop_level` for monsters to drop it,
or add its key to a town's shop in the admin town editor. It shows up on `/help/items`.

## Inventory

`user_items(id, user_id, item_id, qty, equipped)`: a stack of one item, equipped in a slot
(`weapon`, `armor`, `shield`, `accessory1`-`accessory3`; one per slot) or in the bag
(`equipped` NULL). `lib/inventory.lua` holds the rules; the pure ones are unit-tested in
`tests/lua/test_inventory.lua`:

- The bag holds `control.inventory_size` stacks (default 12; "Bag Size" in the admin main
	settings). Equipped items don't count, a stack counts once, quest items never count (a
	quest can't be blocked by a full bag). Topping up a stack that isn't full
	(`qty < max_stack`) is always allowed (`inventory.room`).
- Equipping a bag item swaps it with what is in the slot (never needs a free slot);
	accessories pick slot 1-3 or the first free one. Unequipping needs room in the bag.
	After any equipment change current HP/MP/TP are clamped to the new maxima
	(`inventory.changed`).
- `/inventory` (link in the left nav, and "Bag: n / 12" in the right one) shows the slots
	and the bag grid (free slots drawn) with equip, unequip, use and discard (confirmation;
	how many for a stack; not quest items). Every action is a POST that renders the page
	with what happened.

| Function | |
|---|---|
| `inventory.entries(uid)`, `inventory.bag(uid)`, `inventory.equipped(uid)` (slot -> entry, cached per request), `inventory.entry(uid, id)`, `inventory.find(uid, item_id)` | entries `{ id, user_id, qty, equipped, item }` |
| `inventory.size()`, `inventory.used(bag)`, `inventory.free(bag, size)`, `inventory.room(item, bag, size)` | the cap |
| `inventory.add(uid, item, qty)`, `inventory.take(entry [, qty])` | into / out of the bag |
| `inventory.equip(uid, entry, slot)`, `inventory.equip_new(uid, item, slot)`, `inventory.unequip(uid, slot)`, `inventory.free_accessory_slot(uid)` | equipment (they clamp) |
| `inventory.stats(user)`, `inventory.names(uid)` | effective stats, equipped names per slot |

## Derived stats

`lib/stats.lua` (pure, `tests/lua/test_stats.lua`). The users row holds base stats:
`base_maxhp`, `base_maxmp`, `base_maxtp`, `strength`, `dexterity` (level-ups add to them)
and `base_attack`, `base_defense`, `base_exp_bonus`, `base_gold_bonus` (0 for new
characters; power neither strength, dexterity nor gear explains: schema version 6 kept the
original game's inconsistencies there, and admins can set them). Effective stats:

- maxhp/maxmp/maxtp, strength, dexterity = base + modifiers
- attack = strength + base_attack + the items' attack + attack modifiers
- defense = dexterity + base_defense + the items' defense + defense modifiers
- exp/gold bonus (percent) = base + modifiers

Stats that were UNSIGNED columns in the original never go below 0. `game.stats(user)`
computes them (the equipment is read once per request); every page, the fight and the
spell and item actions use them (`game.player(user)` for the latter, so
`fight/combat.lua` keeps the original formulas and names). Never store effective stats:
change base stats or equipment. `stats.solve(expected, mods)` is the inverse (base columns
that give expected effective stats), used by the migration.

Modifiers are gear's passive stat bonuses, plain data (not code: they are summed,
displayed and overridden): `{ kind = "stat", stat = "strength", amount = 50 }` (amount may
be negative), checked by `stats.validate_modifiers(list)`, stored as text by
`stats.encode_modifiers` (`"stat stat=strength amount=50; stat stat=maxhp amount=-50"`,
read back by `stats.decode_modifiers`) and summed by `stats.modifiers(list)`.

## Forum and news

- Boards are rows of `forums` (seeded: 1 General, 2 News). `forum` holds threads
	(`parent = 0`) and replies (`parent` = thread id); a reply copies its thread's `board`.
	Posts keep the charname in `author` (shown) and the account in `author_id`. Boards with
	`admin_threads = 1` only take new threads from administrators; anyone can reply.
- URLs: `/forum` (boards), `/forum/#board` (threads, `?start=N`), `/forum/#board/new`,
	`/forum/thread/#id`, `POST /forum/reply/#id`. `/forum/new` redirects to `/forum/1/new`.
	Every forum route uses `forum.guard` (logged out → message, `auth.game`, then
	`forumtype ~= 1` → "disabled").
- `lib/news.lua`: `news.post(user, title, content)` stores a post and starts its thread in
	the News board (`news.BOARD`) whatever the forum setting, so the threads are there if the
	forum is turned on later. An empty title becomes `news.default_title(content)`.
	`news.latest()` (town box: `excerpt`/`more` from `news.first_paragraph`), `news.get(id)`
	and `news.page(start, per)` return rows with `author` ("Unknown" when the account is gone)
	and, when `forumtype == 1` and the thread exists, `thread_url` / `thread_label`
	(`news.reply_label(n)`: "Reply", "1 reply", "N replies").
- Paging (`lib/paging.lua`): `paging.start(req)` reads `?start=N`; `paging.pages(base,
	start, per, total)` builds the links that `include("community/forum/pager")` renders.

## PHP compatibility (`lib/php.lua`)

Game mechanics must match legacy exactly. Use these helpers rather than ad-hoc Lua:

- `php.rand(min, max)`: like PHP, casts both arguments to int by truncating toward zero
	(`rand(maxdam * .5, maxdam)`), swaps them when `min > max`, and is inclusive. Uses
	`math.random`, which the engine seeds per VM.
- `php.ceil`, `php.floor` return integers. `php.round(x)` rounds half away from zero.
	`php.intval(x)` matches PHP's `(int)`: truncates and parses a leading numeric prefix.
- `php.mysql_int(x)` / `php.mysql_uint(x)`: the value MySQL **stored** when legacy wrote a
	float into an integer column (rounded; the unsigned version clamps to 0). SQLite would
	keep `12.5` as REAL, so convert floats before writing them to INTEGER columns.
- `php.str(v)`: PHP number-to-string (`1.0` → `"1"`, `1.2` → `"1.2"`). Use it to display
	numbers that may be floats.
- `php.number_format(n)`, `php.prettydate(ts)`, `php.datetime(ts)`.
- `php.nl2br(s)` does **not** escape. Templates use `h.nl2br`.
- `php.explode(sep, s)`, `php.implode(sep, t)`, `php.in_list(list, v)`: comma-list
	columns (`users.towns`) with PHP loose equality
	(`"3" == 3`). For example `"29.30"` matches neither 29 nor 30. Keep those columns'
	formats, including the leading `"0"`.
- `php.loose_eq(a, b)`, `php.trim(s)`, `php.is_email(s)`.

When legacy has a gameplay bug, keep the behaviour unless it's a security hole, and say so
in a comment.

## Database

- `dk.db:query(sql, ...)` returns rows, `:first` one row or nil, `:value` a scalar,
	`:exec` returns `changes, last_id`. Always use `?` parameters and **never concatenate
	user input**. Column identifiers come from whitelists only (a content kind's `fields`,
	or a fixed list in the code).
- Always call `dk.db` at call time. Don't cache it in a module-level local: it's attached
	per request and wrapped to count queries.
- Times are unix seconds (`dk.now()`): `regdate`, `onlinetime`, `postdate`,
	`newpostdate`, `posttime`.
- `username`, `charname` and `email` compare case-insensitively (`COLLATE NOCASE`, like
	MySQL). `users.verify` is TEXT: `'1'` means verified, anything else is the pending code.
- Store user text raw and escape it on output. Legacy HTML-escaped on input; we don't, so
	never put DB text in `{{{ }}}`.
- Schema: `app/sql/schema.sql`. Default data: `app/sql/seed.sql` and the content files
	(`app/content/`).
- Foreign keys are on (`PRAGMA foreign_keys=ON` per connection): delete children before
	parents, and reference users with `ON DELETE SET NULL` where the row should outlive them.

### Schema changes and migrations

`app/sql/schema.sql` is always the latest schema, and `dk install` stamps new databases
with `PRAGMA user_version = migrations.VERSION` (`app/lib/migrations.lua`). Databases from
before versioning are version 0. `dk migrate` runs the missing steps of
`migrations.STEPS` in order, stamping each version, all in the CLI's one transaction, then
runs `PRAGMA foreign_key_check` and the content sync. `main.lua` compares the version on every request and
serves a 503 page until the database matches.

Upgrade a server with `make migrate` (`dk check`, then `dk backup`, then `dk migrate`;
stops at the first failure) or `make deploy DEST=...`, which syncs the files and does the
same in DEST; `make run` does it before serving. `dk backup` writes a consistent copy to
`<db dir>/backups/<name>-YYYYMMDD-HHMMSS.db` even while the server runs; to roll back a
migration, stop the server and copy the backup over the database (see README
"Deployment").

To change the schema:

1. Edit `schema.sql` (and `seed.sql` if new rows are needed; write `INSERT INTO t (cols)
	 VALUES …` so seed lines survive later columns).
2. Append a step to `migrations.STEPS` that makes the same change to an existing database
	 plus any backfill (and, if it needs the synced content, an `after_sync` function, run
	 after the content sync that ends `dk migrate`). Write it in SQL against the schema of its time; don't call app
	 modules that query tables, since they follow the latest schema (pure helpers are fine).
	 SQLite can't `ADD COLUMN` with `REFERENCES` and a non-NULL default while foreign keys
	 are on: rebuild the table (create `t_new`, copy, drop, rename, recreate indexes), as
	 step 1 does for `forum`. `DROP COLUMN` works for columns that no index, constraint,
	 foreign key, trigger or view uses (step 2).
3. Extend `tests/e2e/migrate.sh`: it builds databases from the frozen schemas
	 `tests/fixtures/schema_v0.sql` (version 0) to `schema_v6.sql` (version 6) with the
	 game data of that time (`seed_v3.sql` to `seed_v6.sql`), migrates them, checks the data and compares
	 the column, foreign key and index layout with a fresh install. Never edit the
	 fixtures; add a `schema_vN.sql` copy of the old schema when a test needs to start
	 from version N.

## Sessions, CSRF, accounts

- `lib/session.lua`: `session.create(req, user_id, remember)`, `session.destroy(req)`,
	`session.destroy_user(user_id)`. The cookie `dk_session` holds 32 random bytes as hex
	(HttpOnly, SameSite=Lax, Path=/, plus Secure when `cookie_secure = true`). The DB
	stores only `sha256(token)`. Expiry slides: 1 day normally, 1 year with "remember me"
	(`Max-Age=31536000`).
- `lib/csrf.lua`: logged in, the token is `sessions.csrf`. Logged out, the forms use a
	signed double-submit: an HttpOnly `dk_csrf` cookie plus
	`hmac_sha256(config.secret, "csrf:" .. cookie)` in the form. The field is named
	`csrf`; the `X-CSRF-Token` header also works.
- `lib/auth.lua`: `auth.hash_password(pw)` → `pbkdf2$<iters>$<salt>$<hash>`,
	`auth.verify_password(pw, stored)` (constant time), `auth.random_letters(n)`.
- `lib/mail.lua`: `mail.send(to, subject, body)` writes `<outbox_dir>/<unix>-<rand>.eml`
	and returns true or false.

## End-to-end tests

`make test` runs `tests/run.sh`. It copies `app/`, `templates/` and `public/` into a
temp dir, installs a fresh DB (admin `admin` / `adminpass1`), starts the server on a
random port and runs the core checks (install, accounts, sessions, CSRF, HEAD, hot reload,
error rollback). Then it **sources every `tests/e2e/*.sh`** in sorted order, and finally
stops the server and fails on any `[error]` line or sanitizer report in its log.
`E2E_ONLY=town,fight tests/run.sh` runs only those scripts (the core checks always run).
Name a new script after its feature.

```bash
# tests/e2e/town.sh
t_section "inn"
t_jar town; t_register innkeeper pw1 inn@example.com Innkeeper; t_login innkeeper pw1
t_get /inn;   expect_status 200; expect_body 'Resting at the inn'
t_post /inn "csrf=$(t_csrf)&submit=Yes"; expect_body 'You wake up feeling refreshed'
t_sql "UPDATE users SET gold = 0 WHERE username = 'innkeeper'"
t_get /inn;   expect_body 'You do not have enough gold'
```

| Helper | |
|---|---|
| `t_section name` | label for failure messages |
| `t_jar name` | switch cookie jar (one per simulated browser); `t_reset_jar` |
| `t_get path [curl args]`, `t_post path 'a=1&b=2'`, `t_head path` | set `$STATUS`, `$BODY` (file), `$HEADERS` (file) |
| `t_form_submit path [name=value ...]` | re-POST the form in `$BODY` (text inputs + selects, csrf) with overrides |
| `t_csrf` | CSRF token from the last body |
| `t_enc value` | urlencode |
| `expect_status N`, `expect_body text`, `expect_no_body text`, `expect_header regex`, `expect_redirect /path` | assertions; `expect_body` matches raw HTML, so write `'` as `&#39;` |
| `t_ok` / `t_fail msg` | custom assertions |
| `t_sql "SQL"` | run SQL on the test DB (sqlite3 or python3); `t_has_sql` |
| `t_register user pass email charname [class]`, `t_login user pass [remember]`, `t_logout` | account shortcuts |
| `t_spells username "1,6"`, `$T_KNOWN` | set the spells a user knows; SQL expression for a users row's known spell ids (`SELECT $T_KNOWN FROM users ...` → `1,6`) |
| `t_give username key [qty [slot]]`, `t_items_clear username`, `$T_ITEMS` | give an item (into the bag, or equipped in `slot`); take all away; SQL expression for a users row's items (`stick@weapon,herbx3`) |
| `t_stats`, `expect_stats "maxhp maxmp maxtp str dex atk def" label` | the logged-in character's effective stats from `/character` |
| `t_mail_latest`, `t_mail_count` | outbox |
| `t_wait_for path text` | poll up to 5 s (hot reload) |
| `$BASE`, `$T` (temp dir), `$CONFIG`, `$OUTBOX`, `$ADMIN_USER`, `$ADMIN_PASS`, `$BIN`, `$ROOT` | the server log is `$T/server.log` (one access line per request) |

Lua unit tests: put `tests/lua/test_<name>.lua` returning `{ name = function() assert(...) end }`.
`run.sh` runs them inside a dk VM, where they can `require("lib.php")` and friends.

Keep scripts independent: use your own cookie jars and users, and restore any control
settings you change. `tests/run.sh -k` keeps the temp dir for debugging.

## Scratch dev server

A throwaway config keeps experiments away from your main database:

```bash
mkdir -p /tmp/dk-dev
cat > /tmp/dk-dev/config.lua <<'EOF'
return { port = 8081, db_path = "/tmp/dk-dev/dk.db",
				 outbox_dir = "/tmp/dk-dev/outbox", secret = "dev", dev = true,
				 pbkdf2_iterations = 1000 }
EOF
./dk install --config /tmp/dk-dev/config.lua --admin admin admin@example.com secret
./dk serve   --config /tmp/dk-dev/config.lua
./dk check   --config /tmp/dk-dev/config.lua   # compiles every module + template, validates content
./dk content --config /tmp/dk-dev/config.lua status
./dk user    --config /tmp/dk-dev/config.lua list
```

Edits to `app/**/*.lua` (content files included), `templates/**/*.html` and the app-level
keys of the config file apply on the next request. To build and test several checkouts side by side (or in CI),
give each its own object dir and binary: `make BUILD=build/x BIN=build/x/dk` and
`BIN=build/x/dk tests/run.sh`.

## Releases

The version shown in the footer is `view.GAME_VERSION` (`app/lib/view.lua`); it links to
`/changelog`. For a release, bump it and add an entry at the top of
`changelog.RELEASES` in `app/community/changelog.lua`, in the original changelog's style
(`m.d.yyyy` dates, one short past-tense line per change). Entries up to 1.1.11 are the
original `changelog.txt` and stay verbatim. Between releases, the version is the next one
with `-dev` (e.g. `2.1.0-dev`) and its entry has `date = "unreleased"` until the release.
