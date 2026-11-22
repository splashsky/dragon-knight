# App developer guide

How the Lua app under `app/` and the templates under `templates/` fit together. Read
`PLAN.md` for the engine API, URL map, data model and fidelity rules, and `README.md` for
building and running. Game messages, formulas and data follow the original PHP game
v1.1.11; where the port deliberately differs, the code says so in a comment
(`legacy: …` for kept quirks, `fixed: …` for changes).

## Module layout

| Area | Lua | Templates / assets | Tests |
|---|---|---|---|
| Core | `app/main.lua`, `app/routes.lua`, `app/lib/*`, `app/routes/test.lua` (test-only routes) | `templates/layout/{main,minimal,head,nav_left,nav_right}.html`, `templates/errors/*`, `public/css/dk.css`, `public/js/dk.js`, `public/images/*` | `tests/run.sh` (core checks), `tests/e2e/pure.sh` (pure GETs), `tests/lua/test_{php,router}.lua` |
| Live pages: chat, who's online, notices, broadcast banner | `app/lib/{chat,presence,notices,banner}.lua`, `app/town/babble.lua`, `app/routes/live.lua`, `app/admin/broadcast.lua` | `templates/layout/{chat,chat_posts,online,online_list,side_live,banner,live_attrs}.html`, `templates/town/babble.html`, `templates/admin/broadcast.html`, `public/js/live.js`, `public/js/windows.js` (the chat, map and character windows) | `tests/e2e/{chat,presence,notices}.sh`, `tests/lua/test_chat.lua` |
| Tooltips, lore | `app/lib/tips.lua`, `app/lib/view.lua` (`tip`, `paragraphs`), the kinds' `lore` field (`app/lib/content/schema.lua`) | `templates/tip/tip.html`, `public/js/tooltip.js`, `public/css/dk.css` (`.dk-tip`, `.tip-*`) | `tests/e2e/tips.sh`, `tests/js/test_tooltip.js`, `tests/lua/test_content.lua` |
| Themes, font | `app/lib/themes.lua`, `app/routes/theme.lua` | `templates/layout/{head,logo,theme_picker}.html`, `public/css/themes/*.css`, `public/images/themes/*`, `public/fonts/vollkorn/*` | `tests/e2e/theme.sh` |
| Accounts | `app/routes/auth.lua`, `app/lib/{auth,session,csrf,mail}.lua` | `templates/auth/*` | `tests/run.sh` |
| Home (town / exploring view) | `app/routes/home.lua` | `templates/home/*` | `tests/run.sh` |
| Clock and weather | `app/lib/{clock,weather,weather_lines}.lua`, `app/lib/game.lua` (`nav`), `app/routes/home.lua` (the exploring page) | `templates/layout/nav_left.html` (`weather`), `templates/home/explore.html`, `public/css/{dk,town}.css` | `tests/lua/test_{clock,weather}.lua`, `tests/e2e/weather.sh` |
| Terrain and the world map | `app/lib/{terrain,terrain_lines}.lua`, `app/lib/terrain/world.lua` (the world: generated data), `app/lib/terrain/{generator_v1,picture}.lua` (not loaded by the game), `tools/world.{sh,lua}`, `app/town/character.lua` (`/map`), `app/lib/game.lua` (`land`), `app/routes/home.lua`, `app/fight/{fields,encounter,round}.lua`, `app/content/fields/{shallows,marsh,forest,hills,peaks,sand,cinders}.lua` | `templates/town/map.html`, `templates/home/explore.html`, `templates/layout/nav_left.html`, `public/images/world.svg` (generated), `public/css/{dk,town}.css`, `public/js/windows.js` | `tests/lua/test_terrain.lua`, `tests/lua/test_{weather,fields}.lua`, `tests/e2e/{terrain,town}.sh` |
| The server tick (fights in real time, world statuses and weather on the clock) | `src/http.c` (the timer), `app/lib/tick.lua`, `app/routes/tick.lua`, `app/fight/round.lua` (`round.advance`), `app/fight/encounter.lua` (`encounter.advance`), `app/lib/world.lua` (`world.advance`) | `templates/fight/clock.html`, `public/js/fight.js` (the turn's timer), `public/css/fight.css` | `tests/c/test_http.c`, `tests/lua/test_{tick,round}.lua`, `tests/e2e/tick.sh` |
| Fields (the battlefield: the weather's and spells' effects on a fight) | `app/fight/fields.lua`, `app/lib/fields.lua`, `app/lib/content/kinds/fields.lua`, `app/content/fields/*.lua`, `app/fight/{engine,round}.lua`, `app/community/help.lua` (`/help/fields`), `app/admin/effects.lua` | `templates/fight/battlefield.html`, `templates/community/help/fields.html`, `public/js/fight.js`, `public/css/fight.css`, `public/images/fields/*` | `tests/lua/test_fields.lua`, `tests/e2e/fields.sh` |
| Town, shop, explore, heal, character, map | `app/routes/town.lua`, `app/town/*` | `templates/town/*`, `public/css/town.css` | `tests/e2e/town.sh` |
| Items, inventory, derived stats | `app/content/items/*.lua`, `app/lib/{items,inventory,stats}.lua`, `app/town/{inventory,shop,inn}.lua`, `app/admin/items.lua` | `templates/town/{inventory,inventory_discard,shop,shop_buy,inn}.html`, `templates/fight/drop*.html`, `templates/admin/item{,s}.html`, `public/images/items/*` | `tests/e2e/{inventory,town,fight,wand}.sh`, `tests/lua/test_{items,stats,inventory}.lua` |
| Fight, victory, drops | `app/routes/fight.lua`, `app/fight/{combat,act,encounter}.lua`, `app/lib/leveling.lua` | `templates/fight/*`, `public/css/fight.css` | `tests/e2e/fight.sh`, `tests/lua/test_{fight,leveling}.lua` |
| Hotbar (the fight's number keys) | `app/lib/hotbar.lua`, `app/town/hotbar.lua`, `app/routes/fight.lua` (`hotbar_view`), `app/fight/encounter.lua` (settling) | `templates/fight/{fight,action}.html`, `templates/town/hotbar.html`, `public/js/hotbar.js`, `public/css/{fight,town}.css` | `tests/e2e/hotbar.sh`, `tests/e2e/browser.sh` |
| Smooth fights (fight events) | `app/fight/events.lua`, `app/routes/fight.lua` | `templates/fight/*`, `public/js/fight.js`, `public/css/fight.css` | `tests/e2e/fight_api.sh`, `tests/lua/test_round.lua`, `tests/e2e/browser.sh` |
| Fight engine (round pipeline, statuses, summons, AI, world statuses) | `app/fight/{state,engine,round,ai,act}.lua`, `app/lib/{statuses,summons,world}.lua`, `app/content/{statuses,summons}/*.lua`, `app/admin/effects.lua` | `templates/fight/{fight,statuses}.html`, `templates/admin/{effects,effect}.html` | `tests/lua/test_round.lua` (+ `fight_original.lua`, `fight_model.lua`, `spells_original.lua`), `tests/e2e/effects.sh` |
| Monsters (content with MP, equipment, items, spells) | `app/content/monsters/*.lua`, `app/lib/content/kinds/monsters.lua`, `app/lib/monsters.lua`, `app/fight/monster.lua`, `app/admin/effects.lua`, `app/community/help.lua` | `templates/community/help/monsters.html`, `templates/admin/{effects,effect}.html` | `tests/lua/test_monsters.lua`, `tests/e2e/monsters.sh` |
| Content (statuses, fields, summons, classes, spells, items, monsters) | `app/content/{statuses,fields,summons,classes,spells,items,monsters}/*.lua`, `app/lib/content/*`, `app/lib/{classes,spells,items,statuses,fields,summons,monsters}.lua`, `app/cli/{content,check}.lua`, `app/admin/{classes,spells,items,effects,content}.lua` | `templates/admin/{class,classes,spell,spells,item,items,effect,effects,content_form,content_status}.html` | `tests/e2e/content.sh`, `tests/lua/test_{content,items}.lua` |
| Scripted spells and items (what they do) | `app/lib/action.lua`, `app/lib/content/{sandbox,scripted}.lua`, `app/fight/{act,engine}.lua` | | `tests/lua/test_action.lua` (+ `effects_original.lua`), `tests/e2e/content.sh` |
| Forum (boards), help, changelog | `app/routes/community.lua`, `app/community/{forum,help,changelog}.lua`, `app/lib/paging.lua` | `templates/community/{forum,help}/*`, `templates/community/changelog.html`, `public/css/community.css` | `tests/e2e/community.sh` |
| News (town box, `/news`, News board threads) | `app/lib/news.lua`, `app/community/news.lua`, `app/admin/news.lua` | `templates/community/news/*`, `templates/home/town.html`, `templates/admin/news.html` | `tests/e2e/news.sh`, `tests/lua/test_news.lua` |
| Realtime (event streams) | `app/routes/live.lua`, `app/lib/json.lua` | | `tests/e2e/live.sh`, `tests/lua/test_json.lua`, `tests/c/test_hub.c` |
| Live client (regions, the wire format) | `app/lib/wire.lua`, `app/main.lua`, `app/lib/view.lua` (`region`, `view.layout`) | `templates/layout/*.html` (regions), `templates/layout/chat.html` | `tests/e2e/live_wire.sh` (`tests/wire.py`), `tests/lua/test_wire.lua` |
| Admin panel | `app/routes/admin.lua`, `app/admin/*` | `templates/admin/*`, `templates/layout/admin.html`, `public/css/admin.css` | `tests/e2e/admin.sh` |
| Install / CLI / migrations | `app/install.lua`, `app/cli/{user,migrate}.lua`, `app/lib/migrations.lua`, `app/sql/*` | `templates/errors/503.html` | `tests/run.sh`, `tests/e2e/migrate.sh` (`tests/fixtures/{schema_v*,seed_v*}.sql`), `tests/lua/test_db.lua` |
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
	 row) and `req.session`, and updates `users.onlinetime` (a player not marked online is
	 announced: see [Presence](#presence-whos-online)). Then the presence sweep runs when
	 one is due (once a minute).
4. The router matches the method and path. No match gives a 404 page; the wrong method
	 gives a 405 page with an `Allow` header.
5. **Every POST must pass CSRF verification**, or the response is a 403 page. This check
	 runs before any guard or handler. (The server's own tick, `req.tick`, has none: [The
	 server tick](#the-server-tick).)
6. Guards run, then the handler runs. The handler returns a response table (or an HTML
	 string).
7. HEAD requests: the transaction is rolled back and queued cookies are dropped.
8. Cookies queued on `req.out_headers` are added to the response.

The whole request runs in one SQLite transaction (`BEGIN IMMEDIATE`). If a Lua error
escapes, `main.lua` rolls the transaction back, logs the traceback and renders a 500 page
(with the traceback when `dev = true`). Don't catch errors just to hide them, and never
issue `BEGIN`/`COMMIT` yourself.

### What the engine does around a request

(The C side; `PLAN.md` "Architecture" has the diagram, `docs/PERF.md` the numbers.)

- **The VM.** Every request runs in a pool VM that was built once for the current code
	(`require "main"` and everything it requires ran then), snapshotted, and is restored to
	that snapshot with one memory copy after the request, with `math.random` reseeded. So
	module-level code runs once per code change, not per request, and nothing a request
	does (globals, module tables, caches in upvalues) is seen by the next one. A request
	may use up to `vm_memory_limit` of Lua memory (default 256 MiB): beyond that it fails
	with a Lua "not enough memory" error (a 500). Its garbage is rarely collected
	(`vm_gc_pause`): the restore drops it. A file left open is closed by its finalizer
	before the restore; still, close what you open.
- **The transaction.** Requests that use the database take turns on one in-process lock
	around `BEGIN IMMEDIATE … COMMIT`, so a long handler delays every other request:
	keep handlers short, and never wait inside one. WAL checkpoints happen on a
	background thread.
- **Queueing.** A request that waits longer than `queue_timeout_ms` (2 s) for a worker
	gets a `503` with `Retry-After: 1` without running; it is safe to retry (nothing was
	done).
- **Responses.** The worker writes the response to the socket itself; `/static/` files
	never reach Lua (cached in memory, `ETag`/`Last-Modified`, 304s). Access log lines are
	written by a background thread (`access_log = false` turns them off); `dk.log` lines
	too, in order.
- **Event streams.** A handler may answer with `{ sse = {...} }` instead of a page; the
	connection then stays open, held by the server, not by a worker or a VM (see
	[Realtime](#realtime-event-streams)). `dk.publish` events go out after the commit.
- **The server's tick.** Every 10 s, on the clock's tick boundary, the engine sends a
	request of its own, `POST /__tick`, down this same path (a worker, a pool VM, the
	transaction, events after the commit, errors logged): the game's clock moving (see
	[The server tick](#the-server-tick)). It has no connection, no access log line and no
	CSRF token: only the engine can mark a request as the tick (`req.tick`).
- **Metrics.** `/admin/server` (administrators) and `dk stats` show the server's counters:
	requests and latency buckets, queue wait, worker time, VM pool, time in SQLite and
	waiting for the write lock, checkpoints, static cache, event streams and subscribers
	per channel, memory. `make bench` loads a
	temporary install with scripted players (`tools/dkbench.c`, `docs/PERF.md`).

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
- **Pure GETs** (3.0): a GET (or HEAD) never changes the game. Only bookkeeping may
	write: the `onlinetime`/session touch, the presence join and sweep, the content sync and
	the CSRF cookie seed. So any page can be fetched again at any time (a reload,
	back/forward, the live client refreshing it) and shows the game as it is. What used to
	happen on a GET happens in the POST that causes it: an encounter begins (its monster
	picked, its first strike played) on the map move, a victory is paid in the winning
	round (`fight/encounter.lua`), and a finished fight is kept so `GET /fight` and `GET
	/victory` can show it again. Every `POST /fight` answers with a redirect to the page that
	shows what it did (Post/Redirect/Get): a reload never sends a command again.
	`tests/e2e/pure.sh` requests every GET route of the router
	(`GET /__test/routes` lists them) in every game state and fails if any game table
	changed; a new GET route has to be added to its list.
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
| `auth.game` | legacy index.php chain: not logged in → `/login`; `control.gameopen == 0` → "Game Closed" page; `verifyemail == 1` and not verified → `/verify`; blocked (`roles.is_blocked`, see [Roles](#roles)) → 403 blocked page |
| `auth.admin` | not logged in → `/login`; not an administrator (`roles.is_admin`) → 403 |

Use `auth.game` for every game page (town, fight, character, babble, news, `/live`). The forum
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
| `view.json(t [, status, headers])` | `application/json` (`lib/json.lua`), `Cache-Control: no-store`; `view.wants_json(req)`: the request sent `Accept: application/json` (live.js's fetch: the chat) |
| `view.back_path(req)` / `view.back_to(req [, fallback])` | this page's path and query (for a form's `back` field) / where to redirect after a form with `back`: that path if it is same-site with a GET route, else `fallback` (`/`) |
| `view.chat(req)` / `view.online()` | ctx for `layout/chat.html` / `layout/online.html`, or nil when the Babble Box / Who's Online is turned off |
| `view.render(name, ctx, req)` | a rendered template string (a partial for JSON; mind region markers: `wire.strip`) |
| `view.layout(req, title, html, opts)` | wraps already-rendered HTML |

`opts`:

- `nav`: show the side columns and the logged-in top nav. Defaults to true when logged
	in. Legacy pages called with `display(..., false, false, false)` pass `nav = false`.
- `layout`: `"main"` (default) or `"minimal"`. Use `"minimal"` for pages that stand alone
	(`/character`, `/map`: the floating windows' pages without JavaScript; help). Any other name uses
	`templates/layout/<name>.html` (the admin panel uses `layout = "admin"`).
- `body_class`: extra class(es) on `<body>` for page-specific CSS (the layouts also add
	`theme-<key>`, see [Themes](#themes)). The help pages pass
	`{ layout = "minimal", nav = false, body_class = "help" }` for a full-width minimal
	page (`body.minimal.help` in `community.css`).
- `status`: the HTTP status.
- `headers`: extra `{name, value}` pairs.

The layout re-reads `req.user` from the DB before drawing the nav, so stats changed by
the handler show up straight away (legacy `display()` did the same). A handler that renders
stats itself after changing them reads the row again (`game.user(id)`).

Layout ctx, if you write your own layout: `title`, `content` (HTML), `body_class`,
`theme` (the request's theme, see [Themes](#themes)), `gamename`, `nav` (table or nil),
`logged_in`, `version`, `build`, `elapsed()`, `queries()`, `banner` (the broadcast banner
or nil), `back` (`view.back_path`), `live` (logged in, not minimal: the page loads
live.js), `side` (with `nav`: the online count for the right column,
`layout/side_live.html`). `layout/head.html` loads every script on every page (`dk.js`,
`tooltip.js`, see [Tooltips](#tooltips), `modal.js`, see [Modals](#modals), `client.js`,
`scene.js`, see [Scenes](#scenes),
`live.js`, `windows.js`, see [Windows](#windows), `fight.js`, `hotbar.js`, see [Hotbar](#hotbar)): the head is the same
everywhere, so the live client never loads a page again for its scripts. The main layout marks the parts a script may
swap: `<aside class="dk-left" data-nav-left>`, `<main class="dk-middle" data-main>` and
`<div class="dk-nav-right" data-nav-right>` around `layout/nav_right` (not the whole right
column). Include `{{{ include("layout/head") }}}` in `<head>` to get the
CSS links (`dk.css` + the four feature stylesheets + the theme's), `dk.js` and, with
`live`, `live.js`; put `theme-{{ theme.key }}` in the `<body>` class followed by
`{{{ include("layout/live_attrs") }}}`, start the body with
`<div class="dk-banner-slot" data-banner-slot>{{{ include("layout/banner") }}}</div>`, and
use `{{{ logo() }}}` and `{{{ theme_picker() }}}`.

## Live client

(3.0, `docs/plans/live-client.md`.) Pages are plain HTML that works without JavaScript;
with it, the live client (`public/js/client.js`) sends links and forms with `fetch` and
the server answers with only the parts of the page that changed. Routes, guards, handlers
and templates don't change for it: the same code answers both ways.

**Regions.** A layout or template marks the parts of a page that change on their own:

```html
{{{ region("loc") }}}<section class="box" data-r="loc">...</section>{{{ endregion() }}}
```

`region(name)`/`endregion()` leave invisible markers around the element (`<\1loc>`,
`</\1>`; escaped text never contains `<`, so user data can't make one), and the element
carries the same name in `data-r` for the client to find it. Regions nest, names
(`[a-z][a-z0-9-]*`) are unique in a page; `root` is the `<body>` (attributes included) and
`head` the `<head>` contents but `<title>` (compared, never sent). The main layout has
`banner`, `topnav` (the header's links), `left` (`loc` with `weather`, `towns`, `functions`), `main` (on the
exploring page with `explore-land` and `explore-weather`), `right` (`charpanel`, `invpanel`,
`spellpanel`, `online-count`), `foot` (with `foot-time`, the timing line), `themes` (with
`theme-back`), and on `/babble` the chat's `chat` (with `chat-posts`, and `chat-form` with
`chat-back`); `minimal` and
`admin` have `banner`, `main` (and `foot`, `themes`). The `back` fields (the page's
address, different on every page) and the timing line (different on every request) are
regions of their own so that their parents stay the same. `lib/wire.lua` splits a
rendered page at the markers in one pass and hashes each region's **skeleton** (its HTML
with each child region replaced by a placeholder; 12 hex digits of SHA-256), so a hash
changes only when that region's own markup does. A full page loses the markers and carries
every hash on `<html data-h="head=… root=… loc=…">` (`{{{ hashes() }}}` in the layouts'
`<html>` tag). Every layout must load the same head (`layout/head.html` loads every script
on every page): a page whose head differs is loaded normally.

**Live requests.** A GET or POST with `X-DK-Live: 1`, and `X-DK-Have: name=hash ...` (the
regions the client shows). `main.lua` runs the route as always, then:

- a page from `view.layout` is answered with the regions whose hash differs from the
	client's (walking down from `root`: a region the client has is skipped and its children
	compared; one it lacks or has differently goes whole, but a region inside it that the
	client has with the same hash goes as a placeholder, `<template data-r-keep="name">`,
	and its own children are compared in turn: `wire.changed`);
- a redirect to one of the game's pages (a same-site path with a GET route) is **followed
	on the server**, up to 5 hops, each a fresh dispatch with the cookies set so far (login
	and logout work): a POST and the page it lands on are one round trip. A redirect
	elsewhere becomes `go`;
- a `head` that differs from the client's becomes `go` (load the page normally: a theme
	changed, or a deploy brought new scripts or stylesheets);
- an HTML page outside the layouts (the 500 and 503 pages) becomes `doc`; anything else
	(JSON, text, the event stream) is answered as it is. HEAD is never live.
- pages and live answers carry `Vary: X-DK-Live`.

**The wire format** (`application/x-dk-live`; `wire.encode`/`wire.decode`, `tests/wire.py`):
the line `DK1`, then frames `<op> [<arg> ...] <length>\n<payload>\n`. Lengths are in bytes
and payloads raw (HTML goes as HTML, nothing is escaped); clients skip ops they don't know.

| Op | Payload |
|---|---|
| `title <n>` | the document title |
| `url <n>` | the page's address (a GET's, or where a POST's redirects landed); absent for a page a POST answered with itself, which no GET shows (the client keeps its address) |
| `events <kind> <n>` | data for a player of that kind (JSON), played before the regions apply; from `opts.events = { { kind, json }, ... }` of `view.layout`/`view.page`, or `res.events` on a redirect |
| `region <name> <n>` | the region's element (outerHTML, children included, those the client has as placeholders; `root`: the `<body>`) |
| `hashes <n>` | the regions whose hash the client lacks or has differently (`name=hash`, space-separated), and `name=-` for those the page no longer has |
| `go <n>` | load this URL normally instead (empty: load the current address again) |
| `doc <n>` | a whole HTML document to show instead |

The HTTP status is the page's (a 404 page comes as a 404 with its regions).

**Adding a region.** Wrap the element in `region()`/`endregion()` and give it the same
`data-r`. Worth it for a part that changes often while the rest of its parent doesn't (a
box in a column). Markers must balance: a page that doesn't is an error with `dev = true`
(and loses its hashes otherwise). Partials rendered on their own for JSON (`/live/state`)
must not leave markers in their output (`wire.strip`).

### The client (`public/js/client.js`)

Loaded on every page (first of the page scripts), it runs where the page has `<html
data-h>` and the browser has `fetch`, `AbortController`, `TextDecoder`, `DOMParser` and
`history.pushState`; elsewhere nothing changes.

- **What it takes over.** Clicks on same-origin links (left button, no modifier keys, no
	`target` or `download`, not another `#hash` of the same page, not
	`/static/` or `/live`) and submits of same-origin urlencoded forms (the pressed button
	included). `data-native` on a link, a form or an ancestor keeps it native. Its click and
	submit listeners are on `window`: the other scripts' (on `document`) come first, and a
	form one of them handles itself (`preventDefault`: the chat, whose listener captures) is
	left alone.
- **Requests.** `X-DK-Live: 1` and `X-DK-Have` (its hash map: `<html data-h>`, then every
	answer's `hashes`). One at a time: a new GET aborts a running GET; anything started
	while a POST runs waits for its answer (a second submit of the same form is dropped).
	After 250 ms without an answer `<html class="dk-busy">` shows the progress bar
	(`.dk-progress`, a 2 px bar in the theme's link colour) and `data-r="main"` is
	`aria-busy`.
- **Applying an answer.** `events` players first (`DK.on("events:<kind>", fn)`, each
	returning a promise), then the `before` hooks (`DK.on("before", fn)`: `{ regions,
	from, to, user }`, the regions' names coming, the address on screen and the answer's,
	whether a link or form of the player's sent it rather than a refresh or back/forward;
	a promise too: `scene.js` fades the middle column out there), then each `region` is morphed into `[data-r=name]` (`root` into
	`<body>`), the hashes merged, the title set; after a POST the submitted form is
	`reset()`, so it shows what the server rendered (empty after success, the values the
	server put back after a refusal). Then the history entry: a new address is pushed (and
	scrolled to the top or its `#hash`, and announced to screen readers), the same address
	replaced (the scroll stays: a fight round). A page a POST answered with itself (no
	`url`) keeps the address on screen and is marked as such (`DK.view().post`). Focus lost
	with its element goes to the middle column.
- **The morph** changes only what differs: attributes, text, children matched by key
	(`data-r`, `id`, `data-k`, `data-id`) or by position and tag; `<template>` contents
	compared as HTML. A placeholder (`<template data-r-keep>`) is the page's own element,
	moved there untouched; in anything new that goes in, a region the page already shows
	(by name) is the page's own element, moved and morphed (a panel moving from one column
	to another would keep its scroll and typed text). Regions
	taken out while an answer applies are kept aside until it is done, for a later region of
	the same answer. It never removes elements marked `data-client` (the tooltip box, the
	toasts, the progress bar, the announcer: give anything a script adds to the page that
	attribute), never touches the live value of a control (typed text survives; only the
	form `reset()` above), and leaves `inert` (modal.js), `open` on `<details>` and tooltip.js's
	`data-tip-title` to the page's scripts.
- **History.** `history.scrollRestoration = "manual"`; each entry has a key, and its scroll
	is kept while the page lives (and in `history.state` for a reload). Back and forward
	are live GETs of the entry's address (safe: [pure GETs](#routes)), then its scroll.
- **Fallbacks.** A GET that fails, takes over 10 s, or answers with something else than the
	wire format is loaded natively. A POST that fails before its answer may or may not have
	happened: the address on screen is loaded natively, showing the game as it is. A POST
	answered with a non-wire document shows it as the browser would (`document.write`).
	`go` loads natively, `doc` shows the document. An answer with a region the page lacks
	(the page isn't what the server's hashes say) loads the address natively.
- **For other scripts**, `window.DK`: `visit(url)`; `refresh()` (the address on screen
	again, keeping the scroll: only what changed comes; a POST's own page keeps its middle
	column, which no GET shows, and updates the rest); `on("applied", fn)` (after an answer
	is on screen; `{ url, post }`); `on("events:<kind>", fn)`; `on("before", fn)`; `touched(el)` (the script
	changed the region `el` is in, e.g. a chat message added from an event: the next answer
	brings that region as the server has it); `view()`; `busy()`.

`tests/js/test_client.js` tests the pure parts (the frame reader, the hash map, which
addresses qualify); `tests/e2e/browser.sh` drives `tests/browser/client.js` in headless
Chrome, Edge or Chromium over the DevTools protocol (node's `WebSocket`, no dependencies;
skipped without node or a browser): logging in and out without a page load (and the event
stream starting and stopping), links, back/forward with their scroll, typed text kept,
the chat window (sending, its fixed height, from page to page, dragged, over a dialog, after a page load), the map and character windows (titled, the one pressed in front, the sheet fetched again when the panels change, kept closed), a move, a POST's own page (resting at the inn), the progress bar, a newer link
winning, the minimal layout, a broken page loaded natively. `GET /__test/slow?ms=N` (test
routes only) is a page that takes its time.

## Scenes

The live client changes pages smoothly (`public/js/scene.js`). Any action of the player's
that changes the middle column (a link or form: the inn and resting there, the shop and
selling, buying a map in the market, the inventory, ...) fades it out (0.15 s, in the
`before` hook, `html.dk-fade-out`) and the new one in (0.25 s); fight rounds (`fight.js`
plays them: from `/fight` to `/fight`), the hotbar saved after a drag (`/hotbar` to
`/hotbar`), refreshes, back/forward and answers that leave the
middle column as it is (a step while exploring) don't. When the player's state changes the
middle column fades out through a caption instead: a fight beginning, a victory, a death,
a getaway, arriving in a town, setting out from one.

- **The server** adds a `scene` event to the redirect that ends the change:
	`scene.add(req, res, kind, title, detail [, page])` (`app/lib/scene.lua`; live requests only),
	`{ kind, title, detail [, page] }` as JSON. `main.lua` carries a redirect's events to the page it
	lands on, after the round's (`events fight`). The scenes:

| Where | kind | title | detail |
|---|---|---|---|
| `POST /move` onto a town, `POST /travel/<id>` (`town/travel.lua`) | `town` | the town's name | "You arrive in Midworld." / "You travel to Roma for 5 TP." |
| `POST /move` out of a town (`town/explore.lua`) | `explore` | Exploring | "You leave Midworld behind." |
| `POST /move` into an encounter | `fight` (`death` when the ambush kills) | Fight! | "A Blue Slime blocks your way." |
| `POST /fight`, the winning round (`routes/fight.lua`) | `victory` | Victory! | "You defeated the Blue Slime: +12 experience, +5 gold." (and "You gained a level!" or "It left something behind.") |
| `POST /fight`, the fatal round | `death` | You have died | "The Blue Slime defeated you. Half your gold is lost." |
| `POST /fight`, a getaway | `escape` | You got away | "The Blue Slime is left behind." |

- **The client** plays it after the round's events (`fight.js`) and before the regions
	apply: the middle column fades out (0.2 s) while the caption (`.dk-scene
	.dk-scene-<kind>`: the title large, the detail under it, over the middle column,
	`role="status"`) fades in; the new page goes in under it, the caption lingers (0.55 s;
	arriving in a town and setting out 0.8 s), then it fades out and the page in (0.25 s):
	1 s in all (1.25 s). The victory is a page scene
	(`scene.add(..., page)`, `"page": true`): the victory page is drawn like a caption
	(`fight/victory.html`: `.dk-scene-page`, "Victory!" large in gold, who fell and what it
	paid under it, then a level-up, a drop and the way on), so no caption goes over it: the
	fight fades out and the victory page fades in slowly (0.6 s) and stays. A click or a key cuts any of it short;
	with `prefers-reduced-motion` the new page just shows; if no page comes (a native load)
	the caption goes after 4 s. Without the live client nothing plays: the redirect shows the
	new page.
- Arriving in a town goes straight to the town's page (3.0): the "You have travelled to
	... You may now enter this town." page is gone; its sentence is the scene's detail.
- Tests: `tests/e2e/live_wire.sh` (the encounter's, the town's and setting out's scenes,
	none while exploring on or without the live client), `tests/e2e/fight_api.sh` (victory,
	death, escape), `tests/browser/client.js` (a link: the middle column faded out and in;
	back: no fade; walking into Midworld: the caption seen, the page back after it).

## Modals

A page can open in a dialog over the one on screen (`public/js/modal.js`), the shop's
purchase first: give the link `data-modal`.

```html
<a href="/shop/buy/3" data-modal>Club</a>
```

- **The request**: `modal.js` fetches the link's address with `X-DK-Modal: 1` (and the
	live client's `X-DK-Tab`). `main.lua` marks the request (`req.modal`) and
	`view.layout` answers with the page's title and content alone, no layout
	(`templates/layout/modal.html`: `h2.dk-modal-title` and `.dk-modal-content`; region
	markers stripped), marked `X-DK-Modal: 1`. The same routes run, so the handler needs
	nothing: whatever page it answers (the purchase form, a message, a 403) is the dialog's.
	A redirect comes back as an empty `200` with `X-DK-Go: <location>` (fetch would
	follow it into the dialog): the dialog closes and the page goes there (`DK.visit`).
	Templates can tell with `req.modal` (`town/message.html` offers "Back to the shop"
	instead of the ways on). HTML answers vary by `X-DK-Live, X-DK-Modal`.
- **The dialog**: one `<dialog class="dk-modal">` made by the script (`data-client`: the
	live client's morph leaves it alone), opened with `show()` over a backdrop of its own
	(`.dk-modal-backdrop`), the page behind made `inert` by the script (each child of
	`<body>` but those scripts own, `data-client`: the floating windows stay usable and
	over it; the live client leaves `inert` to the scripts): the game halts, Escape closes
	it (but not from a floating window), focus stays inside. A browser without `inert` gets
	`showModal()` (the windows halt too). Closing cleans up at once (the close event
	comes later). Its first field or button gets
	the focus (`autofocus` picks another); closing gives the focus back to the link. If the
	page takes longer than 250 ms the dialog opens with "Loading…" meanwhile.
- **Inside it**: forms submit into the dialog (`fetch`, the submitter's name and value
	included); after a POST the page behind brings itself up to date (`DK.refresh()`;
	without the live client, a reload when the dialog closes), so the gold and lists are
	current under the answer. A link closes the dialog and goes on like any link (a
	`data-modal` one opens in it instead). An element with `data-modal-close` closes it
	without a request: on a submit button (`<input type="submit" name="cancel" value="No"
	data-modal-close>`) the page without JavaScript still submits it. The close button
	(×) and a click on the backdrop close it too. Tooltips inside it work as anywhere
	(`tooltip.js` puts its box into the open dialog), and the compass's arrow keys rest.
- **Without it** (no JavaScript, no `<dialog>`): the link is an ordinary link and the page
	shows as a page, exactly as before. A GET that fails or answers something else (a 503
	page) loads the address as a page; a POST answered with a whole page shows it, and one
	lost on the way reloads the page as it is now.
- `window.dkModal`: `open(url)`, `close()`, `isOpen()`.
- Styles: `.dk-modal`, `.dk-modal-box`, `.dk-modal-title`, `.dk-modal-x`,
	`.dk-modal-actions` (`dk.css`; the themes give the box their tooltips' paper).
- Tests: `tests/e2e/town.sh` ("the purchase in the shop's dialog": the answer, the headers,
	`X-DK-Go`, a purchase); `tests/browser/client.js` ("the shop's dialog": it opens over
	the page, the focus, No, a purchase and the page behind catching up, Escape, a tooltip in
	it, the arrow keys).

## Windows

Floating windows (3.1, `public/js/windows.js`): the Babble Box ([Chat](#chat)), the world
map and the character sheet. A link names its window, `<a href="/map" target="_blank"
data-window="map">` (the Location panel's View Map; the Character panel's Extended Stats
is `stats`, the Functions box's Babble Box `chat`); a click opens or closes it, and
without JavaScript (or with a modifier key) the link is its page (`/map` and `/character`
on the minimal layout, in a new tab).

- **What they show**: the link's address fetched as a dialog's page (`X-DK-Modal: 1`: the
	content alone, [Modals](#modals)), without the live client's region names (`data-r`).
	`windows.js` names each kind: its title (in the strip: "Babble Box", "World Map",
	"Extended Stats"), where it opens the first time (the bottom right corner, the middle,
	the top right under the header), what of the page it shows (the chat: `.chat`; else
	`.dk-modal-content`), the field focused when the player opens it, and the regions
	whose change makes it out of date: the sheet's are the right column's panels
	(`charpanel`, `invpanel`, `spellpanel`, or `right`/`root` when the answer sends those
	whole), seen in the live client's `before` hook; it is fetched again once the answer is
	on screen (`applied`). The map's are the Location box's (`loc`, or `left`/`root`): the
	player's ring follows a move (the land's picture is a cached static file, so only the
	page's few kilobytes come again).
- **The window** (`<section class="dk-window dk-window-<kind>" role="dialog">`, not a
	`<dialog>`: the game goes on under it, the arrow keys and the hotbar too;
	`data-client`, so the live client's morph leaves it and it stays open from page to
	page). Its strip (`.dk-window-grip`: the title, the close button `.dk-window-x` at the
	right) moves it (pointer events, kept inside the viewport); its corner resizes it (CSS
	`resize`); a press anywhere in one brings it in front (`z-index` from 950, in the order
	pressed). Sizes at first: the chat 320 by 400, the map 540 by 680 (the map as large as
	the window allows, the legend under it), the sheet 280 by 520 (scrolling). It has the page's own
	background (the theme's `body` image) a little darker. Whether each is open, where and
	how big are kept in `localStorage` (`dk-window-<kind>`), so a page load opens it again
	where it was. Escape in one closes it. A page without a window's link (logged out, the
	admin panel) hides that window. Over a dialog it stays usable and on top (the dialog's
	`z-index` is 901).

## Realtime (event streams)

The server pushes events to browsers over [server-sent events](https://html.spec.whatwg.org/multipage/server-sent-events.html)
(`EventSource` in the browser). The engine part (`src/hub.c`) knows channels and
streams; the app decides who may listen to what and what to send.

**Opening a stream.** A GET handler returns

```lua
return { sse = { channels = { "babble", "user:" .. req.user.id }, retry = 3000 } }
```

- `channels`: 1 to 16 names, each `[a-z0-9:_-]{1,64}`. **Authorization is the
	handler's job**: only put a private channel (`user:<id>`, `admin`) in the list when
	the request's user may read it. The C side checks names, not rights.
- `retry` (optional, ms): the browser's reconnect delay (`retry:` line).
- `status` and `body` are ignored; headers (cookies queued on `req.out_headers`) are
	sent. Only `GET` opens a stream: HEAD and POST get a 405 from the engine.
- The handler's transaction commits and the VM is released as usual; then the server
	sends `200`, `Content-Type: text/event-stream`, `Cache-Control: no-store`,
	`X-Accel-Buffering: no`, and keeps the connection, without timeouts.
- When `max_streams` or `max_streams_per_ip` is reached the answer is a `503` with
	`Retry-After: 5`. `EventSource` does not retry after an error status: the client
	script has to (with a backoff).
- The stream is fixed once open: the server does not re-check the session. A logout or
	password change publishes `logout` on `user:<id>`, and live.js closes the page's
	stream and reloads it (see [Live pages](#live-pages)).

`GET /live` (`app/routes/live.lua`) is the game's stream: `babble`, `presence`,
`notices`, `user:<id>`, plus `admin` for administrators (`live.channels(user)`).

**Publishing.** `dk.publish(channel, event, data)` from any request handler:

```lua
local json = require("lib.json")
dk.publish("babble", "babble", json.encode({ id = id, author = name, text = text, time = dk.now() }))
```

- `data` is a string; encode tables with `lib/json.lua` (`json.encode`, see its header:
	strings are escaped so the result is safe in HTML too; `json.array({})` for an empty
	array). Line breaks in data are fine (each line becomes a `data:` line; the browser
	joins them with `\n`). Up to 64 KiB, no NUL bytes; event names `[A-Za-z0-9_.:-]{1,64}`.
	Invalid arguments raise a Lua error (a 500).
- Events are buffered per request and handed to the server **only after the
	transaction commits**, in commit order. On a rollback (an error, `view.server_error`,
	a HEAD request) they are dropped. At most 256 per request.
- The server numbers events `<boot>-<n>` (`boot`: random per server start) and sends
	`id:`, `event:` and `data:` lines. Every subscriber gets the same bytes (one buffer
	shared by all).
- Events committed before a stream opened are not sent on it, except as a replay (below).
	That includes events the stream's own request published.
- From CLI commands (`dk user ...`) `dk.publish` logs a warning and sends nothing: the
	streams belong to the server process.

**Who listens.** `dk.subscribers(channel)` is the number of open streams on a channel
(0 when none, and in CLI processes): `dk.subscribers("user:12") > 0` means player 12 has
a live page open. It reads the server's counts as they are now (thread-safe, a hash
lookup under a short lock); a stream the request itself opens isn't counted yet.

**Reconnects.** The browser reconnects by itself and sends the last id it saw
(`Last-Event-ID`; also visible to the handler as `req.headers["last-event-id"]`). The
server replays the stream's channels' events after that id from each channel's ring
(`stream_replay_events`, `stream_replay_seconds`), or, when some are gone (or the id is
from before a restart), sends `event: resync` (empty data): the page should reload what
it shows. Every opening ends with an id line for the current position, and heartbeats
(`: ping` every `stream_heartbeat_ms` on quiet streams) carry it too, so a short network
blip replays instead of resyncing. At shutdown streams get `event: bye`.

**Limits.** A client that stops reading is cut off once `stream_queue_bytes` (256 KiB)
are waiting for it. `max_streams` (512) and `max_streams_per_ip` (8) bound the number of
open streams; a browser has at most 6 connections per host over HTTP/1.1, so live.js
shares one stream between a browser's tabs.

**Testing.** `test_routes = true` in the config (the e2e config sets it) enables
`POST /__test/publish` (`channel`, `event`, `data`, optional `delay_ms`, `fail=1`) for any
logged-in user, and the request header `X-Test-Seed: <digits>` (`math.randomseed` before the
route runs: `tests/e2e/fight_api.sh` plays a round twice with the same dice), `X-Test-Now: <unix>` (the
clock, [Clock and weather](#clock-and-weather)); `tests/e2e/live.sh` reads streams with `curl -N` (the `live_*` helpers
of `tests/run.sh`, see [End-to-end tests](#end-to-end-tests)).

### Events

What the game publishes (data is JSON; event names are unique across channels, because
the browser sees only the name):

| Channel | Event | Data | Published by |
|---|---|---|---|
| `babble` | `babble` | `{ id, author, author_id, role, text, time, when, delete }` (a new chat message; `author_id`: the author's account (public anyway: Who's Online links to it), so each page tells the viewer's own; `role`: the author's ([Roles](#roles)); `time`: unix seconds, `when`: as the page shows it, `delete`: the address administrators and moderators delete it with) | `POST /babble` (`chat.post`) |
| `babble` | `delete` | `{ id }` | `POST /babble/#id/delete` (administrators and moderators) |
| `presence` | `join` | `{ id, name, url, online }` (`url`: the character page; `online`: how many are online now) | a player's first request while not online (`session.load`) |
| `presence` | `leave` | `{ id, name, url, online }` | the presence sweep |
| `notices` | `news` | `{ id, title, author, url }` | a news post (`/admin/news`) |
| `notices` | `banner` | `{ id, text, expires, ttl }` (`expires`, `ttl`: unix time and seconds left, absent without an expiry) | `/admin/broadcast` (set) |
| `notices` | `clear` | `{ id }` | `/admin/broadcast` (clear) |
| `user:<id>` | `reply` | `{ thread, title, author, url }` | a reply in a forum thread the player started or posted in (not to the one replying; at most 200 players) |
| `user:<id>` | `logout` | `{ session }` (one session's pages) or `{ all = true }` | logout; password change, lost password, a new password set in the user editor |
| `user:<id>` | `stale` | `{ tab }` (the sending page's `X-DK-Tab`, or `""`) | every successful POST of the player (`main.lua`), but those that set `req.quiet` (the chat's, the banner's dismissal): their other pages ask for themselves again; the server's tick (`lib/tick.lua`, `tab` `""`: every page) when it changed the player's fight or world statuses, or the weather where an online player with a stream stands |
| (server) | `resync`, `bye` | empty | the hub: missed events are gone / shutdown |

The `admin` channel exists for administrators' streams; nothing uses it yet.

### Live pages

`public/js/live.js` is loaded on every page and runs while the page is a logged-in
player's (every layout: `<body data-live data-csrf=... data-live-session=...
[data-live-admin]>`, from `layout/live_attrs.html`). With the [live client](#live-client)
the page stays while the player logs in and out, so the stream starts when `data-live`
appears and stops when it goes (on `DK.on("applied")`), and it stays open across
navigation. What it changes in the page itself (a chat message, a name joining) it reports
with `DK.touched`. Everything it does is also there without it: forms post and pages
reload. No toasts in popup windows (`window.opener`).

- **Markup comes from the server.** What live.js adds to a page (a chat message, a name in
	Who's Online, the banner, a toast) is a copy of a `<template data-proto="…">` the page
	carries (`chat-post` in `layout/chat.html`, `online-name` in `layout/online.html`,
	`banner` and `toast` in `layout/protos.html`, rendered with the page: an administrator's
	chat posts have the delete button, with the session's CSRF token). live.js fills it from
	the event: `data-slot="key"` elements get the value as text (`data-unwrap`: the text
	alone), `data-slot-attr="attr:key ..."` attributes; then the result is the server's
	own markup for it (a prototype says so next to the template it copies: keep the two
	alike). Prototypes leave out the page's address (`back`), which would change their
	region with every page; live.js sends those forms itself.
- **Other pages of the player.** After every successful POST of a player (but the chat's
	and a banner dismissal: `req.quiet`), `main.lua` publishes `stale` on `user:<id>` with
	the sending page's id (`X-DK-Tab`, `DK.tab`). Every other page of the player, in this
	browser or another, asks for itself again (`DK.refresh()`, 250 ms later: several
	changes, one request; only what changed comes); a hidden page does it when it shows
	again (also after more than a minute hidden, whatever happened). The server's tick
	publishes it too, with no tab (every page of the player): a fight the clock moved (a
	status's tick, a guard), world statuses, the weather (see [The server
	tick](#the-server-tick)).

- **One stream per browser.** Tabs elect a leader: `localStorage["dk-live-leader"]` holds
	`{ id, t }`, renewed every 2 s; a tab finding it missing or older than 6 s claims it,
	and leads if its claim is still there 100–200 ms later. The leader holds the
	`EventSource("/live")` and forwards each event over `BroadcastChannel("dk-live")`; a
	leader closing (`pagehide`) clears the claim and says so, and another tab takes over
	(and resyncs: events in between are lost). A leader that finds another tab's fresh
	claim steps down. Without `BroadcastChannel` or `localStorage` every tab has its own
	stream. Events carry their id; a tab ignores an id it has seen.
- **Errors.** A dropped connection is reconnected by `EventSource` itself (with
	`Last-Event-ID`: replay). An error status (503 at the limits; a redirect to `/login`
	when logged out) closes it: live.js then asks `GET /live/state`; a redirect or a 4xx
	(but 429) stops it for good, anything else is retried with a backoff (1 s doubling to
	60 s, with jitter); a stream opened after that resyncs. On `bye` (server shutdown) it
	reconnects after 2–5 s the same way.
- **Resync.** On `resync` (and after a reconnect or a takeover) every tab asks the live
	client for its page again (`DK.refresh()`: only what changed comes). Without the live
	client it fetches `GET /live/state?back=<page>`: `{ chat, online = { count, html },
	banner }`, the live parts rendered by the same templates as the page, and swaps them in.
- **Event data goes in with `textContent` only.** Links in notices are used only when they
	are same-site paths (`/...`, not `//`).
- **Logout.** `logout` with `all`, or with the page's own `data-live-session`
	(`session.live_id`, a hash of the session row: not the token), closes the stream and
	asks for the page again (`DK.refresh()`, or a reload without the live client): the login
	page comes. The pages of the player's other sessions ignore it.
- Not covered: events published between a page's render and its stream opening are lost
	(the stream starts at the server's current position); the page shows the state of its
	render. Navigating keeps that window to a few milliseconds.

### Chat

The Babble Box (`lib/chat.lua`, routes in `town/babble.lua`, `layout/chat.html`) is
`/babble` (its own page, with who's online; old links to the iframe land there) and, from
the Functions box's Babble Box link (`<a href="/babble" data-window="chat">`), the **chat
window** (3.1, one of the [floating windows](#windows)); no other page shows it. `control.showbabble` turns
it off everywhere (the link too). Its messages are in a box of a fixed height
(`.chat-scroll`, 340px on the page; the window's whole upper part: it doesn't grow or shrink
as messages come and go) that scrolls from the bottom, the newest last; each message is
compact, the author's name (`.babble-author`) over the text (`.babble-text`;
`layout/chat_posts.html`, no whitespace between the tags since messages keep their
spaces; an administrator's or moderator's delete button on the name's line, shown on the
message pointed at), on the box's own ground: the viewer's messages on the right in red
(`.babble-mine`: the author is the list's `data-me`), the others on the left, black, an
administrator's gold (`.babble-admin`) and a moderator's green (`.babble-moderator`), by the
author's role now ([Roles](#roles); `chat.history` joins it, the event carries it; live.js
gives the prototype the same classes). A message right after one by the same author (the
same name) doesn't show the name again (`.babble-cont`, last of its classes: the name stays
in the markup, hidden but for screen readers, and the message sits close to the one
before); live.js groups a list again (`group`) after a message comes or goes, so deleting
the first of a run shows the name on the next. Then the message bar (`.chat-bar`): the field across the box, the send button
(`.chat-send`, an SVG arrow, `aria-label="Send"`) inside it. live.js sends the chat's forms
itself (its submit listener captures: no dialog or live client takes them) and adds the
messages that come to every list on the page (the window's too).

- **The window** (`.dk-window-chat`, see [Windows](#windows)): `/babble` as a dialog's
	page, the chat alone (`.chat`, no heading), 320 by 400 at first in the bottom right
	corner, the focus in its field when the player opens it. The message bar is its foot:
	dark, with light text and send button, flush with its sides and bottom, square on top,
	its bottom corners the window's (an error line goes above it).

- History: the last 50 messages (`chat.HISTORY`), oldest first, rendered on the page;
	live ones arrive as `babble` events (live.js builds the same markup).
- `POST /babble` (`babble`, `back`): blank messages are ignored, longer ones cut to 120
	characters (`chat.MAX_CHARS`, like before), at most one message per 2 seconds per player
	(`chat.INTERVAL`, in whole seconds from `babble.posttime` of the player's last message,
	by `author_id`: a message is taken once the clock's second is 2 past the last one's, so
	messages are at least 1 s and on average 2 s apart): `429` with `Retry-After` and a
	message. With `Accept:
	application/json` (live.js's fetch, CSRF in `X-CSRF-Token`) the answer is `{ message =
	{ id, author, text, time } | null }` or `{ error, wait }`; otherwise a redirect to
	`back` (or `/babble`), or the 429 page.
- `POST /babble/#id/delete` (administrators and moderators, `roles.can_moderate`; the
	button shows for them): deletes the
	message and publishes `delete`; JSON `{ deleted }` or a redirect back.
- `babble.author` keeps the name at posting time (shown), `author_id` the account.

### Presence (who's online)

`lib/presence.lua`. **Online** = has a stream open (`dk.subscribers("user:<id>") > 0`) or
made a request within `online_seconds` (600). `users.online = 1` marks the players
announced as online; the Who's Online list (town page, `/babble`) and the count in the
right column ("Online: N", when `control.showonline` is on) are those players, so they
always match the events. Both read the partial index `users_online` (schema version 11:
only the players online), so their cost follows the players online, not the accounts.
The Who's Online box lists at most `presence.SHOWN` (50) names, by name, then "and N
more" linking to `GET /online`, which lists everyone; the count is always exact. live.js
adds joining players only while the box has room (`data-online-limit`) and keeps "and N
more" in step with the count.

- **Join**: `session.load` → `presence.touch`: a request by a player with `online = 0`
	sets it and publishes `join`. Any number of requests, tabs or streams make one join.
- **Leave**: `presence.sweep()` (every request, from `main.lua`, after the session) runs
	when `meta.presence_sweep` is at least `presence_sweep_seconds` (60) old: it stamps
	the time and publishes `leave` for marked players with no request in the window and no
	open stream (at most 40 per request, the rest next time). So departures show within
	about a minute, and on a quiet server (no requests at all) when the next request comes.
- A player's own request counts before the sweep, so nobody leaves and rejoins at once.
- Logging out doesn't announce a leave: the player stays online for the window, as by
	the definition.

### Notices

`lib/notices.lua`: toasts at the bottom right of open pages, gone after 12 s or when
closed; live only (a player who isn't online doesn't get them later). `notices.news(id,
title, author)` from `/admin/news`; `notices.forum_reply(thread, author, url)` from
`POST /forum/reply/#id`, to every account that started or posted in the thread except
the replier.

### Broadcast banner

`lib/banner.lua`, `/admin/broadcast` (Broadcast in the admin menu): a text (200
characters) with an optional expiry in minutes, kept in `control` (`banner`, `banner_id`:
+1 per new banner, `banner_expires`: unix time, 0 = never). Every layout renders it at
the top (`layout/banner.html`, logged out too) while it is active; open pages get
`banner` / `clear` and drop it at its expiry. "×" dismisses it in this browser: the
cookie `dk_banner=<id>` (set by live.js, or by `POST /banner/dismiss` without JS), so a
new banner shows again.

### Adding a live feature

1. Decide the channel: a public one (`babble`, `presence`, `notices`) or the player's
	`user:<id>` (a new public channel goes into `live.PUBLIC` in `routes/live.lua`; only add
	private channels a player may read) and a **new event name** (names are global).
2. Publish from the handler that commits the change, after validation:
	`dk.publish(channel, "my_event", json.encode({...}))`. Keep data small and plain
	(ids, names, short texts, same-site URLs); never HTML.
3. Render the same thing server-side so a page load (and no JS) shows it, with a
	`data-...` hook live.js can find; if it can go stale, add it to `GET /live/state`.
4. In live.js add the event to `EVENTS` and a handler to `handlers` that updates the
	page (idempotent: an event may come twice): markup from a `<template data-proto>` the
	page carries (`proto(name, values)`), text with `textContent`; then `touched(el)`, so the
	live client's next answer brings that region as the server has it. Often the simplest
	handler is `DK.refresh()`: the page as the server has it, only what changed.
5. Test with two jars and `live_open` streams (`tests/e2e/chat.sh` is the model).

## Templates

Syntax: see PLAN.md. Names resolve in this order: template locals, then `ctx`, then the
helpers `h`. `ctx` and `h` are not names you can use in a template, and identifiers
starting with `__` are reserved.

- `{{ expr }}` escapes the value; `nil` prints as an empty string. Use `{{{ expr }}}` only
	for HTML your own code built.
- **HTML-returning helpers need triple braces**: `{{{ csrf_field() }}}`,
	`{{{ include("x") }}}`, `{{{ nl2br(text) }}}`.
- Every POST form needs `{{{ csrf_field() }}}` (the chat's and the banner's too).
- Floating windows: `<a href="/map" target="_blank" data-window="map">` (see
	[Windows](#windows); without JS the page in a new tab).
- The way back (`layout/main.html`, 3.1): the header's first button (`.dk-home`, a gold
	frame on dark brown, black in Retro), on every page of the main layout, links to `/`
	(`routes/home.lua`: the fight, the town or exploring) and is named for where that is:
	"Back to the fight", "Back to Midworld" (the player's town), "Back to exploring". It
	isn't there on the page it leads to (`/`, or `/fight` while fighting: the layout's
	`here`, the request's path). The header's links are a region (`topnav`), so the button
	follows the state and the page on live pages.
- The compass (`layout/nav_left.html`): the original's picture (`public/images/compass.png`,
	its four pieces joined) with a submit button over each quarter (`.compass-rose`: the
	triangles between the diagonals, `clip-path`, lit within the parchment by a `mask`),
	named `north`, `west`, `east`, `south` like the old text buttons, so `POST /move` reads
	them as before. `dk.js` presses them for the arrow keys (not while a field has the
	keyboard or a modifier is held; a held key walks on only while the live client is free).
- The Towns box (`layout/nav_left.html`, 3.1): a button per town on the player's map
	(`.towns-btn`, a `POST /travel/<id>` form each) with the trip's TP on the right; the town
	the player is in ("here"), those their TP don't cover (the cost in red, "You need N more
	TP" as its title) and all of them while fighting are disabled; no maps: a line saying
	where to buy them. The server checks everything again (`town/travel.lua`).
- Item and skill tiles (`dk.css` "frames"): a gradient frame drawn as a background layer
	under the tile, through a 2px transparent border, bright at the top to dark at the
	bottom: gold (`--frame-gold`, lit on hover) for spells, items and gear, steel for the
	fight's Attack and Run (`.action-btn`), crimson for quest items in the bag; the tile
	itself is `--icon-bg`, a fine grain (`--icon-noise`: an SVG noise filter in a `data:`
	URL, no image file) over a warm off-white a little darker at the edges
	(`--icon-ground`, radial), which item pictures without a ground of their own sit on
	everywhere (the bag, lists, the Inventory panel, tooltips, the purchase dialog). The
	bag's entries sit on the page itself (3.1: no frames, a hairline under each row; a quest
	item's name in crimson, a free slot just the word). Retro sets the frames to plain
	black (quest items red).
- Icon buttons for items (`.spell-btn` with an `.item-badge`): the fight menu's Items and
	Gear, the shop's wares (`town/shop.html`: grouped Weapons, Armor, Shields, Items;
	greyed, `.shop-short`, when the gold, with what the worn piece sells back for, doesn't
	cover it — still a link: the purchase page says why) and its Sell buttons (a stack's
	size, `.item-badge-qty`, and how many to sell). The shop's prices are in its tooltips,
	`tip/shop.html` (below). The wares' links open the purchase in a dialog, `data-modal`
	(see [Modals](#modals)); without JavaScript it is a page of its own.
- The purchase (`town/shop_buy.html`, `.buy`; `shop.confirm` builds its ctx) has its own
	look, made to decide rather than to inform: the item in a framed tile (`.buy-tile`, 48px)
	with its name, its kind ("Weapon", "Consumable, into your bag") and a gold
	price tag (`.buy-tag`, "15 gold each"); gear's description, small; what it changes
	side by side with the item worn in its slot (`.buy-compare`: "Your Stick" and "The
	Club" columns, the change green or red; `items.compare`), or what it gives with nothing
	worn (`.buy-gives`), or what it does (`.buy-effects`: a consumable's effect, the spell it
	casts and its charges); then the choices as large buttons (`.buy-choice`: what to do in
	bold, what happens to what is worn and what it leaves in the purse under it; one that
	can't be taken is shown dashed with the reason, `.buy-choice-off`): for gear "Buy to
	bag" (`bag`), "Buy and equip" (`keep`: the old piece into the bag; `submit` with
	nothing worn) and "Buy and sell my Stick" (`sell`), for the rest a quantity for stacks
	(`.buy-qty`) and "Buy" (`submit`, `qty`); and "Not now" (`.buy-cancel`, `cancel`,
	`data-modal-close`).
- Images: `/static/images/<file>` (`public/images/`): `items/` and `skills/` (icons, see
	[Items](#items), [Spells](#spells)), `buildings/` (the town's banners), `backgrounds/`
	(`parchment_tile.jpg`: the news posts' card, seamless, made from VWolfdog's
	"WarmParchment" on OpenGameArt, CC0; `parchment.png`, `blue.webp`, `darkstorm.jpg`,
	`snowstorm.jpg`),
	`actions/` (19px framed action icons: `attack.png`, `attack_1.png` ... `attack_8.png`,
	`creature*.png`, `relic.png`, `send_message.png`, ...), `tiles/` (grid cells: `1x1.png`,
	`1x1_mini.png`, `2x2.png`, `2x3.png`), `ui/` (`spinner.gif`, the `indicators.png`
	sprite), `themes/<key>/` (a theme's logo, background, pictures); at the top the
	original's (the compass, the slot icons `icon_*.gif`, the help pages' pictures) and
	`world.svg` (the land's picture, generated: [Terrain and the map](#terrain-and-the-map)). The `actions/`, `tiles/`, `ui/` pictures and all but the parchment tile among
	the backgrounds aren't used yet. A link-styled submit button:
	`<form class="inline" method="post" action="/x">{{{ csrf_field() }}}<button class="link">Text</button></form>`.
- Low numbers blink with `<span class="highlight blink">`. The CSS animation replaces
	`<blink>`.
- Shared CSS classes: `.title` (headings: `<h1 class="title page-title">` the page's own,
	once, first in the middle column; `<h2 class="title">` a panel's; the browser's heading
	sizes don't apply, the theme styles them), `.box` / `.box-body`, `.small`, `.light`,
	`.highlight`, `.error`, `.copyright`, `button.link`, `form.inline`. A heading the theme
	may draw as a picture goes through `{{{ art(key, text) }}}` (see [Themes](#themes)).

### Helpers `h`

| Helper | |
|---|---|
| `escape` | `dk.html` |
| `include(name [, ctx])` | renders another template (defaults to the current ctx) → HTML |
| `csrf_field()` / `csrf_token()` | hidden input / raw token |
| `logo()` | the theme's logo, linked to `/` → HTML |
| `theme_picker()` | the theme selector (a POST form to `/theme` that comes back to this page) → HTML |
| `art(key, text)`, `art_src(key)` | a label of the layout: the theme's picture for `key` or the text (see [Themes](#themes)) → HTML; the picture's URL or nil |
| `url(path, seg..., [query_table])` | `url("/forum/thread", 7, {start = 15})` → `/forum/thread/7?start=15` (segments urlencoded) |
| `number(n)` | PHP `number_format($n)`: `1234567` → `1,234,567` |
| `date(ts)` | PHP `date("F j, Y")` (legacy `prettydate`) |
| `datetime(ts)` | `Y-m-d H:i:s` (what legacy printed for raw MySQL datetimes) |
| `nl2br(s)` | escapes, then adds `<br />` → HTML |
| `paragraphs(s)` | escapes; a blank line starts a new `<p>`, the lines of a paragraph are joined with spaces (lore) → HTML |
| `tip(kind, row)` | the tooltip content of a `"spell"`, `"item"`, `"monster"` or `"class"` row (`lib/tips.lua`, `templates/tip/tip.html`; see [Tooltips](#tooltips)) → HTML |
| `req` | the request (`req.user`, `req.path`, …) |
| `php` | the `lib.php` module |
| `ipairs pairs next select type tostring tonumber string table math utf8 os.date os.time dk` | Lua builtins |

## Themes

A theme is a stylesheet, a logo and, optionally, pictures for the layout's labels (`art`);
the page's structure is the same in every theme. `app/lib/themes.lua` lists them:

| Key | Name | Stylesheet | Logo | Labels |
|---|---|---|---|---|
| `default` | Default | `/static/css/themes/default.css`: the snow background (`public/images/themes/default/background.jpg`), near-black text, dark red links with a bright red hover; headings as text in small capitals over a hairline (the page's title larger, without one), no lines between the columns but 22px of space, the chat in light stripes, the footer a row of small print without a box | `/static/images/themes/default/logo.png` (shown at 355×120) | text |
| `retro` | Retro | `/static/css/themes/retro.css`: the original tiled `background.jpg`, the grey heading boxes and black column lines of `dk.css` | `/static/images/themes/retro/logo.gif` (409×108) | the original's pictures (`public/images/themes/retro/`: `button_*.gif`, `title_*.gif`, `town_N.gif`) |

```lua
-- an entry of themes.list (the selector lists them in this order)
{
	key = "retro",                                  -- [a-z0-9_]: the cookie value, body class theme-retro
	name = "Retro",                                 -- shown in the selector
	stylesheet = "/static/css/themes/retro.css",
	logo = { src = "/static/images/themes/retro/logo.gif", width = 409, height = 108,
		alt = "Dragon Knight" },                    -- the logo's alt text is the game's name; this if it has none
	art = { location = "button_location.gif", town_1 = "town_1.gif", ... },   -- optional
	art_dir = "/static/images/themes/retro/",
}
```

- **Choosing.** Every page with a footer (main and admin layouts, help and changelog
	pages) has the selector in its footer's row, `{{{ theme_picker() }}}` ("Theme: Default · Retro", the
	current one in bold): a POST form to `/theme` (`app/routes/theme.lua`) with the CSRF
	field (the session's token, or the pre-session token when logged out, as on the login
	form), `theme` (the key, from the button pressed) and `back` (the page's path and query
	string; on a page answering a POST, its path). The route sets the `dk_theme` cookie
	(`Path=/`, one year, `SameSite=Lax`) and redirects to `back` if it is a same-site path
	with a GET route (`themes.safe_path`: no scheme, host, `//`, backslash or control
	characters), else to `/`. An unknown key is a 400 page and changes nothing. Pages on
	the minimal layout have no selector but use the theme. No database: the
	choice belongs to the browser, logged in or out.
- **Rendering.** `themes.current(req)` is the cookie's theme, or `themes.DEFAULT`
	(`default`) when there is none or it names no theme. The layouts get it as ctx `theme`:
	`layout/head.html` links `theme.stylesheet` after the other stylesheets, `<body>` gets
	the class `theme-<key>` (before `body_class`), and `{{{ logo() }}}`
	(`templates/layout/logo.html`) draws `theme.logo` linked to `/` (main layout header, admin
	menu, help and changelog pages). The 500 and 503 pages link the theme's stylesheet too.
- **Labels** (`art`): the panels' headings (`<h2 class="title">`), the page titles
	(`<h1 class="title page-title">`) and the top links are written with `{{{ art(key,
	text) }}}`: the theme's picture for `key` (`<img>` with `text` as alt and title), or
	`text`, escaped. `art_src(key)` is the picture's URL or nil (the Log Out button: an
	image button or a link-styled one). Keys: `location`, `towns`, `functions`,
	`character`, `inventory`, `fastspells`, `spells`, `exploring`, `fighting`,
	`town_<id>` ("Welcome to <town>"), `login`, `logout`, `register`, `help`. A key the
	theme has no picture for is text, so a ninth town reads "Welcome to ..." in Retro too.
	The Location panel's heading is where the player is ("In Midworld", "Exploring",
	"Fighting") when the theme draws it as text; a theme with a `location` picture shows
	that, and where the player is as the panel's first line (`.loc-where`). Then the
	coordinates, latitude first (`.loc-coords`, "3N, 5W"), and the map link on one line.
- **Theme CSS** only overrides `dk.css` and the feature stylesheets: background, colours,
	borders, the headings' and columns' look, logo effects. Since only the current theme's
	file is linked, plain selectors (`body`, `a`) are enough; `body.theme-<key>` is there
	for feature CSS that needs to differ by theme. Keep the columns' widths and the page's
	structure in `dk.css` so every theme fits the same.
- **Adding a theme**: put its images under `public/images/themes/<key>/`, write
	`public/css/themes/<key>.css` (copy `default.css`), add an entry to `themes.list`, and
	add it to `tests/e2e/theme.sh`. No restart: the next page lists it.

**The font.** Every page, whatever the theme, uses Vollkorn (`public/fonts/vollkorn/`,
Regular, Italic, Bold and Bold Italic; SIL Open Font License 1.1, `OFL.txt` next to the
fonts): the `@font-face` rules and `font: 15px/1.4 Vollkorn, Georgia, "Times New Roman",
serif` on `body` are at the top of `dk.css`, tables and form controls inherit it, and
`layout/head.html` preloads the regular weight. Sizes: 15px text, 13px for `.small`, the
footer (`.copyright`) and the selector; the side columns are 210px wide (legacy 180px at
11px Verdana), the admin menu 180px. A weight not in the folder is synthesized by the
browser; to use SemiBold or Black, add the file and its `@font-face`.

## Tooltips

`public/js/tooltip.js` (loaded deferred by `layout/head.html` on every layout) shows a
tooltip for any element with `data-tip`. One shared box (`<div id="dk-tooltip"
role="tooltip" class="dk-tip">`, made on first use) serves every trigger; the only DOM work
per show is cloning the content. Events are delegated to `document` (`pointerover`/`out`,
`focusin`/`out`, `keydown`, `pointerdown`), so content swapped in later (the live client's regions,
live.js chat, a resync) needs no set-up, and nothing runs while nothing is hovered.

**Markup.**

```html
<!-- rich content: an inert template child, rendered (and escaped) by the server -->
<span class="tip-term" data-tip data-tip-side="bottom" tabindex="0">Mage
	<template class="tip"><div class="tip-title">Mage</div><div class="tip-meta">...</div></template></span>
<!-- plain text -->
<li data-tip="Weapon: empty slot">...</li>
```

- `data-tip` marks the trigger. Its content is, in order: its `<template class="tip">` child;
	the text of `data-tip`; its `title` (or a descendant's). Templates are inert: their content
	is not rendered, read by screen readers or submitted.
- `data-tip-side`: `top` (default), `bottom`, `left` or `right`, the preferred side.
- Content classes (`dk.css`, coloured by the themes): `.tip-title` (bold name), `.tip-meta`
	(short facts, muted: "5 MP · In fights"), `.tip-icon` (an item's picture, 20px, before
	its name in `.tip-title`: the template's `icon`), `.tip-lines` (a list of stat lines),
	`.tip-body` (the description, paragraphs) and `.tip-lore` (italic, muted, set apart by a
	dotted rule). `.tip-term` underlines a word that has a tooltip (dotted, `cursor: help`).
- **Game things**: `{{{ tip("spell", row) }}}` (also `"item"`, `"monster"`, `"class"`;
	`tip("item", row, entry)` with a `user_items` entry says that item's charges, "3/5
	Charges") renders the template from a row: `lib/tips.lua` picks what to say (title, meta, lines,
	description, lore), `templates/tip/tip.html` renders it, escaping everything; empty
	parts (no lore, no description) are left out. For anything else,
	`{{{ include("tip/tip", { title = ..., meta = { ... }, lines = { ... }, body = text, lore = text }) }}}`.
- **Disabled controls** get no pointer events in some browsers: put `data-tip` on a wrapper
	(the spell buttons' `<span class="spell-tip">`, the fight actions' `<span
	class="action-tip">`; `.spell-btn:disabled` and `.action-btn:disabled` have
	`pointer-events: none` so the wrapper gets the hover).
- **No JavaScript**: keep a short `title` (and `aria-label` for icon buttons) in the markup;
	it is the browser's own tooltip then. With the script, `title` moves to `data-tip-title`
	(at start and before each show) so the two don't double up; `aria-label` stays for screen
	readers.

**Showing.** Hover shows after 120 ms, at once when moving from one trigger to the next
(within 300 ms of the last one closing); keyboard focus (`:focus-visible`, so not a mouse
click or a tap) shows it at once; on touch screens a long press (400 ms, without moving)
shows it and swallows the click that follows, while a normal tap still clicks. It hides on
leaving, on blur, on Escape, on a click or tap (one opened by focus stays until blur), when the trigger scrolls out of view
(the viewport or a scrolling ancestor) and when it leaves the DOM (a region
swapped in). While shown, the focused element (or the trigger) has
`aria-describedby="dk-tooltip"`. A short fade, none with `prefers-reduced-motion`.
`window.dkTip.show(el)` / `.hide()` open and close one from other scripts (and test pages).

**Placement** (`place(trigger, tip, vw, vh, side)` in tooltip.js, pure: rects in, `{ side,
x, y, arrow }` out; `tests/js/test_tooltip.js`): the box (at most 280px wide, never wider
than the viewport less 16px) goes on the preferred side if it fits there (8px gap for the
arrow, 8px from the viewport's edges), else the first that fits of the opposite side and
then the other axis (top → bottom → right → left; left → right → top → bottom), else on the
side that lacks the least room; then it is clamped 8px inside the viewport on both axes,
and the arrow points at the trigger's centre, clamped 10px from the box's corners. It is
`position: fixed` and measured with `getBoundingClientRect`, so it works in scrolled
containers and at any zoom; scrolling, resizing and DOM changes reposition it (once per
animation frame) while it is open.

**Adding a tooltip** to anything: add `data-tip` (and `tabindex="0"` if it isn't focusable,
so keyboards reach it) with a `<template class="tip">` child (`tip(...)` or
`include("tip/tip", ...)`) or a `data-tip="text"`, and keep a `title` for no-JS. That's all.

**Where.** The fight menu's spell buttons and Fast Spells (name, MP, where usable,
description, lore), the fight menu's Attack (the player's attack power and weapon) and Run
buttons (`tips.attack`, `tips.run`; see [Fight engine](#fight-engine)), the gear rows of
the Inventory panel (item name, kind, stats or power, description, lore; an empty slot's
label), the fight menu's Gear and Items buttons (`tips.gear(entry)`: the item, the spell it
casts, its charges, "No MP"; `tips.consumable(row, qty)`), item names wherever a page lists items (`tip("item", row)`: on `/inventory` the
equipped slots and every bag entry, quest items saying "Quest item"; on `/shop` the items
for sale and the Sell buttons (`tips.shop(item, { gold, old, sellback, short })`,
`tips.sell(entry, price)`, rendered by their own template, `tip/shop.html`, made to be read
at a glance: the price set large with the player's gold or what is missing, the stats as
a table of figures with the change against the item worn in that slot, green or red, a
gray "+0" when it doesn't change, and the stats a swap loses, the effects (a consumable's, the spell gear casts, its charges),
the trade-in, then the description; no lore); the discard confirmation), the monster's name on the fight page (name,
level, description, lore), the fields on the fight page's Battlefield line (`tips.field`: the
field's icon and name, its group and a spell's time left, its modifiers as lines, the
description, lore) and the class names on the registration page (starting HP/MP, the
description's points, lore). Names that aren't links get `class="tip-term" tabindex="0"`.

## Lore

`lore` is an optional content field of every kind (classes, spells, items, monsters,
statuses, summons, fields): story text, up to 2,000 characters (`schema.LORE_MAX`), several lines,
a blank line between paragraphs (the lines of a paragraph are joined, so files may wrap
it). Synced into the kinds' `lore` columns (schema version 13), overridable in the admin
panel (a textarea on every content admin page), escaped wherever it shows
(`paragraphs(text)`): in the tooltips (`.tip-lore`) and on the help pages under each entry
(`.help-lore`: classes on `/help`, spells, statuses and allies on `/help/spells`, items on
`/help/items`, monsters on `/help/monsters`, fields on `/help/fields`). Empty lore shows nothing. Every class, item, monster, spell, status and ally has
some (3.1); the fields (3.2) get theirs in a later pass. The voice is plain and concrete (a place, a
habit, a rumour, who uses it), and only the upper echelon sounds legendary: monsters from
level 42, the dragons and demon lords, the Destiny gear and the Dragon's, Angel's, Seraph's
and Demon's accessories, the strongest spells:

```lua
-- app/content/spells/heal.lua (excerpt)
	lore = [[
The first word every young Mage learns, and the last one a wise one forgets. Spoken
softly over a wound, it draws warmth back into tired flesh. Old soldiers say a Heal cast
in time is worth a hundred herbs.]],
```

## Icons

Every item, spell, monster, status and ally has an icon (3.1): a square PNG named by its
`icon` field, `public/images/<dir>/<icon>.png`: `items/`, `skills/` (spells), `monsters/`,
`statuses/`, `summons/` (the last three since schema version 20; synced and overridable
like the others; `dk check` fails on a missing file). Monsters' are 128×128 portraits, the
rest 96×96. Where they show: items and spells on their buttons, in the bag, the Inventory
panel and tooltips (see [Items](#items), [Spells](#spells)); the monster's portrait beside
"You are fighting a ..." and its HP (`.fight-foe`, 72px) and in its tooltip; an ally's
icon before its name and a status's before its name on the fight page (`fight/statuses.html`,
and `fight.js` from the fight API's status lists); each entry's icon before its name on
the help pages. Fields (3.2, [Fields](#fields)) may have one too, in `fields/` (copies of
the skill icons that fit the weather; a field without one shows its name alone), on the
Battlefield line, in its tooltip and on `/help/fields`. Templates get an entity's own icon
with `entity_icon(kind, name)` (nil when it has none; `schema.entity_icon`), which shows
nothing rather than the spells' default picture.

They are made from licensed icon packs kept outside the repository (`Icons/`, ignored by
git: standard art, never the "nobg" variants; items from the weapon, armor and profession
packs, spells and statuses from the skill packs, monsters and allies from the character
portraits). `docs/icon-sources.tsv` lists every icon made in 3.1 with its source file and
how it was recoloured, so any of them can be made again. `tools/icons/sheet.py` makes
contact sheets of icons to browse (`sheet.py /tmp/sheet "Icons/.../*.png"`), and
`tools/icons/place_icon.py SRC public/images/<dir>/<key>.png [--size N] [--hue DEG]
[--sat F] [--bright F] [--tint #rrggbb:0.3] [--flip]` resizes and recolours one (a family's
members from one picture: the slimes by hue, a Dark version darker, a Frost one tinted).
Then set `icon = "<key>"` in the content file, add the line to `docs/icon-sources.tsv`
and run `./dk check`.

## Game helpers (`lib/game.lua`)

| Function | Returns |
|---|---|
| `game.control()` | control row (id 1), cached per request; `game.reload_control()` after updating it |
| `game.user(id)` | fresh users row |
| `game.town_at(lat, lon)`, `game.current_town(user)` | town row or nil (by coordinates) |
| `game.class_name(n)` | the class's name for a `users.charclass` value (nil if unknown); `lib/classes.lua` has the rest |
| `game.stats(user)` | the effective stats of a users row: `{ maxhp, maxmp, maxtp, strength, dexterity, attack, defense, exp_bonus_pct, gold_bonus_pct }` (see [Derived stats](#derived-stats)) |
| `game.player(user)` | a copy of the row with the effective stats under the original column names (`maxhp`, `attackpower`, `defensepower`, `expbonus`, `goldbonus`, ...): what the fight code and the spell and item actions (`fight/engine.lua` handles) take |
| `game.user_towns(user)` | town rows in `users.towns`, ordered by id |
| `game.latitude_str(n)`, `game.longitude_str(n)` | `5N`/`5S`, `3E`/`3W` |
| `game.statbar(cur, max)` | `{pct, width, level}`: width 0..100 (%), level `high`/`mid`/`low` (66/33); the Character panel's bars (`game.nav(user).bars`) and the fight bars share the CSS gradients `--bar-high/mid/low/mp/tp` in dk.css |
| `game.is_low(cur, max)` | `cur <= max / 5` |
| `game.gear_rows(equipped)` | the Inventory panel's rows from `inventory.equipped()`: `{label, icon|badge, name, empty, item}` (weapon, armor, shield, accessory slots 1–3; `item`: the row, for its tooltip) |
| `game.forum_link()` | `/forum`, the external address, or nil |
| `game.online_users()` | the players online (`id, charname`; `lib/presence.lua`) |
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
| `classes.start_spells(c)`, `classes.teach_start_spells(user_id, c)` | the spells rows of the class's `start_spells` (existing, not retired) / teach them to a new character, learned at level 1 (registration, `dk install`) |
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

The starting stats are the class file's (`start_hp`, `start_mp`, ...; the Mage starts with
5 MP since 2.4, the gains per level unchanged, so a Mage's MP is 5 + the gains + equipment;
`tests/lua/test_leveling.lua` pins the gains, 370 MP over levels 2-99).

The global rules are plain data at the top of the module (`leveling.GLOBAL_STAGES`,
`leveling.TP`, `leveling.HP_MILESTONES`); edit them and the next request uses them (hot reload): victory
level-ups (`combat.level_up`), "Next Level" on the character sheets, `/help/levels` and
the admin class pages. `tests/lua/test_leveling.lua` pins them and the stock class files
against a frozen copy of the original table (`tests/lua/levels_original.lua`), so update
its expectations with them. Moving thresholds needs no data fixup: a player whose
experience already covers the next level gets it (or several) on the next victory.

## Clock and weather

(3.2, `docs/plans/elements-and-weather.md` part 3.) The game's one clock
(`app/lib/clock.lua`) and a weather computed from it (`app/lib/weather.lua`; the words in
`app/lib/weather_lines.lua`): pure functions of the place, the time and a fixed seed.
Nothing is stored and nothing runs in the background, so GETs stay pure, every worker
agrees, and a page computes the weather when it shows it. No dice: every choice is a hash
(64-bit mixing of `weather.SEED`, a salt and integers), and the game's dice
(`math.random`) are left alone.

- **The clock** is the single source of game time: whatever moves with time counts in its
	ticks, and no browser drives it. `clock.now()` is the time every caller passes on
	(`dk.now()`, or the time a test pinned: below); everything else takes `now` (unix
	seconds) as an argument. Game time goes in **base ticks of 10 s** (`clock.TICK`),
	numbered from the unix epoch: `clock.tick(now)` is the number of the tick `now` is in
	(`now // 10`), `clock.tick_start(n)` the unix time tick `n` starts. A game day lasts 2
	hours (`clock.DAY`): dawn 15 minutes, day 60, dusk 15 and night 30 (`clock.PHASES`, whole
	ticks). `clock.time_of_day(now)` is the phase, `clock.phase_ends(now)` when it ends.
	`clock.duration(seconds)` is a length for the page ("20s", "1m 30s"). The server runs
	the game's tick on it ([The server tick](#the-server-tick)), and fights, statuses and
	allies count its ticks.
- **The weather's step** is 6 clock ticks (`weather.STEP`): it changes only as a minute
	begins, and is the same all through one.
- **The grid.** The map in cells of 10 by 10 tiles (`weather.CELL`). Each cell has a base
	sky that holds 20 minutes (`weather.SPELL`; each cell changes at its own moment), picked
	by a hash from its place and the time of day, by the **climate of the land** at the
	cell's centre (its biome's `climate`, [Terrain and the map](#terrain-and-the-map); one
	climate per cell, so a cell keeps one sky): fog (likelier at dawn and at night where the
	biome says: the Greymoor's dawns are foggy half the time), heat by day (the Ashlands and
	the Dry Country), a little drizzle (snow where it snows), clouds, sun by day, else
	clear. The Midlands keep the weather's numbers from before the land exactly (fog 4%,
	drizzle 6%, overcast 20%, sun 35% by day), so the e2e tests' calm place sees the same
	skies.
- **Snow.** Falling weather is snow (drizzle and rain as snow, downpours and thunderstorms
	as blizzards) north of the cell's climate's snow line (`snow_line`: latitude 150 in the
	Midlands and most lands; 100 in the Hambry Weald and the Storm Barrens) and, at any
	latitude, on a peak tile (the feature of the tile itself, so a storm over a range snows
	on the peaks and rains on the hills around them, and `weather.edge` says so); but never
	where the climate has no snow line (the Dry Country and the Ashlands: rain instead,
	north of 150 and on their peaks too).
- **Storms.** A slot every 45 minutes (`weather.SLOT`). One hash per slot decides whether
	its storm forms (45%, `weather.FORMS`: about one storm every 100 minutes), its size (a
	squall, half of them, with a radius of 8-14 tiles; a storm, 35%, 16-26; a great storm,
	15%, 30-40), its birth (in the slot's first half), its origin (within 30 tiles of
	Midworld), its life (2 hours, give or take 12 minutes) and how far its heading is off the line to Gilead (up to 0.08 radians). It
	moves in a straight line at the speed that takes it to Gilead in its life, so its
	position is a closed-form function of time. It grows from 40% of its radius in the first
	fifth of its life, holds, and from 70% of it weakens (its rain a level lighter, its
	radius shrinking to half) until it breaks over Gilead (within about 25 tiles). Inside it
	the rain goes by the distance from its centre over its radius: the core (under 0.35)
	has the size's strongest (a downpour in a squall, a thunderstorm in the others), the
	body (under 0.7) a level less, the fringe two (a drizzle at least), and the climate's
	`storm` levels more (the Storm Barrens one: a squall's core there is a thunderstorm; at
	most a thunderstorm); where it snows, drizzle and rain fall as snow, downpours and
	thunderstorms as blizzards.
	`weather.storms(now)` lists the storms alive (centre, radius, birth, end).
- **The ground.** From each storm's closest approach to the tile along its track (closed
	form): where it rains, mud from then until 20 minutes (`weather.MUD`, times the biome's
	`mud`: 2 in the Thornbog, 0.4 in the Dry Country) after its rain (rain or worse) there
	ended; where it snows, snow for 20 minutes after any snowfall, then ice for 20 more
	(`weather.SNOW`). Otherwise wet while rain falls (snow while snow falls), else
	dry. The ground follows the closest approach and the sky the moment, so the two agree
	closely but not exactly at a storm's edge.
- **`weather.at(lat, lon, now)`** is `{ sky, ground, time, storm, near }`, the same all
	through a step. It looks only at the storm slots whose storms can be alive or still
	leave mud or snow (about ten; their storms kept for the request) and costs about 3 µs
	(`tests/lua/test_weather.lua` measures 10,000 calls). Part 4 (fields) maps `sky`,
	`ground` and `time` to the battlefield, so their words are a contract:

| Field | |
|---|---|
| `sky` | `clear`, `sun`, `heat`, `overcast`, `fog`, `drizzle`, `rain`, `downpour`, `thunderstorm`, `snow`, `blizzard` |
| `ground` | `dry`, `wet`, `mud`, `snow`, `ice` |
| `time` | `dawn`, `day`, `dusk`, `night` (`clock.time_of_day`) |
| `storm` | the storm overhead, `{ size = "squall" \| "storm" \| "great", name }`, or nil |
| `near` | the nearest other storm whose edge is within 40 tiles (`weather.NEAR`), `{ direction = "south-east", distance }` (tiles to its edge), or nil |

- **Changes.** What a page shows of the weather is the sky, the ground, the time, the
	storm overhead's size and a near storm's direction; a change is a difference in those.
	`weather.changed(lat, lon, t0, t1)` says whether there is one between two times: false
	at once within a step (no `weather.at`), else the two compared, so between two clock
	ticks it sees every change. `weather.change(lat, lon, now)` compares the step before
	with now's: a line for each part that changed (a storm arriving or leaving, the sky, a
	storm coming near or going, the ground, the time of day), or nil.
	`weather.describe(w)` is the weather as it stands (a sentence for the sky, the storm
	overhead, the ground and a near storm), the same for the same weather.
	`weather.edge(lat, lon, now)` is a line when a tile next to this one (north, east,
	south, west) has another sky, naming its direction. `weather.report(lat, lon, now)` is
	what the Location box shows.
- **The words** (`lib/weather_lines.lua`, plain tables): names (`sky`, `ground`, `time`,
	`storm`, `directions`); `standing` (the sky by `"sky:time"`, else by sky; the ground; the
	storm overhead; a storm near); `change` (the sky and the ground by `"from>to"`, else by
	the new state; the time; `storm_arrives`, `storm_leaves`, `near_comes`, `near_goes`); and
	`edge` (by the next tile's sky). Every entry is a list of variants: add to any. One is
	picked by a hash (a change line's of the tile and the step, a description's of the
	weather, an edge line's of the tile and the direction), so a reload shows the same line.
	`{direction}` in a line becomes the direction.
- **Shown.** The Location box (`layout/nav_left.html`) has the weather in a region of its
	own inside `loc`, `weather` (`.loc-weather`): an icon for the sky (`.wx .wx-<sky>
	.wx-<time>`: an SVG mask in the text's colour, `dk.css`; the moon on a clear night), the
	sky's name with a tooltip (the name; the time of day, the storm, the ground; the
	description; `title` without JavaScript) and the time of day. Its markup changes only
	when the weather does. The exploring page (`home/explore.html`) shows above its line the
	change line (`.explore-change`, in the minute the weather changed) and the edge line
	(`.explore-edge`), in a region of their own, `explore-weather`, there even when empty:
	the middle column's own markup stays the same, and a move doesn't fade it
	([Scenes](#scenes)). A GET can't know where the player came from, so the edge line
	stands for "you walked into other weather": right after such a move the weather left
	behind is next to the player, and the line is true whichever way they came. The fight
	page shows the battlefield: the weather's fields ([Fields](#fields)).
- **Open pages** learn of a change from the server, never from a timer of their own: the
	server's tick (`lib/tick.lua`), at each tick that begins a weather step, asks
	`weather.changed` between the tick before and this one for the tiles of the players
	online with an event stream and publishes `stale` on `user:<id>` for those whose weather
	changed, which live.js turns into `DK.refresh()` (only what changed comes: the `weather`
	region, and `explore-weather` on the exploring page). Until then a page shows the
	weather of its last answer.
- **Testing.** With `test_routes = true` a request may pin the clock: `X-Test-Now: <unix
	seconds>` (`main.lua`, `clock.pin`), for everything that asks `clock.now()`.
	`tests/run.sh` pins every request at `$T_NOW` (4000000000), so the weather is the same on
	every run and doesn't change between two requests (`T_NOW=<unix> t_get /` asks at another
	time). `tests/lua/test_clock.lua`, `tests/lua/test_weather.lua` (the storms' journey and
	how often they come, the land's climate, snow beyond the snow lines and on the peaks and
	never in the Dry Country, the storms' bands and the Barrens' harder storms,
	mud after rain, the lines, `weather.changed` between clock ticks, the cost), `tests/e2e/weather.sh` (the box; in the minute of a change the exploring page's
	line, and a live answer with the weather's regions alone), `tests/e2e/tick.sh` (the push
	to an open page).

## Terrain and the map

(3.2, `docs/plans/elements-and-weather.md` part 7.) The world's land: every tile has a
**biome** (ten: one around each town and two wild ones) and maybe a **feature** (a lake, a
pond, hills or a peak). Every tile stays walkable (lakes are waded, peaks climbed); the land
changes the weather's climate, the fight's battlefield and the words of the place, never
where a player may go.

- **The world is data** (permanent after 3.2.0's release). `app/lib/terrain/world.lua` holds the land of every
	cell of 5 by 5 tiles (101 by 101; a town at a cell's centre): `land`, a string per row
	from the north with a biome's letter per cell from the west (`M` midland, `R` downs, `B`
	shoals, `K` diggings, `N` moors, `H` weald, `G` barrens, `E` ashlands, `D` drylands, `T`
	marsh), and `relief` the same with a feature's character (`~` lake, `o` pond, `n` hill,
	`^` peak, `.` none), so the file reads as two maps. It is **generated, committed and
	never edited by hand**: its header names the generator and the seed. The game only
	reads it, so nothing the game's code does moves the land.
- **World generator v1** (`app/lib/terrain/generator_v1.lua`, seed `0x3300`) made it, and
	the game never loads it. Integer hashing (the weather's 64-bit mixing) and integer or
	fixed-point arithmetic only (integer square roots, smoothstep on integers, floor
	divisions; no floats), so every Lua 5.4 on every platform makes the same bytes. Each
	cell, at its centre: its biome is the town's within 7 tiles of a town, else the nearest
	point's of a blue-noise scatter (a jittered grid: one point in each 12-tile square,
	within 0.6 of it). A point within a town's core takes the town's biome; any other is
	reached only by the biomes whose nearest anchor (their town, or a wild biome's four
	seeds, placed in the gaps between the towns' lands) is within their reach, each scoring
	weight * (1 - distance / reach), moved up to 0.25 either way by its own border noise,
	and takes one within 0.15 of the best score (a hash, weighted by how far within). So
	the lands are coherent, their borders meander, and they mix only in the bands where
	two scores are close; every point is reached by some biome (the generator stops if
	not). **Pockets** break up the broad lands by climate: a second jittered grid (one
	centre in each 56-tile square) whose centres deep inside a land (its score 0.4 above
	any other's, 26 tiles or more from its town) make round pockets of 22 tiles (to a
	quarter more), where the land's deep points take a biome of a like climate by a hash:
	each biome has two integer traits, warmth and wetness (-2 to 2), and the same traits
	weigh 2, one step apart 1, further never. So the cold Weald has pockets of the Barrens
	and the Greymoor, the wet Shoals of the Thornbog, the Ashlands of the Dry Country, the
	Midlands of the Copper Downs; a pocket is a dozen scatter points or so, never one cell
	alone. Its feature, from value noises (lattice bytes hashed every `step` tiles,
	smoothstep between) flattened toward the towns (none within 16 tiles of Midworld and 8
	of another town, fewer out to 40 and 24): a peak where the elevation (steps 48, 24 and
	12, plus the biome's shift) is 0.76 or more; a lake where the basins (steps 60 and 18,
	less the biome's lake shift: more in the Shoals and the Thornbog) are 0.22 or less and
	it isn't high, so lakes are a few bodies several cells across; hills at 0.62; a pond
	where a fine noise (step 6, plus the biome's pond shift) passes 0.89 and it is low (one
	or two cells); else none. Its numbers (the biomes' cores, reaches, weights, shifts,
	traits and the wild seeds) are in the file, tuned by looking at the map. The world:
	plain 73%, hills 17%, lakes 5%, peaks 4%, ponds 1%; the Dry Country 13% and the
	Thornbog 9%, the towns' biomes from 6% (the Ashlands) to 14% (the Greymoor, the Weald);
	no cell alone among other biomes; 32 lakes, 9 of them 30 cells or more (the largest
	81); ponds of at most 4 cells; the widest stretch of one biome away from its town 70
	tiles (the Greymoor).
- **Verifying it**: `tests/lua/test_terrain.lua` runs generator v1 and requires its output
	to be the committed file byte for byte (and the generator's code to count in integers).
	`tools/world.sh` (`BIN=./dk tools/world.sh`) writes the file again from the generator,
	in the project's own Lua (a scratch copy of `app/` whose `cli/check.lua` is
	`tools/world.lua`, run by `dk check`, which needs no database): it changes nothing
	unless generator v1 changed. **Until 3.2.0 is released** generator v1 may still change:
	run `tools/world.sh` and commit the data and the picture with it. It is frozen at the
	release; **after 3.2.0's release, a new world is a new generator** beside v1
	(`generator_v2.lua`, its own seed), never a change to v1: point `tools/world.lua` and
	the test at it, run `tools/world.sh`, and commit the new data as a deliberate change of
	the world (the players' positions stay; only the land under them changes).
- **`lib/terrain.lua`** reads the data and says what the land is: `terrain.at(lat, lon)` is
	`{ biome, feature, field }` (a biome key; `"lake"`, `"pond"`, `"hill"`, `"peak"` or nil;
	the terrain field's key or nil), the same for the 25 tiles of a cell, a shared table
	(two string reads and a table read: about 0.15 µs; the module loads in well under a
	millisecond, from the code cache). `terrain.BIOMES` (key, name, map colour, field,
	climate) and `terrain.FEATURES` (key, name, colour or how much darker than the biome,
	field), `terrain.biome(key)`, `terrain.feature(key)`, `terrain.colour(biome,
	feature)`.

| Biome | Town | Field | Climate (lib/weather.lua) |
|---|---|---|---|
| `midland` The Midlands | Midworld | none | the weather's own: fog 4%, drizzle 6%, overcast 20%, sun 35% by day, snow north of 150 |
| `downs` The Copper Downs | Roma | none | dawn mist, more drizzle and cloud, a little heat, mud lasts 1.5x |
| `shoals` The Salt Shoals | Bris | none | sea mist at dawn, drizzle and cloud, mud 1.25x |
| `diggings` The Diggings | Kalle | none | dry and bright, little rain, mud 0.8x |
| `moors` The Greymoor | Narcissa | none | fog at dawn about half the time, some at night, grey, mud 1.5x |
| `weald` The Hambry Weald | Hambry | `forest` | fog off the marsh-forest, more drizzle, overcast, snow north of 100 |
| `barrens` The Storm Barrens | Gilead | none | grey, less sun, snow north of 100, storms rain a step harder |
| `ashlands` The Ashlands | Endworld | `cinders` | heat by day 60%, rarely drizzle, never snow, mud 0.5x |
| `drylands` The Dry Country | wild (4 seeds) | `sand` | heat by day 45%, sun, almost no drizzle or fog, never snow (rain instead), mud 0.4x |
| `marsh` The Thornbog | wild (4 seeds) | `marsh` | fog (dawn and night), drizzle, overcast, mud 2x |

- **The fields** (group `terrain`, [Fields](#fields)): a tile's field is its feature's
	(`peaks`; `shallows` in a lake or a pond; `hills`), else its biome's own. Midworld's
	start is the Midlands' plain, with no field, for at least 12 tiles around (the e2e
	tests' calm place too).
- **The climate**: the weather reads the biome at the centre of each 10-tile weather cell
	(its `climate`: the chances of the base sky, the snow line, how long mud lasts, how
	much harder storms rain), and the feature of the tile itself for snow: peaks snow at
	any latitude but where the climate never snows ([Clock and weather](#clock-and-weather)).
- **The words** (`lib/terrain_lines.lua`, plain tables like `weather_lines.lua`): for
	each biome and each feature, `standing` (where the player stands), `edge` (another
	biome or feature on a tile next to theirs, `{direction}`), `fight_open` (an encounter's
	first line, `{monster}`) and `fight_turn` (now and then between rounds). A tile's own
	words are its feature's, else its biome's. One variant is picked by a hash of the place
	and the time (the hour for the exploring page, the clock tick for an encounter, the
	round in a fight), never by dice: `terrain.standing(lat, lon, now)`, `terrain.edge(lat,
	lon, now)` (the first neighbour, north, east, south, west, with other land),
	`terrain.fight_open(lat, lon, k, monster)` and `terrain.fight_turn(lat, lon, round)`
	(one round in four may have a line, chosen by the place, and half of those do: at most
	one in four rounds, about one in eight; at the end of the round, `fight/round.lua`).
	Fights roll the same dice with them.
- **Shown**: the Location box names the biome and the feature (`.loc-land`, `game.land`);
	the exploring page has the standing and edge lines above the weather's, in a region of
	their own, `explore-land` (`.explore-standing`, `.explore-land-edge`), there even when
	empty; an encounter opens with the land's line; the Battlefield line shows the terrain
	field.
- **The map** (`GET /map`, `town/map.html`, and the World Map window, [Windows](#windows)):
	the land's picture under the towns and the player, and a legend; the whole world
	(every town and all the land, whatever maps the player bought). The picture is a static
	file, `public/images/world.svg` (about 30 KB, served and cached like any static file):
	a cell a unit, each row's runs of one colour a stroke (a path per colour: the biomes',
	the water's deep blues, lakes `#3f6fa3` and ponds `#5585b8`, apart from the Shoals'
	teal; the hills' and peaks' darker shades), the hills' and peaks' cells with a
	pattern over them (a hump; a peak with a pale cap). `app/lib/terrain/picture.lua` draws
	it from the data; `tools/world.sh` writes it, and `tests/lua/test_terrain.lua` requires
	the file to be that drawing (so a colour change fails until it is written again). The
	page is an inline SVG in the picture's units: the picture as an `<image>`, thin axes
	through Midworld, each town from the `towns` table (a dot and its name, inward from the
	map's edges), the player's red ring and a title naming where they are; it works
	without JavaScript.
- **Testing**: `tests/lua/test_terrain.lua` (the data is generator v1's output byte for
	byte, integers only, the picture is the drawing, a cell is one place, the towns plain
	in their biomes and no feature near them, Midworld's start, the biomes' and features'
	shares, the lands coherent (no confetti, tracts), lakes as bodies and small ponds, the
	widest stretch of one biome, the fields, the cost), `tests/lua/test_weather.lua`
	(the climate: fog on the moors at dawn, heat in the Ashlands; snow on the peaks),
	`tests/lua/test_fields.lua` (the terrain field held, never a spell's),
	`tests/e2e/terrain.sh` (the Location box, the exploring page's lines, a fight on the
	Thornbog's field and its first line, `/help/fields`; places found in the world's data),
	`tests/e2e/town.sh` (`/map`: the picture, the towns, the player, the legend).

## The server tick

(3.2, `docs/plans/elements-and-weather.md` part 6.) The game runs on one server-authoritative
clock ([Clock and weather](#clock-and-weather)): nothing a browser does (a refresh, a dropped
connection, a closed tab) drives it.

- **The timer** (`src/http.c`): with `tick = true` (the default; `false` turns it off: the
	e2e tests' config does), the I/O thread sends the game's tick on every boundary of 10
	s of the wall clock (`clock.TICK`; `dk_config.tick_ms`, not a config key, shortens it
	in the C tests), a moment after it: a request of its own, `POST /__tick` with
	`req.tick = true`, queued for a worker like any other and run by the ordinary path (a
	pool VM, `main.lua`, the transaction and its write lock, `dk.publish` events after the
	commit, errors logged), with no connection: its answer goes nowhere (a status other
	than 200 is logged) and it has no access log line. One at a time: a tick still running
	when the next is due skips that one (the next catches up). The CLI and `dk check` never
	run it. `ticks` in `dk stats` and `/admin/server` counts them.
- **Only the engine reaches it.** A network request can't set `req.tick` (the engine sets
	it on its own request only), and `routes/tick.lua` answers anything else with a 404
	(`main.lua` skips the CSRF check for the tick alone, so a network POST without a token
	gets its 403 first). The tick has no user: `main.lua`'s `stale` after a player's POST
	isn't sent for it; `tick.run` publishes what it changed itself.
- **`tick.run(now)`** (`app/lib/tick.lua`) advances everything the clock moves up to the
	tick `now` is in, in three parts, each bounded per run (`tick.FIGHTS` = 100 fights,
	`tick.WORLD` = 200 characters, at most `tick.TICKS` = 30 ticks each): what is left over
	continues on the next run, so after the server was down the next runs catch up, because
	time ran on.
	- **Fights** due (`SELECT ... FROM fights WHERE outcome = '' AND due <= ? ORDER BY due`:
		the partial index `fights_due`, the most behind first) are advanced with
		`encounter.advance` (below), the same code a `POST /fight` runs first.
	- **World statuses** (`user_statuses.tick < ?`, the index `user_statuses_tick`, the most
		behind first) count the ticks with `world.advance`: each ticks and counts down
		(they can't take the last hit point outside a fight); while the character fights,
		the ticks pass them by.
	- **The weather**: at a tick that begins a weather step, the players online with an
		event stream whose tile's weather changed since the tick before.
	A fight or world statuses the tick changed, and a changed weather, publish `stale` on
	`user:<id>` (with no tab: every page of the player refreshes; a player gets one per
	run).
- **Fights on the clock** (`fight/round.lua` `round.advance(f, n [, limit])`): a fight saves
	the last tick it played (`fights.tick`), the tick its turn runs out at
	(`fights.deadline`) and when the tick must advance it next (`fights.due`: the next tick
	while anything in it counts ticks, a status, an ally, a spell's field or a field with
	`on_tick`, else the deadline, or the weather's next step when that comes first). Advancing
	it to tick `n` plays every tick after `fights.tick` in order; at each:
	0. the battlefield: spells' fields count down, the world's follow the weather at the
		player's tile, each field's `on_tick` runs ([Fields](#fields));
	1. a turn the player can't act in (asleep, recharging, charging: `round.locked`) ends:
		a round with the blocked turn (its line), the allies and the monsters acting;
	2. every combatant's statuses tick (`on_tick`) and count down, those that run out
		expire (a charge releases: the caster's action, even between the player's turns;
		sleep rolls to wake), and allies count down and leave;
	3. a turn whose deadline passed is played as a **Guard** round ("You hesitate, and
		raise your guard."), whether or not a page is open: a player who walked away keeps
		guarding, every 30 seconds, until the fight ends.
	Each round played starts the player's next turn (`round.next_turn`: the round counter
	+1, the deadline `round.TURN` = 3 ticks, 30 s, later). A fight further behind than
	`round.CATCHUP` (360 ticks, an hour) skips the older ticks. A fight not on the clock yet
	(`fights.tick` 0: in progress when the database was migrated, or made by a test) starts
	on it at `n` with its turn's full time and the weather's fields; world statuses with
	`tick` 0 too.
	`encounter.advance(user, f, n [, limit])` runs it and settles what it did: its lines go
	into the fight's log, a death or a victory ends the fight as a round's would, else the
	fight is saved.
- **Commands catch up first**: `POST /fight` advances the fight to now (the same code), then
	plays the command: a form from before a turn that ran out is stale (the round counter
	moved on), and a status's tick due in between happens before the spell.
- **GETs stay pure**: `GET /fight` shows the fight as the tick (or the last command) left it,
	at most one tick old; it computes the timer and nothing else.
- **Testing.** `POST /__test/tick` (test routes only) runs `tick.run` at the request's time
	(`X-Test-Now`: `t_tick [SECONDS]` moves `$T_NOW` on and runs it, see [End-to-end
	tests](#end-to-end-tests)). `tests/c/test_http.c` (the timer fires on its boundaries,
	is off with `tick = false`, a network request to `/__tick` is never the tick),
	`tests/lua/test_round.lua` (advancing: statuses and allies counting ticks from the one
	after they came, a blocked turn ending at the tick, sleep waking on ticks, a charge
	releasing between turns, the timed-out Guard, catching up after a long absence until
	the fight ends, bounded per call), `tests/lua/test_tick.lua` (`tick.run` on the
	database: the fights due in order and bounded, `stale` published, world statuses),
	`tests/e2e/tick.sh` (the route, the timer's markup, a guard pushed to an open page and
	kept in the log, a fight that ends on the clock, the weather pushed),
	`tests/e2e/fight_api.sh` (a command catching up first, Guard), `tests/e2e/migrate.sh`
	(step 22).

## Content

Classes, spells, items, statuses, fields, summons and monsters are **content**: Lua files in
git, one per entity, hot-reloaded like the code and synced into the database, where players'
rows reference them by id. Spells, consumables, statuses and summons also carry code: what
they do (see [Scripting spells and items](#scripting-spells-and-items) and
[Fight engine](#fight-engine)); monsters may carry conditions (see [Monsters](#monsters)),
and fields an `on_tick` (see [Fields](#fields)).

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
	start_spells = { "hurt" },               -- spells a new character knows (level 1; optional)
	exp_base = 22,                           -- the first experience step; exp_stages (optional,
	                                         -- "factor x steps,...") replaces the global curve
	levels = levels,                         -- every level 2-100: hp, mp, strength, dexterity
}                                          -- (default 0), spells (default none)
```

- **Lore**: every kind has the optional field `lore` (schema version 13; see
	[Lore](#lore)).
- **Starting spells** (schema version 14): a class's `start_spells` lists spell keys a new
	character knows from the start (`classes.start_spells`, column `classes.start_spells`,
	overridable in the admin panel): registration and `dk install --class` teach them with
	`learned_level` 1. The Mage starts with Magic Bolt (and 5 MP); the Warrior and Paladin
	with none. Changing the list later doesn't teach existing characters (the step-14
	migration taught the Mages Magic Bolt once).
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
	admin overrides. Kinds sync in `schema.KINDS` order (statuses, fields, summons, spells,
	classes, items, monsters: kinds others reference first; statuses before fields, whose
	rules name them, spells before classes, whose `class_spells` rows need the spell ids,
	items and spells before monsters). The original
	classes keep ids 1-3, the original spells 1-19, the items 1-68, the statuses of the
	original mechanics (`sleep`, `uber_damage`, `uber_defense`) 1-3 and the original
	monsters 1-151 (seeded in `seed.sql`).
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
	`/admin/spells/#id`, `/admin/items/#id`, `/admin/{statuses,summons,monsters,fields}/#id`,
	shared code in `admin/content.lua` and `templates/admin/content_form.html`) write them
	for the kind's `admin_fields` (every kind: lore; classes: name, description, sort, playable, starting
	stats; spells: name, description, MP, power, icon, numbers and message strings; items: see
	[Items](#items); monsters: see [Monsters](#monsters); fields: see [Fields](#fields); a
	value equal to the file's
	deletes the override) and offer "reset to file". Field names are those of the
	flat form: `name`, `levels.17.hp`, `levels.17.spells` (`"heal,hurt"`), `power`,
	`data.min`, `messages.hit`, `messages.enemy.hit`, `modifiers.2.stat`.
- **Migrations into content**: a migration that turns old rows into content writes the
	old values into `content_adopt(kind, key, field, value)`; the next sync turns those
	that differ from the file (and are valid) into overrides (that is how schema version 4
	kept edited class names and levels data, version 5 edited spell names, MP and amounts,
	version 6 edited items and drops, version 7 turned edited effect amounts into
	`power`, and version 9 kept edited monster stats). Only values that may have been
	edited belong there: version 4 records a level's spell only where it differs from the
	original game's (`V4_STOCK_SPELLS`), since the class files teach spells at more levels
	now and a stock database's empty level is no edit; likewise version 21 adopts a
	monster's immunity as `resist.arcane` / `ward.sleep` only where it differs from the
	original game's (`V21_STOCK_IMMUNE`).

Adding a class: copy `app/content/classes/mage.lua` to `app/content/classes/<key>.lua`,
edit it, run `./dk check`; the class shows up on the registration page on the next page
load. Deleting the file retires the class. Adding a kind: a `kinds/<kind>.lua` module
(`fields` with types, `field(name)`, `admin_fields(flat)`, optional
`validate_extra`/`write_children`), its table (`id`, `key` UNIQUE, the field columns,
`retired`) and an entry in `schema.KINDS` (in sync order: kinds others reference first).
A field of type `keys` with `refs = "<kind>"` lists keys of another kind (type `key`: one
key or `""`, an item's `casts`; both checked by `load.all`); `write_children` maps them to ids; an optional `validate_refs(flat, all,
err, key)` checks more against the other kinds' files (a monster's weapon must be a weapon; a
world field's group must be the weather's). A kind with code uses
`lib/content/scripted.lua` (function fields, messages, data; `load.module(kind, key)`
gives the runtime the loaded file). Bump `load.FORMAT` when the flat form changes meaning.

## Spells

Spells are content (see [Content](#content)): `app/content/spells/<key>.lua`, synced into
`spells`. The original 19 keep ids 1-19 (keys from the names: `heal`, `revive`, `life`,
`breath`, `gaia`, `hurt`, `pain`, `maim`, `rend`, `chaos`, `sleep`, `dream`, `nightmare`,
`craze`, `rage`, `fury`, `ward`, `fend`, `barrier`).

3.1 added 40 spells so that each class learns something new at least every 6 levels up to
100 (`tests/lua/test_spells.lua` checks it, and that each spell's MP fits the class's pool
at the level it is learned); the original assignments stayed where they were. Each new
file names where it is learned (`-- learned: ...`). The Mage's are damage and control
(Spark, Frostbite, Cinder Lash, Sap Mind, Rockfall, Lightning Lance, Starfall, Whiteout,
Ember, Inferno, Venom, Plague, Withering, Enfeeble, Curse); the Warrior's battle cries,
strikes on its strength or attack with a cap (Cleave, Reaver, Blood Strike at a cost in
HP, Finishing Blow against a monster at a quarter of its HP), rough self-healing (Grit,
Second Wind) and Hunter's Mark (more damage from the weapon); the Paladin's healing with
cures (Cleanse, Mend, Mercy, Renewal, Dawn), protection (Iron Vigil), holy strikes
(Dawnstrike, Judgement) and allies. HP and MP costs and restores are shares of the maximum
(Tithe, Wellspring, Stand Fast), so they mean the same at every level. New statuses:
`weakened` and `venom` (the monster deals less damage), `burning`, `withering` (drains HP
to the caster), `marked` (weapon attacks deal more); new allies: the bear, the spirit, the
golem. `tests/lua/test_spells.lua` casts every spell, by the player and by a monster, over
many seeded states (no errors, whole amounts, MP spent only when cast, monsters immune to
every element and warding off every status untouched).

3.2 added 25 spells for the elements and the battlefield (`tests/lua/test_new_spells.lua`).
**Monster specials**, learned by no class, scale with the caster's own `attack` (`data.min` and
`data.max` percent, armor ignored, so one spell serves a level 6 drake and a level 47
dragon): the charged breaths (`fire_breath`, `frost_breath`, `venom_breath`,
`shadow_breath`: 46-55%, 20 MP, gather for a tick with `s:charge(1, "release")`, then hit in
their element with a rider: burning at level/5 (at least 3) a tick, weakened 25% for 2 ticks,
venom, withering) and `heavy_blow` (50-60%, neutral, 15 MP, also the wyverns' dive), and the
plain `thunderbolt`, `water_jet` (35-42%) and `deluge` (33-40% of water and a `downpour`).
`doom` puts the status `doom` on the target (4 ticks; harmful, so every cure lifts it); only
when the ticks run out (`on_expire`: not when cured) it takes shadow damage of half the
caster's attack. **Field spells** (`rain_call`, `sunfire`, `storm_call`, `cold_snap`, `mire`,
`nightfall`, `fog_bank`, `miasma`, `brimstone`, `consecrate`) are `target = "self"`, set the
field of their group with `s:field(key, { ticks = n })`, and refuse (`can_cast`) while it is
up (`s:has_field`); Consecrate (Paladin 30) takes an aura's place, so it undoes Miasma and
Brimstone. **Player spells**: Gust (wind) and Torrent (water) are typed Hurts for the Mage,
Scorch a stronger Ember (Mage 45), and `fire_ward`, `frost_ward` and `storm_ward` put on the
statuses of the same keys (`resist` 50 of fire, frost or lightning, 6 ticks; the Ward
Draughts, 240 gold, 8 ticks) for Paladins (21, 24, 26) and Mages (34, 37, 38). Rain Call 20,
Gust 22, Torrent 24, Sunfire 26, Cold Snap 28 and Storm Call 41 are the Mage's, Mire the
Warrior's (21).

```lua
-- app/content/spells/heal.lua (scripted: see Scripting spells and items)
return {
	name = "Heal",
	description = "Restores hit points, in a fight or out of it.",
	mp = 5,                       -- MP it costs (deducted after a successful cast)
	power = 10,                   -- the most HP it restores (what cast makes of it)
	usable_in = "both",           -- "fight" (default), "town" or "both"
	target = "self",              -- "enemy" (default) or "self"
	icon = "heal",                -- public/images/skills/heal.png (default: default.png)
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
- `icon` (optional): the spell's picture on its buttons, the name of a PNG in
	`public/images/skills/` without `.png` (`[a-z0-9_]+`; served at
	`/static/images/skills/<icon>.png`). Absent or `""`: `default.png`. The file must exist:
	`dk check` (and the sync) fail naming the spell file otherwise (`dk.static_exists`, a
	stat per check); an icon deleted after the sync shows `default.png` (`spells.icon_url`
	checks the file on every call). Synced into `spells.icon` (schema version 12) and
	overridable in the admin panel, which shows the current icon. Every spell has one (3.1;
	see [Icons](#icons)).
	**Adding an icon**: put `<name>.png` in `public/images/skills/` (square; shown at 44px in
	fights and 34px in Fast Spells, scaled by CSS), set `icon = "<name>"` in the spell file
	and run `./dk check`. Heal's and Magic Bolt's PNGs are 256×256 (120–165 KB); the 3.1
	icons are 96×96 (about 20 KB), enough for 2× screens.
- **Buttons.** The fight menu shows the spells castable in fights as icon buttons
	(`templates/fight/action.html`): `<button type="submit" name="spell" value="<id>">` with
	the icon, the MP cost as a badge (`.spell-mp`) and `title`/`aria-label` "Heal (5 MP)";
	a spell the player's MP don't cover is `disabled` and greyed out (the server checks
	again). `POST /fight` reads the spell from `spell=<id>`; the old form's
	`spell=Spell&userspell=<id>` still works (`userspell` wins when both are sent), and a
	missing, `0` or non-numeric id is "You must select a spell first". The Fast Spells box
	(`layout/nav_right.html`) is a grid of smaller (34px) buttons for the town spells, each
	its own POST form to `/spell/<id>` with the CSRF field, disabled only when MP are short
	(a full-HP heal is refused by the server). Each button has a tooltip (2.4, see
	[Tooltips](#tooltips)): its name, MP cost, where it can be cast, description and lore; the
	trigger is the fight button's wrapper `<span class="spell-tip" data-tip>` and the Fast
	Spells form (`data-tip-side="left"`), since a disabled button gets no pointer events. Both lists come from `spells.buttons`; the
	styles are `.spell-grid`, `.spell-btn` (shared with the fight menu's Attack and Run,
	`.action-btn`) and `.spell-mp` in `dk.css` (hover, active,
	`:focus-visible` outline, disabled = desaturated and faded; theme colours in
	`themes/*.css`). Since 3.1 the fight's buttons are on the hotbar (see [Hotbar](#hotbar)):
	a spell on a key carries `aria-keyshortcuts`, the others are under More. Items are icon
	buttons too (2.4, see [Fight engine](#fight-engine)).
- Magic Bolt (`magic_bolt`, 2.4, id 25): the Mage's starting spell, 1 MP, Hurt's formula
	with power 4 (3-4 arcane damage), none to monsters immune to arcane; the Wand casts it.
- The originals: heals (`heal` ... `gaia`: power = the HP restored), hurts (`hurt` ...
	`chaos`: arcane damage `rand(power * 5/6, power)`, none if the monster is immune to
	arcane), sleeps (`sleep`, `dream`, `nightmare`: the monster stays asleep while `rand(1,
	15) <= power`; a ward against sleep may stop it), damage buffs (`craze`, `rage`, `fury`: +power% damage) and
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
| `spells.icon_url(spell)` | `/static/images/skills/<icon>.png`, or `.../default.png` when it has none or the file is missing |
| `spells.label(spell)` | `"Heal (5 MP)"` (button tooltips) |
| `spells.buttons(list, mp)` | the fight menu's and Fast Spells' buttons: `{ id, name, mp, label, icon, short, spell }` (`short`: `mp` doesn't cover it; `spell`: the row, for `tip("spell", b.spell)`) |
| `spells.learn(user_id, id, level)`, `spells.set_known(user_id, ids)` | teach one (known ones keep their level) / set the whole list |

Adding a spell: copy a file in `app/content/spells/` to `<key>.lua` (`hurt.lua` for an
attack, `heal.lua` for a heal, `rage.lua` for a buff), edit its data and code (and give it
an `icon`, see above, or leave the default), list the key
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
	if s.target:immune_to("arcane") then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)   -- the original's rand(max * 5/6, max)
	s:say("hit", s.name, s.target:hurt(damage, "arcane"))   -- what it really dealt
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

**Combatants** (`s.caster`, `s.target`; the player, monsters and summons alike) have
read-only fields `id` (the combatant's number in the fight), `side` (`"player"`, `"ally"`,
`"enemy"`), `name`, `is_player`, `level`, `hp`, `maxhp`, `mp`, `maxmp`, `tp`, `maxtp`,
`attack`, `defense`, `strength`, `dexterity`, `attack_element` (the element of its attack:
the player's weapon's, a monster's `attack_element`, a summon's `element`; default
`"neutral"`), and, from its statuses, `asleep`, `sleep_chance`, `uber_damage`,
`uber_defense`; in a fight `attack`, `defense`, `strength` and `dexterity` are under the
battlefield's fields' percents ([Fields](#fields)); and methods (resistances and wards: see
[Elements and wards](#elements-and-wards)):

| | |
|---|---|
| `:heal(stat, n)` | restores up to `n` of `"hp"`, `"mp"` or `"tp"`, never above the maximum (and never lowering a value above it); returns what it restored |
| `:hurt(n [, element])` | `n` damage of `element` (default `"neutral"`) through the damage formula: returns what it really took (HP may go below 0; the fight decides who died); immune: 0; a combatant that absorbs the element heals instead (never above its maximum) and it returns 0 |
| `:resist(element)`, `:immune_to(element)` | its resistance to the element (percent, -100..200, summed from its own, its gear's and its statuses'); whether it is 100 or more |
| `:ward(key)` | its ward against status `key` (percent chance, 0..100, that it doesn't take hold) |
| `:spend(stat, n)` | uses up `n` of a stat (a cost) |
| `:buff(kind, pct)` | `"damage"`: +pct% damage dealt, `"defense"`: -pct% damage taken, until the end of the fight (the statuses `uber_damage` / `uber_defense`; 0 ends it) |
| `:sleep(chance)` | asleep (the status `sleep`); stays asleep while `rand(1, 15) <= chance`, rolled on every clock tick (0 wakes it); returns whether it fell asleep (false: a field or its ward stopped it) |
| `:afflict(key, params)` | applies the status `key` (see [Fight engine](#fight-engine)); `params`: names and plain values (`ticks`: how many clock ticks; the rest is the status's `t.data`); replaces an instance it has; returns whether it took hold (false: a field or its ward stopped it; the fields may also adjust its ticks and data, see [Fields](#fields)) |
| `:cure(key or kind)` | removes a status, or all of a kind (`"harmful"`, `"helpful"`, `"neutral"`); returns how many |
| `:has_status(key)`, `:status(key)`, `:statuses([kind])` | what it has: `{ key, name, kind, ticks_left, data }` copies |

Amounts are whole numbers >= 0; anything else is an error. The handle's numbers follow its
own changes during the action (heal, then read `hp`).

**Running an action** (`action.perform`): the framework checks the place (`usable_in`,
retired; the caller's message), runs `can_cast`/`can_use` (which may only decide: changing
anything there is an error), then `cast`/`use`, then deducts a spell's MP from the caster.
Nothing touches the game state meanwhile: the handles record an ordered list of events
(`heal`, `hurt`, `spend`, `buff`, `sleep`, `afflict`, `cure`, `summon`, `say`), and the
caller applies them (`fight/engine.lua` `engine.apply` on the fight model; outside fights
`lib/world.lua`) and saves. A refusal, or an error, returns no events, so nothing changes
and no MP, item or turn is spent. In fights the player's action is step 1 of the round
pipeline (`fight/act.lua` `act.run(f, action)`, see [Fight engine](#fight-engine)); town
casting (`town/heal.lua`) and the inventory's Use (`town/inventory.lua`) call
`action.perform` and `world.apply`.

More context methods: `s:summon(key, params)` (an ally joins, in fights, for `ticks` of
the clock; `s.summon_room` says how many more may), `s:charge(ticks, step)` and
`s:recharge(ticks)` (multi-stage actions), `s:seconds(n)` (`n` clock ticks in seconds, for
a line: "burns for %d seconds"), `s:field(key, { ticks = n })` (a field spell: field `key`
up for `n` clock ticks in place of its group's; true when it was set, false when that field
is already up or outside a fight) and `s:has_field(key)` (whether it is up; statuses'
hooks have `t:has_field`; see [Fields](#fields)), and the file's `stages = { release = fn
}` (named steps; see [Fight engine](#fight-engine)). A file declares the fields it sets
like the statuses it applies: `uses = { fields = { "rain" } }`.

**Monsters acting.** Messages are worded for the player. When a monster is the caster,
`s:say("hit", ...)` uses `messages.enemy.hit` if there is one (same arguments); otherwise
the line becomes a generic "The Dragon casts Hurt." (items: "The Dragon uses the Potion.")
followed by what changed since the previous line ("You take 13 damage.", "The Dragon
recovers 10 Hit Points.", "You are now Poisoned.", ...). Monsters cast spells and use items
from their loadouts (see [Monsters](#monsters)); `tests/lua/test_action.lua` and
`tests/lua/test_monsters.lua` cover both forms with monster casters.

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

## Fight engine

A fight is a model of combatants loaded and saved once per request (`fight/state.lua`), a
request plays at most one **round** of a deterministic pipeline (`fight/round.lua`), and
what happens to combatants (handles for content code, applying events, statuses, summons)
is `fight/engine.lua`. Monsters choose by weight (`fight/ai.lua`). The dice and formulas of
the original game stay in `fight/combat.lua`; `routes/fight.lua` picks the monster, checks
the player's choice (known spell, MP, item in the bag) and saves. Since 3.2 a fight runs on
the game's clock: statuses and allies count its ticks, and the player's turn has a deadline
([The server tick](#the-server-tick)); a command first catches the fight up to now.

**The fight menu** (`templates/fight/fight.html`, one form posting to `/fight`) is the
**hotbar** (3.1, see [Hotbar](#hotbar)): ten slots on the number keys, each an icon button
(`.action-btn`, `.spell-btn`, styled in `dk.css` and the themes; the slots in `fight.css`):
**1 Attack** `<button type="submit" name="fight" value="Fight" aria-label="Attack"
aria-keyshortcuts="1">` with `images/skills/attack.png`, **2-8** the player's actions, **9
Guard** (3.2) `<button type="submit" name="guard" value="Guard" aria-label="Guard"
aria-keyshortcuts="9">` with `images/skills/guard.png`, and
**0 Run** `<button type="submit" name="run" value="Run" aria-label="Run"
aria-keyshortcuts="0">` with `images/skills/run.png`, set apart (`.hotbar-run`) so it
isn't pressed instead; then, under **More**, the actions not on the bar, without keys. An
action's button (`templates/fight/action.html`, from the route's `gear_buttons`,
`spell_buttons` and `usable_items`, each with its `kind` and hotbar `key`) is one of: a
spell (see [Spells](#spells)); **gear** that casts (`<button type="submit" name="use_gear"
value="<user_items id>">` with the item's picture and its charges on a badge,
`.item-badge-charges` "3/5", red and disabled at 0; tooltip `tips.gear`); an **item** (each
consumable in the bag usable in fights, one button per item: `<button type="submit"
name="item" value="<items id>">` with its picture and how many on a badge, `.item-badge`;
disabled when its `can_use` refuses now, checked by `act.can_use` with no dice; tooltip
`tips.consumable`). `POST /fight` reads a consumable from `item=<id>`; the form before 2.4
(`item=Use Item&useritem=<id>`) still works (`useritem` wins), and a missing or `0` id is
"You must select an item first". `use_gear=<id>` must be an entry of the player's that is
equipped and casts a spell ("You do not have this item equipped.") with a charge left ("The
Wand has no charges left. Rest at an inn to recharge it.", without the inn for a single-use
item; nothing happens, the turn isn't
spent); the round then casts the spell through the spell's code with the player as caster
and no MP cost (`act.run` with `{ kind = "gear", item, spell }`, an `item` step in the
trace), and the route spends one charge (`inventory.spend_charge`), also when the player
dies that turn. The route only checks that the
field is there (`form.fight`, `form.guard`, `form.run`), so `fight=Fight` and `run=Run`
(the text buttons before 2.4, old forms, tests) and whatever value a button sends play the
same. Each button sits in a span carrying its tooltip (`.action-tip`, `.spell-tip`;
`tips.attack(power, weapon)`: "Attack", the player's attack power and weapon, what it does;
`tips.guard()`, `tips.run()`), as fight.js disables the buttons while a round plays. **Guard**
costs the turn and puts on the status `guarding` (helpful: weapon attacks deal a quarter
less, `modify_damage_taken`) until the player's next turn begins, when the round ends it; a
turn that runs out is a Guard. A turn a status blocks shows only the "Continue" text button
(`continue=Continue`), which any number key presses: the turn ends at the clock's next
tick (a round with the blocked turn), so a command now plays nothing, and Continue just
shows the fight again. **The turn's timer** (`templates/fight/clock.html`, the region
`fight-clock` under the hotbar: `data-turn-ends`, when the turn runs out, a blocked one at
the next tick, and `data-now`, the server's time, both unix seconds; a region of its own
because `data-now` differs on every request): fight.js works out its clock's offset from
`data-now` and draws a thin bar draining over the turn's last 20 seconds
(`.fight-clock-bar`, `data-client`; moved each second, without its 1 s slide under
`prefers-reduced-motion`). It is display only: the server plays the timeout.
**The model** (`fight/state.lua`; tables `fights`, `fight_combatants`, `fight_statuses`):

| | |
|---|---|
| `f` | `{ user_id, round, wave, data, st, in_fight, combatants, next_id, outcome, log, result, tick, deadline }`. `data`: fight-level values, among them the battlefield's fields (`field_<group>`, and a spell's ticks: [Fields](#fields)); `round` counts the rounds played (the encounter's first strike is round 1, so the first form carries 2; no cap, unlike the original's 255); `st` is `game.player(user)` (the player's HP/MP/TP stay in `users`); `outcome`: `""` in progress, `"victory"` or `"death"` for a finished fight kept for its page; `log`: the lines since the player's last command, its round's and then what the clock did, at most `encounter.LOG_LINES` (60), the latest (`encounter.log_of`, `encounter.log_add`, `encounter.lines`: paragraphs in order); `result`: a victory's rewards; `tick`: the last clock tick it played (0: not on the clock yet); `deadline`: the tick the player's turn runs out at (`fights.due`, when the server's tick must advance it, is `state.due(f)`, written by `state.save`) |
| combatant `c` | `{ id, side = "player" \| "ally" \| "enemy", kind = "player" \| "monster" \| "summon", entity_id, wave, hp, maxhp, mp, maxmp, ticks_left, data, row, statuses }`, numbered from 1 per fight (the player is 1); `row` is the summons row, or the monsters row with its equipment counted (`monsters.effective`); `mp`/`maxmp`: a monster's MP; `ticks_left`: the clock ticks an ally stays (nil: the whole fight); `data`: a monster's item stock (`stock_<position>`) and the turns it acted (`turn`: its conditions' `m.turn`) |
| status instance | `{ status_id, key, row, ticks_left, data, tick, source }`: `data` holds the params it was applied with, `tick` the last clock tick it counted (at first the one it was applied in), `source` the combatant who applied it |

`state.load(user, st)`, `state.save(f)`, `state.clear(user_id)` (an escape, a new
encounter) and `state.forget(user_id)` (a move or travel: a finished fight's page goes).
How a fight begins and ends is `fight/encounter.lua`: `encounter.begin(user_id)` (POST
`/move`'s 1-in-5: the monster picked where the player stands, its first strike played when
it is quicker), `encounter.win(user, f, r)` (the rewards paid in the winning round, kept in
`fights.result` for `GET /victory`) and `encounter.die(user, r)`. Saved values are **names and plain
data only** (whole numbers, text, booleans: `state.encode`, "name=i:5" lines;
`action.params` refuses functions and tables), so a fight in progress never holds code: a
charged spell's release step is saved by name.

**Encounters and waves.** A fight is an ordered list of waves of enemies (`c.wave`); today
every encounter is one wave with one monster (the original random pick). The pipeline
already acts with every enemy of the current wave; when the wave is defeated the next one
enters ("Another monster appears: ..."), and the victory is "no enemy left". The winning
round pays each defeated enemy's rewards (summed) and rolls for a drop once (at the highest
level); `GET /victory` shows them. The player's actions aim at "the current target" (`engine.target`: the first
living enemy of the wave, `s.target` in spells), so a target picker can come later without
changing spell files.

**The round** (`round.play(f, a)`; `a.kind`: `attack`, `spell`, `item`, `gear`, `guard`
(`a.timeout`: the turn ran out), `run`, `continue`, or `ambush`: the monster swung first):

1. the player's action; a status that blocks the action makes the turn a skip (with its
	 `blocked` message). A refused spell or item (or one whose code fails) leaves the fight
	 exactly as it was: the round runs on a copy (`state.copy`);
2. each ally (summon), in the order summoned: its `act` unless blocked;
3. each enemy of the current wave: unless blocked (its `blocked_other` message), an action
	 and a target chosen by `fight/ai.lua` (a monster that acts counts its turn: `m.turn`);
4. the player's next turn begins: `guarding` ends.

No status ticks in a round: they tick on the clock (below). After each step that changed
HP the round checks the outcome: the player dead is the death (as before), the last enemy
defeated the victory, an ally at 0 HP leaves ("Your Wolf has been defeated.", or its
`on_death`). The result `r` has the lines of each part (`player`, `allies`, `enemies`,
`ending`; `round.lines(r)`: them in order), the model after the round (`r.f`) and
`escaped`, `victory`, `died` or `refused`; the caller starts the next turn
(`round.next_turn(f)`: the round counter +1, the deadline `round.TURN` ticks after
`f.tick`). `round.start(f)` rolls a new encounter (each enemy's HP, then who swings first).
`round.locked(f)`: the player has a blocking status, so the page offers only "Continue", a
command plays nothing, and the turn ends at the clock's next tick.

**The clock** (`round.advance(f, n [, limit])`, see [The server tick](#the-server-tick)):
every tick after `f.tick` up to `n` in order: the battlefield's fields follow the weather and
count down, and their `on_tick` runs ([Fields](#fields)); a blocked turn ends (a round with `continue`:
its blocked line, the allies and monsters acting); every combatant's statuses tick and
count down (`engine.tick(f, c, k)`: those applied before tick `k`, which counts from the
tick after a status came, so one put on in a round played at a tick waits for the next)
and allies count down (`engine.summon_tick`); a turn whose deadline passed is a Guard
round. It returns the lines in order (`{ part, line }`), how many ticks it played,
`changed` and `died` or `victory`. Status and summon code runs at most `engine.MAX_RUNS`
times per round and per tick. `fight/encounter.lua` `encounter.advance` runs it for the
server's tick and before every command.

**The trace.** With `f.trace = {}` set on the model before `round.play` or `round.advance`
(a live request does), they record in `f.trace`, in order, every line said, every change
of HP, MP or TP, every status applied, counted down, expiring or removed, every ally
joining, counting down or leaving and every field coming up or going, each with its step (`f.doing`: who acts and how, set by
`engine.doing(f, c, kind)` / `engine.done(f, prev)` around the code that acts). Lines go
through `engine.say(f, line)`. Tracing rolls nothing and changes nothing (the equivalence
test below traces every other fight); `fight/events.lua` turns it into the live client's
events.

**Equivalence.** Fights without summons, new statuses or timeouts roll exactly the
original's dice, in the same order, with the same messages and results: no AI roll with
one action and one target, the damage/defense buffs as statuses with the original
formulas. `tests/lua/test_round.lua` plays 1,000 seeded fights through the pipeline and
through a frozen copy of the 2.1 fight (`tests/lua/fight_original.lua`) and compares every
roll, line and state. Sleep's match is retired (3.2): a sleeper rolls to wake on the
clock's ticks, not at the start of its turns, so those fights cast no sleep spells and the
new sleep rules have tests of their own.

### Statuses

A status (`app/content/statuses/<key>.lua`, table `statuses`) is a named, timed effect on
a combatant: poison, a buff, sleep, "recharging". Its time is the game's clock (3.2): it
lasts `ticks` of 10 seconds, and its `on_tick` runs on each of them.

```lua
-- app/content/statuses/poison.lua
local function tick(t)                       -- t: the status context
	local damage = t.bearer:hurt(t:roll(t.data.min, t.data.max), "poison")   -- what it took
	if t.bearer.is_player then t:say("hurt_you", damage) else t:say("hurt", t.bearer.name, damage) end
end

return {
	name = "Poisoned",
	description = "Loses hit points every 10 seconds.",
	kind = "harmful",            -- harmful | helpful | neutral (an antidote cures "harmful")
	ticks = 3,                   -- default duration in clock ticks (0: until removed or the fight ends)
	data = { min = 2, max = 5 }, -- defaults of t.data (admin-overridable)
	messages = { hurt = "The %s takes %d poison damage.", hurt_you = "You take %d poison damage." },
	on_tick = tick,              -- on every clock tick; or inline: on_tick = function(t) ... end
}
```

- Fields: `name`, `description`, `kind`, `scope` (`"fight"`, the default: ends with the
	fight; `"world"`: outside fights only; `"both"`), `ticks`, `blocks_action`
	(`true`, or a `function(t)` returning true while it blocks), `data`, `messages`
	(`blocked`: said when it blocks the player's turn; `blocked_other`: anyone else's, `%s`
	the name), `resist` and `ward` (what it gives its bearer, like a monster's: `resist = {
	fire = 50 }` for a fire ward; see [Elements and wards](#elements-and-wards)). Hooks, all
	optional: `on_apply(t)`, `on_tick(t)`, `on_expire(t)` (ran out), `on_remove(t)` (cured or
	replaced), `modify_damage_dealt(t, damage, element)` and `modify_damage_taken(t, damage,
	element)` (an attack's; return the new damage, a whole number >= 0; they only decide,
	like `can_cast`). A tick that hurts names its element (`t.bearer:hurt(n, "poison")`:
	burning is fire, poison and venom poison, withering shadow).
- The context `t`: `t.bearer` and `t.source` (handles; `source` may be nil),
	`t.ticks_left` (nil: no limit), `t.data` (the status's data under the params it was
	applied with), `t.name`, `t.messages`, `t.round`, `t.in_fight`, `t:roll`, `t:say`,
	`t:expire()` / `t:remove()` (end it, once the hook returns), `t:release()` (charging:
	run the charged action's stage), `t:has_field(key)` (the battlefield: [Fields](#fields)).
- Applying: `s.target:afflict("poison", { ticks = 2, min = 1, max = 3 })` from any
	context (`turns` is refused: durations are ticks since 3.2). **Re-applying replaces** the
	instance: the old one's `on_remove` runs (not `on_expire`), then the new one's
	`on_apply`, with the new duration and params even when shorter; there is no stacking.
- Timing (the clock, `engine.tick`): a status counts the clock's ticks after the one it
	was applied in, whatever the rounds do: on each it ticks (`on_tick`), then counts down,
	and at 0 it expires. A poison cast at 10:00:03 first ticks at 10:00:10, and a 3-tick
	one is gone at 10:00:30. Its chip on the fight page says the time left ("20s",
	`clock.duration`). Messages say durations in seconds: `s:seconds(n)` is `n` ticks in
	seconds (`clock.TICK` each).
- The original mechanics are statuses 1-3: `sleep` (blocks: the sleeper's turns are
	skipped with its `blocked` / `blocked_other` line, "The Shadow is still asleep."; on
	every clock tick `rand(1, 15) > chance` wakes it: "The monster has woken up."),
	`uber_damage` and `uber_defense` (damage modifiers with the original formulas). `:buff`
	and `:sleep` apply them; anyone can be put to sleep or buffed now. 3.2 adds `guarding`
	(the Guard action's: weapon attacks deal a quarter less until the next turn).
- Robustness: an error in a hook is logged as a warning and removes that status (without
	its hooks); the round goes on. At most `engine.MAX_STATUSES` (10) per combatant (more
	are not applied, logged); at most `engine.MAX_RUNS` (100) runs of status and summon
	code per round and per clock tick (the rest is skipped, logged). A status whose file is
	gone (retired) ends when the fight loads.
- **World statuses** (`scope = "world"` or `"both"`, applied outside a fight, like the
	Regen Potion's) live in `user_statuses` and tick on the clock too (the server's tick:
	`lib/world.lua` `world.advance`; they can't take the last hit point; while the character
	fights, the ticks pass them by), outlast fights and take no part in them; the character
	page lists them with their time left. Their lines aren't shown. In a fight a "world"
	status isn't applied, and outside one a "fight" status isn't (logged).

### Multi-stage actions

- **Recharge** (Hyper Beam): `cast` hits, then `s:recharge(1)` puts the caster in
	`recharging` (blocks, 1 tick): its next turn is skipped at the clock's next tick ("You
	must recharge this turn."; until then the page offers only "Continue") and the monster
	still acts; then the status runs out.
- **Charge** (Solar Beam): `cast` calls `s:charge(1, "release")`: the caster is `charging`
	(blocks, 1 tick) with the params `{ entity = "solar_beam", from = "spell", release =
	"release" }` (names only). At the clock's next tick the blocked turn ends ("You are
	gathering power.", the monster acts), then the status runs out and its `on_expire`
	calls `t:release()`, which runs the file's `stages.release(s)` with the caster and its
	current target: the caster's action, between the player's turns.

```lua
-- app/content/spells/solar_beam.lua (excerpt)
local function release(s)
	if s.target:immune_to("fire") then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)
	s:say("hit", s.name, s.target:hurt(damage, "fire"))
end

return {
	-- name, mp, power, messages ...
	uses = { statuses = { "charging" } },     -- declared: dk check knows the key
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
```

### Summons

A summon (`app/content/summons/<key>.lua`, table `summons`) is an ally on the player's
side, called by `s:summon("wolf", { ticks = 5 })` (in fights; a file refuses in `can_cast`
when `s.summon_room` is 0: at most `control.max_allies` allies, default 1, "Allies" in the
main settings).

```lua
-- app/content/summons/wolf.lua
local function act(a)                        -- a: the summon's context
	local damage = a:roll(a.self.attack // 2, a.self.attack)
	a:say("bite", a.self.name, a.target:hurt(damage, a.self.attack_element))   -- its `element`
end

return {
	name = "Wolf", hp = 30, attack = 12, defense = 5, dexterity = 4,
	ticks = 5,                                 -- clock ticks it stays (0: the whole fight)
	messages = { bite = "Your %s bites the monster for %d damage.", gone = "Your %s runs off into the wild." },
	act = act,                                 -- once per round, after the player
	on_expire = function(a) a:say("gone", a.self.name) end,   -- optional; on_summon, on_death too
}
```

The context `a`: `a.self` (its handle), `a.target` (chosen by the AI), `a.data` (its
params), `a.ticks_left`, `a:roll`, `a:say`. Monsters may attack an ally instead of the
player; the original formula then uses the ally's defense and dexterity. An ally acts once
per round and counts the clock's ticks: it leaves at 0 HP, when its ticks run out ("Your
Wolf leaves the fight.", or its `on_expire`) or when the fight ends; an error in its code
removes it. Its
file may give `element` (its attacks', handed to its `act` as `a.self.attack_element`),
`resist` and `ward` (3.2, see [Elements and wards](#elements-and-wards)).

### Monster AI

`fight/ai.lua`: `ai.pick(list, rand)` picks by `weight` (default 1, `rand(1, total)`; a
single candidate is taken **without a roll**). `ai.choose(f, c)` picks an action among
`ai.actions(f, c)`, then a target among `ai.targets(f, c)` (every living opponent weighs
1: with one summon a monster attacks the player or the summon 50/50; alone with the
player there is no roll; an action with `target = "self"` aims at the monster itself).
Actions come from providers (`ai.PROVIDERS`, `ai.provide(fn)`): functions `(f, c)`
returning candidates `{ kind, weight, target = "opponent" | "self", perform = function(f,
c, target) }`: a monster's attack (weight `attack_weight`, `act.enemy_attack`; with weight
0 it is the fallback when nothing else is eligible, without a roll), the spells and items
of its loadout it may use this turn (`fight/monster.lua`, see [Monsters](#monsters)) and
an ally's `act`.

### Adding a status or a summon

Copy `app/content/statuses/poison.lua` (or `regen.lua`, `recharging.lua`) or
`app/content/summons/wolf.lua` to `<key>.lua`, edit it, and use the key from a spell or an
item (`s.target:afflict("<key>", ...)`, `s:summon("<key>", ...)`; declare it with `uses =
{ statuses = { "<key>" } }` so `./dk check` catches typos), then run `./dk check`. The
admin pages `/admin/statuses` and `/admin/summons` override names, descriptions, numbers
and messages per server. Unit tests can run statuses and summons without files:
`load.preload(kind, key, module)` primes the loaded module (see `tests/lua/test_round.lua`).

### Fight events (smooth fights)

With the [live client](#live-client) a fight round plays in place: the fight forms are sent
like any other form, and the answer to a live request carries the round's **events** (an
`events fight` frame: the JSON list below), which `public/js/fight.js` plays on the page
being shown before the page's regions apply. The server side is the fight routes
(`routes/fight.lua`): when `req.live`, the request records its trace (the clock's ticks
it caught up first, then its round: their events come in that order) and `go` puts the
events on its redirect (`res.events`), which `main.lua` carries into the answer of the page
it lands on (`/fight`, `/victory`, `/`). What the server's tick does to a fight comes as
`stale` instead: the page asks for itself again and shows the new lines without playing
them. Everything
else is the page: the same handlers, the same round code, the same templates, so what stays
on screen is what a page load shows. (2.3's JSON fight API, `Accept: application/json` with
`fragments`, is gone: the live client replaced it.)

**Events** (`fight/events.lua`, from the round's trace): one per line of the page, in the
page's order, with what changed with it; a change in a step that hasn't said anything is
an event without `text`. The texts are exactly the lines the page shows (unescaped:
put them in with `textContent`). Nothing else of the model leaks (no status data, rolls,
stock, resistances).

```lua
{
	part = "player",               -- the page's paragraph: player, allies, enemies, ending
	actor = "enemy", actor_id = 2, actor_name = "Goblin Shaman",   -- who acts (a status: its bearer)
	type = "spell",                -- attack, spell, item, guard, status (a status's tick or hook, or
	                               -- its countdown), summon (an ally acting, joining, leaving),
	                               -- blocked (a status blocks the turn), run, ambush, wave (the next
	                               -- enemy), field (the battlefield: the weather's fields coming and
	                               -- going, a field's on_tick), speech (a monster speaking: "Troll: “Tickles.”", see
	                               -- [Monster speech](#monster-speech)), say (anything else); the last event of a round that
	                               -- ended: victory, death or escape (no text)
	text = "The monster casts Hurt on you for 14 damage.",   -- absent: a change without a line
	hp = { { who = "player", id = 1, name = "Fapi", from = 300, to = 286, max = 300 } },
	mp = { { who = "enemy", id = 2, name = "Goblin Shaman", from = 17, to = 12, max = 17 } },
	tp = { ... },                  -- who: player | ally | enemy; an enemy's MP only if the page shows it
	status = { { who = "player", id = 1, name = "Fapi", key = "poison", status = "Poisoned",
		ticks = 3, change = "add",   -- add | remove | expire | ticks (counted down)
		statuses = { { key = "poison", name = "Poisoned", ticks = 3, left = "30s",   -- the bearer's, after it
			icon = "/static/images/statuses/poison.png" } } } },   -- (icon: absent when none)
	summon = { { change = "join", id = 3, name = "Wolf", hp = 30, max = 30, ticks = 5 } },   -- join | leave | ticks
	field = { { key = "rain", name = "Rain", change = "add",   -- add | remove: the battlefield's
		icon = "/static/images/fields/rain.png" } },             -- (icon: absent when none)
}
```

Lists are present only when not empty; `ticks` (clock ticks left) is absent for an
unlimited status or ally, and `left` is what its chip says (`events.left`).
Changes go with their step's latest line (a spell's line, then its damage and MP cost).

**Every command comes back to the fight page** (Post/Redirect/Get): a `POST
/fight` that played a round saves its lines (`fights.log`: what catching up said, then the
round's) and redirects to `/fight` (a victory to `/victory`, an escape to `/`), and `GET
/fight` shows them, as often as it is loaded, with the lines the clock added since (the
server's tick appends them: a status's tick, a guard). The live client follows the
redirect on the server, so a round is still one request, with its events.

**Refusals** (not enough MP, a spell not learned, an item not in the bag, a wand without
charges, a content file's `s:refuse`): nothing is played or spent, and the fight page comes
back with the reason as a note above the commands (`<p class="fight-note error"
role="alert">`), the last round's lines still there; the note is kept with them
(`encounter.with_note`) until the next round replaces them. Their texts were written for an
error page of their own: the note leaves out "Please go back and try again.".

**Stale rounds.** Every fight form carries the round it was shown at (`<input type="hidden"
name="round">`, `fights.round`, which only a played round counts up). A `POST /fight` with
another round (a second click, an older tab, a resubmitted page, a page from before a turn
the clock ran out or a blocked turn it ended: the POST catches up first) plays nothing: the fight
page comes back with the note "That command came from an older page, so nothing happened."
at the top (kept like a refusal's); a fight that is over (not fighting any more) redirects
to `/`. A form without the field (from before 2.3) plays as before. The counter has no cap (the original's
stopped at 255), so long fights are protected too.

**fight.js** (`DK.on("events:fight")`): while the round plays the fight forms' controls are
disabled (`data-fight-locked`); it clears the round lines (`[data-fight-log]`) and adds each
line (in the page's paragraphs, `fight-yourturn` ... `fight-roundend`) 400 ms after the
previous one; its changes update the player's numbers and bars in the right column
(`[data-meter=hp|mp|tp]` values, `[data-bar=hp|mp|tp]` widths), the numbers and bars of the
monsters and allies (`[data-fighter=<id>][data-stat=hp|mp][data-value][data-max]`), the
status chips of a combatant's line (made if the page had none), allies joining and leaving,
and the Battlefield line's fields (`[data-battlefield]`: a field coming up is added with a
glow, `.fight-field-new`; one going is struck out, `.fight-field-gone`).
A click in the middle column, any key (not while typing) or the "Skip" button plays the rest
at once; with `prefers-reduced-motion` there are no delays and no animations (`fight.css`).
A round that ends in a victory or an escape pauses 800 ms before the next page comes. Then
the regions apply; when the keyboard was in the middle column, the button that sent the
round gets the focus back (the same spell's button, unless it is now disabled; else
Attack). The monsters' and allies' bars are fight.js's (`span.fight-meter[data-client]`, so
the morph keeps them; it updates them from `data-value`/`data-max` after every answer):
without JavaScript there are none, as before. So is the turn's timer (the `fight-clock`
region, see the fight menu above). Without the live client the forms post as plain forms
and nothing is played.

**Adding an animated event type.** A new kind of line needs nothing: give the code that
says it a step (`local prev = engine.doing(f, c, "my_kind")` ... `engine.done(f, prev)`
around `engine.say` and the changes) and it arrives with `type = "my_kind"`; add the type to
the list above and to `TYPES` in `tests/e2e/fight_api.sh`. A new kind of change: record it
in the trace where it happens (`trace(f, { my_change = ..., id = c.id, ... })` in
`fight/engine.lua`), turn it into a field of the event in `events.build` (plain names and
numbers only), apply it in fight.js's `show(e, log)` (look elements up by
`data-fighter`; build DOM with `textContent`), add a CSS animation in `fight.css` (and its
`prefers-reduced-motion` exception), and extend the shape check in `fight_api.sh`.

## Elements and wards

(3.2, `docs/plans/elements-and-weather.md` parts 1 and 2.) Every hit has an **element**, and
every combatant a **resistance** to each element and a **ward** against each status. The
battlefield's fields ([Fields](#fields)) scale damage by element before resistance, and may
keep a status from taking hold before its ward is rolled.
`app/lib/elements.lua` (pure) holds the elements, the damage formula and the lines.

- **Elements** (`elements.LIST`, in this order): `neutral` (shown as "Physical"), `fire`,
	`frost`, `lightning`, `water`, `wind`, `earth`, `holy`, `shadow`, `arcane`, `poison`.
	Weapons, armor and attacks are neutral unless they say otherwise. The player's attack is
	its weapon's `element`, a monster's its `attack_element`, a summon's its `element` (its
	`act` passes it: `a.target:hurt(damage, a.self.attack_element)`). Spells and items name
	theirs in `:hurt`: the original hurt spells, Magic Bolt, Sap Mind, Starfall and the Void
	Flask are arcane; Ember, Inferno, Cinder Lash, Solar Beam and the Fire Flask fire;
	Frostbite and Whiteout frost; Spark and Lightning Lance lightning; Rockfall earth;
	Dawnstrike and Judgement holy; Withering and Curse shadow; Poison, Venom, Plague and the
	Acid Vial poison. The Warrior's strikes (Cleave, Reaver, Blood Strike, Finishing Blow) are
	neutral. Status ticks too: burning is fire, poison and venom poison, withering shadow.
- **Resistance**: a percent per element, summed from every source (the monster's or
	summon's file `resist = { fire = 50, frost = -50 }`, gear modifiers `{ kind = "resist",
	element = "fire", amount = 25 }`, statuses' `resist`) and clamped to -100..200: below 0 a
	weakness, 100 immunity, above 100 it absorbs. `h:resist(element)`, `h:immune_to(element)`
	(`resist >= 100`).
- **The damage formula**, the only one (`elements.damage(n, field_pct, resist)`: attacks in
	`fight/combat.lua`, `:hurt` for spells, items and status ticks): `scaled = floor(n * (100
	+ field_pct) / 100)` (never below 0; `field_pct` is the battlefield's percent for the
	element, the sum of the fields' up: `fields.pct`, see [Fields](#fields); handed to
	`engine.typed` for attacks and to the action context as its `battlefield`), then
	`floor(scaled * (100 - resist) / 100)`; at
	100 it deals 0, above 100 it deals 0 and heals `floor(scaled * (resist - 100) / 100)`
	(never above the maximum). A hit that dealt at least 1 before resistance and isn't
	resisted fully deals at least 1. With no field and no resistance it is `n`: fights
	without affinities roll and say exactly what they did (`tests/lua/test_round.lua`).
- **`target:hurt(n [, element])` returns what it really dealt**: spells print that ("for
	%d damage"); an immune or absorbing target returns 0. Immune messages come from
	`immune_to`: `if s.target:immune_to("arcane") then return s:say("immune", s.name) end`.
- **Lines**: a hit against a weakness or a resistance adds a line after the next one said
	(the spell's damage line; for an attack, its "You attack the monster for 9 damage."):
	"It is weak to fire!", "It resists frost.", "It is immune to arcane force.", "It absorbs
	the lightning!" ("You resist frost." when the player is hit; `elements.note`).
- **A ward** is a percent chance, 0-100, that a status doesn't take hold, keyed by status
	key and summed like resistances: a file's `ward = { sleep = 100 }`, gear `{ kind = "ward",
	status = "sleep", amount = 25 }`, statuses' `ward`. `h:afflict(key, params)` and
	`h:sleep(chance)` return true when the status took hold, false when the ward stopped it;
	`h:ward(key)` reads it. A ward of 0 and one of 100 roll nothing; 1-99 rolls `rand(1,
	100)` with the action's dice once (resisted at or below the ward). Status spells say
	their "immune" message when the ward is 100 and "resisted" otherwise
	(`s:say(s.target:ward("sleep") == 100 and "immune" or "resisted", s.name)`); thrown items
	refuse (cost nothing) against a certain ward or immunity.
- **Where they show**: the monsters help page (an Affinities column) and a monster's
	tooltip (`elements.lines`: "Weak to Frost (+50%)", "Resists Fire (50%)", "Immune to
	Arcane", "Absorbs Lightning (20%)", "Wards off Sleep (100%)"); the character sheet
	(the player's, from gear and world statuses, when any); item lines ("Fire Resistance
	+25%", "Sleep Ward +25%"); the monster admin editor (`resist.<element>`,
	`ward.<status>`).
- **Storage** (schema version 21, `lib/content/affinities.lua`): the flat form has
	`resist.fire` and `ward.sleep`; the `monsters`, `summons` and `statuses` tables keep them
	as text (`resist`, `ward`: `"fire=50,frost=-50"`), and `lib/monsters.lua`,
	`lib/summons.lua` and `lib/statuses.lua` give them back as tables. A ward's status must
	be a status file (`dk check`). The handles take a combatant's own (`resist`, `ward`: its
	file's and its gear's) and each status's; a fight's saved data holds none of them.
- **The end of `immune`**: monsters' `immune` (0, 1: hurt spells, 2: hurt and sleep) became
	`resist = { arcane = 100 }` and, for 2, `ward = { sleep = 100 }`, in the files and on the
	rows; step 21 turned admins' overrides of it into `resist.arcane` / `ward.sleep`
	overrides where they differ from the file, and pending adoptions of it (a database from
	before version 9) into adoptions of only what differs from the original game's
	immunity (`V21_STOCK_IMMUNE`): the files' affinities have changed since, and a stock
	immunity is no edit, so an unedited monster gets its file's affinities.

Testing: `tests/lua/test_elements.lua` (the formula, clamps, immunity, absorbing, the lines,
the handles' API and the wards' dice), `tests/lua/test_spells.lua` (a monster immune to
everything is never hurt or afflicted), `tests/e2e/monsters.sh` (a typed attack and a
resistance in a fight, the sheet, the help page, a class).

## Fields

(3.2, `docs/plans/elements-and-weather.md` parts 4 and 7.) A **field** is an effect on the
whole battlefield, for everyone in a fight: the weather's (rain, mud, the night), the
land's (a marsh, the peaks) or a spell's (consecrated ground). Fields are content (see [Content](#content)):
`app/content/fields/<key>.lua`, synced into `fields` (`lib/content/kinds/fields.lua`, rows
by `lib/fields.lua`), overridable in the admin panel (`/admin/fields`). What a field does
is data, so the pages can show it; only an optional `on_tick` is code.

```lua
-- app/content/fields/downpour.lua
return {
	name = "Downpour",
	description = "Hard rain: fire is weak, lightning strong, no fire can catch, ...",
	lore = [[...]],                   -- optional, like every kind's
	icon = "",                        -- a PNG in public/images/fields/ (optional; none here)
	group = "sky",                    -- sky | ground | time | terrain | aura: one field per group is up
	damage = { water = 15, lightning = 25, fire = -40 },   -- percent, by element (-100..1000)
	statuses = {                      -- how statuses behave under it, by status key
		burning = { blocked = true },   -- can't take hold (the field's `blocked` line)
		-- { ticks = -1 }: lasts a tick less (at least 1); { scale = { amount = 150 } }: a
		-- value it is applied with (or the status's default) at 150%; { chance = 50 }: takes
		-- hold half of the time (rolled after the ward)
	},
	stats = { dexterity = -10 },      -- percent on every combatant's attack, defense, strength, dexterity
	messages = { begins = "...", ends = "...", blocked = "The rain puts the fire out before it can catch." },
	-- data = { ... } and on_tick = function(e) ... end: optional (the thunderstorm's bolts)
}
```

- **The fields of a fight** (`fight/fields.lua`, the one place they combine; saved in the
	fight's data as names: `field_<group>` the key, and for a spell's `field_<group>_ticks`,
	its ticks left, and `field_<group>_tick`, the last it counted). The world's follow the
	weather at the player's tile ([Clock and weather](#clock-and-weather)): the field of the
	same key as the sky (`sun`, `heat`, `fog`, `rain`, `downpour`, `thunderstorm`, `snow`,
	`blizzard`), the ground (`mud`, `ice`) and the time (`night`), when a file of that key
	exists (`dk check`: a world field's group is the part of the weather it follows). They
	are up from the encounter's start (`fields.start`) and follow the weather on every clock
	tick the fight plays (`fields.advance`, the first thing `round.advance` does at a
	tick). A spell's (`s:field(key, { ticks = n })`, the player's or a monster's) takes its
	group's place for `n` ticks, counted from the tick after the one it was cast in, and
	when it ends the weather's comes back; `aura` fields (`consecrated`, `brimstone`,
	`miasma`) come only from spells. The **terrain** group is the land's: the field of the
	player's tile ([Terrain and the map](#terrain-and-the-map): `shallows` in a lake or a
	pond, `peaks`, `hills`, else the biome's own, `marsh`, `forest`, `sand` or `cinders`),
	up from the start like the weather's and followed the same way, which holds it for the
	fight (the player doesn't move in one). It has no `begins` or `ends` lines (it never
	changes in a fight; the Battlefield line shows it), and no spell can put one up
	(`s:field` with a terrain field is an error; `dk check`: a terrain-group field must be
	one the land names, and those must be in the terrain group). The 21 fields are the 11
	weather's, the 7 land's and the three auras.
- **Changes** become lines and `field` events: when only the weather's fields changed, at
	the weather's step, and no spell holds a group of it, the weather's change line
	(`weather.change`) says them all; otherwise each field that went says its `ends` and each
	that came its `begins` (a spell's too, after its own lines). A spell's field hides the
	weather's changes in its group until it ends. Because every command catches the fight up
	first, a spell cast just as the rain clears meets a clear sky: its burn takes hold. A
	fight on the clock is due at the weather's next step when that comes before its deadline
	(`state.due`), and every tick while a spell's field or a field with `on_tick` is up.
- **Combinations**: damage of an element is scaled by the sum of the fields' percents for it
	(`fields.pct`, the formula's `field_pct`: attacks through `engine.typed`, content's
	`:hurt` through the action context's `battlefield`, `fields.battlefield(f)`). A status
	being applied (`:afflict`, `:sleep`) meets the fields' rules: `blocked` stops it first,
	without a roll (the field's `blocked` message follows the next line said, like a
	resistance's), then its ward is rolled ([Elements and wards](#elements-and-wards)), then
	each field's `chance`; then `engine.afflict` adjusts what it is applied with (`ticks`
	added, `scale` on the named values: `fields.adjust`), which it keeps: rain starting later
	doesn't shorten a burn already burning. `stats` are percents on the handles' `attack`,
	`defense`, `strength` and `dexterity` (`engine.handle`: floor, never below 0), which the
	formulas read (`fight/combat.lua`'s attacks: a monster's attack rolls from its handle's,
	so fog weakens it; dodging reads the dexterity) and content sees. Running away and who
	swings first keep the unadjusted numbers. With no field up every one of these is the
	identity and rolls nothing: fights roll the same dice (`tests/lua/test_round.lua`).
- **The API**: `s:field(key, { ticks = n })` (spells and items; true when set, false when
	that field is already up or outside a fight; a key that isn't a field is an error),
	`s:has_field(key)` and `t:has_field(key)` (status hooks), `m:has_field(key)` in monsters'
	`when` conditions ([Monsters](#monsters)); a key that no field file has is an error there
	too (`action.field_info`), and so for status keys in the handles' `:has_status(key)` and
	`:status(key)`, so that a typo doesn't read as "not up". A field's `on_tick(e)` runs on every tick it is
	up, after the fields followed the weather: `e` is a context like a status's (`e:roll`,
	`e:say`, `e.data`, `e.messages`, `e.round`, `e.ticks_left`: a spell's field's) with
	`e.combatants` (every combatant standing: the player, the allies, the enemies of the
	wave, handles) and `e.player`. The thunderstorm's: one tick in `data.chance` (6) a bolt
	strikes a random combatant for `data.min`-`data.max` lightning. Its lines are a `field`
	event; an error is logged and the field stays.
- **Shown**: the fight page's **Battlefield** line under the monster
	(`templates/fight/battlefield.html`, the region `battlefield`, there and hidden when no
	field is up): each field's icon and name with a tooltip (`tips.field`: its group, a
	spell's time left, its modifiers as lines, "Fire damage -40%", "Burning can't take
	hold", "Burning lasts 10s less", "Sleep chance +30%", "Dexterity -20%":
	`fields.lines`, then the description and lore). `fight.js` adds and strikes out its
	fields as a round's `field` events play ([Fight events](#fight-events-smooth-fights)).
	`/help/fields` lists every field by group (sky, ground, time of day, terrain, aura: icon,
	group, modifiers, description, lore), linked
	from the help index. `/admin/fields` overrides the name, description, lore, icon, the
	damage percent of every element, the stats, the file's status rules, numbers and
	messages (the group is the file's).
- **Storage** (schema version 23): the `fields` table's `damage` and `stats`
	(`"fire=-40,water=15"`), `statuses` (`"burning.blocked=1,sleep.scale.chance=120"`),
	`messages` and `data`; the flat form's `damage.fire`, `stats.dexterity`,
	`statuses.burning.blocked`, `statuses.burning.ticks`, `statuses.burning.chance`,
	`statuses.burning.scale.amount`. A status a rule names must be a status file.

Adding a field: copy `app/content/fields/rain.lua` (or `thunderstorm.lua` for one with
`on_tick`) to `<key>.lua`, give it a group (`aura` unless the weather or the land brings
it), run
`./dk check`; a spell puts it up with `s:field("<key>", { ticks = n })` (declare it: `uses =
{ fields = { "<key>" } }`). Testing: `tests/lua/test_fields.lua` (the files and their
validation, nothing changing without fields, the damage percent, `blocked` before the ward,
`chance`, `ticks` and `scale`, stats on the handles, a spell's field displacing the
world's, auras, the terrain's field held and never a spell's, the weather moving the
fields and its events, a spell meeting a sky just cleared, `on_tick`, `m.turn`, the e2e
tests' calm place: `t_calm` in [End-to-end
tests](#end-to-end-tests)), `tests/lua/test_monsters.lua` (weight 0),
`tests/e2e/fields.sh` (the help page, the Battlefield line and its tooltips, nightfall in a
fight on the clock, a live round's `field` event, the admin page), `tests/e2e/migrate.sh`
(step 23), `tests/e2e/pure.sh`.

## Monsters

Monsters are content (see [Content](#content)): `app/content/monsters/<key>.lua`, synced
into `monsters` (`lib/content/kinds/monsters.lua`) and the loadout tables
`monster_equipment`, `monster_items` and `monster_spells`. The original 151 keep ids 1-151
(keys from the names: `blue_slime` ... `lucifuge`), the original game's stats and their
converted immunity (`tests/lua/test_monsters.lua` checks them against
`tests/lua/monsters_original.lua`); since 3.2 they have affinities, and many a fight pattern
(spells, items, a class), so only those still without a loadout attack exactly as before
(`tests/lua/test_round.lua` fights the original stats, attack only, against the frozen 2.1
fight). `goblin_shaman.lua`, `bog_witch.lua` and `bandit_captain.lua` are the commented
examples.

```lua
-- app/content/monsters/goblin_shaman.lua
local function low_hp(m)                    -- a free-standing condition
	return m.hp < m.maxhp // 3
end

return {
	name = "Goblin Shaman",
	description = "Hurls Hurt spells, heals itself when wounded and carries two potions.",
	level = 5,                                -- where it is met and what it drops
	maxhp = 40, maxdam = 8, armor = 4,        -- the original columns
	maxexp = 12, maxgold = 15,
	-- optional (not in this file): resist = { fire = 50, holy = -50 }, ward = { sleep = 30 },
	-- attack_element = "fire", class = "mage" (see below)
	maxmp = 17,                               -- MP at the start of every encounter (default 0)
	uses_mp = true,                           -- spells cost it MP (default); false: free
	attack_weight = 3,                        -- its attack's weight (default 1; 0: fallback only)
	roams = false,                            -- met in random encounters (default true)
	equipment = { weapon = "dagger" },        -- slot = item key (weapon, armor, shield, accessory1-3)
	spells = {                                -- { spell, weight (default 1; 0: never), when (optional) }
		{ spell = "hurt", weight = 2 },
		{ spell = "heal", weight = 3, when = function(m) return m.hp < m.maxhp // 2 end },
	},
	items = {                                 -- { item, weight, stock (per encounter; nil: no limit), when }
		{ item = "potion", weight = 4, stock = 2, when = low_hp },
	},
}
```

- **Validation** (`dk check`): the stats as above (`maxhp` >= 1, the entries' weights >= 0
	(0: never chosen, see below), `attack_weight` >= 0, `stock` >= 1 or absent; `resist` of
	known elements, -100 to 200; `ward` 0 to 100); item, spell, class and warded status keys
	must be files;
	equipment must fit its slot (a weapon in `weapon`, an accessory in `accessory1`-`3`);
	items must be consumables and spells usable in fights; `when` must be a function.
- **MP**: every original monster has `maxmp` = the Mage's total MP at its level (the 2.2
	start of 0 + the gains in `classes/mage.lua`, at least 5), written into its file (the
	Mage's start of 5 since 2.4 left them as they were), or more where its fight pattern's
	spells need it (3.2). A monster's MP is full
	at the start of each encounter (`fight_combatants.mp`/`maxmp`; a fight from before
	version 9 loads it full) and its spells cost `mp` like the player's (none affordable:
	not eligible). With `uses_mp = false` spells are free (MP is still shown and readable
	by conditions). Spells can restore a monster's MP (`:heal("mp", n)`); TP don't apply.
- **Equipment**: the items' attack, defense and modifiers count by the players' rules
	(`stats.monster`, the same `stats.derive`): the monster's base is `maxhp`, `maxmp`,
	strength and dexterity 0, `maxdam` as base attack and `armor` as base defense, so its
	effective `maxdam` = maxdam + strength + attack, `armor` = armor + dexterity + defense,
	`maxhp`/`maxmp` + their modifiers (experience and gold bonuses don't apply). The fight
	uses the effective numbers everywhere (`monsters.effective`: the encounter's HP roll,
	who swings first, running away, its attack, the player's attack on its armor, its
	handle's `attack`/`defense`/`strength`/`dexterity`). Without equipment they are the
	row's: the original monsters are unchanged. Monsters don't drop their equipment.
- **Choosing an action** (each turn it isn't blocked; `fight/monster.lua` as an AI
	provider): the candidates are its attack (`attack_weight`), every spell it can use now
	(usable in fights and not retired; enough MP with `uses_mp`; `when` passes; `can_cast`
	doesn't refuse) and every item it can use now (stock left; usable in fights; `when`
	passes; `can_use` doesn't refuse), in that order; one is picked by weight
	(`ai.pick`), then its target: the monster itself for a spell or item with `target =
	"self"`, otherwise an opponent by weight (the player, or a summon). With a single
	eligible candidate no roll is made, so attack-only monsters roll exactly the original
	dice (`tests/lua/test_round.lua`). Weighing the options rolls nothing: `can_cast` /
	`can_use` run through `action.check` (no dice: a roll there is an error and makes the
	entry ineligible), on the default target (the player); if the real use is refused after
	all (another target), the monster attacks instead.
- **`when` conditions** (inline or free-standing functions) get the monster as its AI sees
	it: `m.hp`, `m.maxhp`, `m.mp`, `m.maxmp`, `m.level`, `m.name`, `m.attack`, ... (its
	read-only handle, its numbers under the battlefield's fields), `m:has_status(key)`,
	`m:status(key)`, `m:statuses(kind)`, `m:has_field(key)` (the battlefield: [Fields](#fields)),
	plus `m.round` (the fight's round: the opening, an ambush, is round 1 and the player's
	first command round 2), `m.turn` (its own turns: 1 on its first action of the fight,
	counting only the turns it acted, not those a status blocked, ambush or not; kept in the
	combatant's data, so openers are `m.turn == 1` and rotations `m.turn % 4 == 0`),
	`m.target` (the default opponent's handle: the player; `m.target:has_status("sleep")`)
	and `m.stock` (items: uses left). They only decide: no
	dice, no changes (an error, logged, makes the entry ineligible this turn). A key that no
	file has is an error, not "no": `m:has_field("nightx")`, `m:has_status("sleeep")` and
	`:status` name it in the warning (else a typo in a negated condition would always pass;
	`tests/lua/test_patterns.lua` reports it). A retired status or field, its file deleted,
	counts as unknown too: nothing can carry it, and content that declares it in `uses`
	keeps `dk check` from letting its file go. They stay in
	the file (`has_when` in the loadout tables marks them; the runtime takes them from the
	loaded file by position).
- **Stock** is per encounter: `stock_<position>` in the combatant's data counts down on
	each use (an entry without stock has no limit); the next encounter starts full.
- **Using** a spell or item is `action.perform` with the monster as caster (its MP cost
	skipped with `uses_mp = false`), applied by `engine.apply`; lines are the files'
	`messages.enemy` wordings, or the generic "The Goblin Shaman casts Heal." / "uses the
	Potion." plus what changed. A monster can't summon (no room on its side).
- **Elements and wards** (3.2, see [Elements and wards](#elements-and-wards)): `resist`
	(percent by element: below 0 a weakness, 100 immunity, above 100 it absorbs), `ward`
	(percent chance by status key that the status doesn't take hold) and `attack_element`
	(its attack's element; default `"neutral"`). Its equipment's resistance and ward
	modifiers add to them (`monsters.effective`). The original `immune` became these:
	`immune = 1` is `resist = { arcane = 100 }` (the hurt spells are arcane), `immune = 2`
	that and `ward = { sleep = 100 }`.
- **Classes** (3.2): with `class = "mage"` its loadout gains every spell the class knows at
	the monster's level (its starting spells and those its levels teach up to there) that is
	castable in fights, weight 1 and no `when` (`monsters.loadout`, entries marked
	`from_class`), after its own spells; its own entry for one of them wins (its weight and
	`when`). It pays MP for them from `maxmp` like for its own (unless `uses_mp = false`).
- **Weight 0**: a `spells` or `items` entry with `weight = 0` is never chosen: the loadout
	leaves it out (`monsters.loadout`), and with it its class's spell of that key. That is how
	a class's unwanted spells are switched off: `{ spell = "dream", weight = 0 }`. The help
	page and the fight page don't count it.
- **Random encounters** pick among the roaming, non-retired monsters of the level band
	(`monsters.roaming`: the original rows and order). Monsters with `roams = false` (the
	examples) are only met where content or a test puts them (`state.add_monster(f, row,
	wave)` + `round.start(f)`); an admin can let one roam.
- **Admin** (`/admin/monsters`, the shared content admin `admin/effects.lua`): name,
	description, level, the stats, `maxmp`, `uses_mp`, `attack_weight`, `roams`,
	`attack_element`, its resistance to every element (`resist.<element>`) and its wards
	against the harmful statuses and those its file names (`ward.<status>`) are overridable;
	the loadout and the class are shown read-only (edit the file). The list keeps the
	original's check that the highest roaming level is the map size / 5.
- **Help** (`/help/monsters`): every non-retired monster with its effective stats and MP,
	its affinities ("Weak to Frost (+50%)", "Immune to Arcane", "Wards off Sleep (100%)";
	`elements.lines`), and the spells (its own, then its class's: "Mage spells: ..."; not
	those of weight 0), items (with stock) and equipment of those that have them. Its tooltip in a fight lists the
	affinities too.
- **Retired** monsters (file deleted) are no longer met; fights against them go on.

`lib/monsters.lua`: `monsters.get(id)`, `monsters.by_key(key)`, `monsters.active()`,
`monsters.all()`, `monsters.roaming(min, max)`, `monsters.loadout(row)` (`{ equipment,
items, spells }` with item and spell rows, read once per request; a row may carry its own
`loadout` table: tests; with its class's spells; without the entries of weight 0),
`monsters.condition(row, list, entry)`
(the `when` function), `monsters.effective(row)` (a copy with the equipment counted, base
values in `base`), `monsters.reload()`. Rows come back with `resist` and `ward` decoded into
tables.

### Monster speech

Monsters may speak in a fight (`app/fight/speech.lua`): a `speech` table in the file holds
lists of lines for moments of the fight. Nothing is ever certain: each moment speaks by
chance, and lines may be held back for conditions, or to once a fight. Every monster has
some (3.1; the Goblin Shaman's is the commented example): beasts and mindless things only
a sound now and then ("Kraa!", "*hisses*"), thinking ones in a voice of their own.

```lua
-- app/content/monsters/red_dragon.lua (abridged)
speech = {
	start = {                                   -- it appears
		"You smell of ash already, little knight.", "Kneel, and I may yet make it quick.",
		{ text = "Another thief come for my gold?", weight = 2 },   -- twice as likely
		chance = 70,                            -- percent; 0 to 99: never for certain
	},
	turn = {                                    -- its turn, before it acts
		"Burn.",
		{ text = "You sway on your feet, {player}.", when = { foe_hp_below = 25 }, once = "condition" },
		chance = 15,
	},
	winning = { "Your armor is melting, {player}.", once = true, chance = 40 },   -- the list: once a fight
	losing = { { text = "Enough!", once = true, when = { hp_below = 15 } }, chance = 45 },   -- the line: once a fight
	hurt = { "A scratch.", { text = "Poison... in MY veins?", once = true, when = { has = { "poison" } } } },
	status = { sleep = { "Zzz..." } },          -- a status put on it, by key
	death = { "My hoard... my... hoard...", chance = 80 },   -- the victory page shows it
	victory = { "Another bauble for the hoard." },           -- the death page shows it
},
```

- **Moments**: `start` (it appears: the encounter begins, or its wave comes on), `turn`
	(its turn, before it acts; not while a status blocks it), `winning` / `losing` (its
	turn, its share of HP 25 points above / below the player's; tried before `turn`),
	`hurt` (it took damage and lives), `healed`, `status` (by the status's key), `death`,
	`victory` (the player fell).
- **Chance**: a list's `chance` (percent, 0 to 99) is how often the moment speaks; without
	it, the moment's default (`SPEECH_CHANCE` in `content/kinds/monsters.lua`: start 50,
	turn 15, winning and losing 25, hurt 20, healed 30, status 40, death and victory 50).
	`once = true` on a list: it speaks once a fight at most.
- **Lines**: a string (weight 1) or `{ text, weight, when, once }`. When the moment speaks,
	a line is picked by weight among those that may be said now; when none may, it stays
	quiet. The line said last at a moment isn't picked next time when another may be.
	`once = true`: once a fight; `once = "condition"`: once each time its `when` comes
	true (it may come again after the condition no longer held at a moment of its list).
	"{player}" is the player's name, "{name}" the monster's.
- **Conditions** (`when`): a table whose conditions must all hold: `has` / `lacks` (status
	keys the monster has all of / none of), `foe_has` / `foe_lacks` (the player's),
	`hp_below` / `hp_above` (the monster's share of HP, percent: below / at least),
	`foe_hp_below` / `foe_hp_above` (the player's), `from_round`; or a `function(m)` like a
	loadout entry's `when` (`m.hp`, `m:has_status(key)`, `m.target`, `m.round`, ...: see
	[Monsters](#monsters); an error counts as false, logged). Combinations are just more
	keys: `{ has = { "poison", "sleep" }, foe_hp_below = 30 }`.
- **One line a round**: a monster says at most one line a round (the first moment that
	speaks), but its death and its victory may always. What it said and what it may not say
	again is kept in the fight's data (`said_<id>_<moment>`, `once_...`).
- **No dice**: the chance and the pick are hashes of the fight's voice (`f.data.voice`,
	drawn from the clock when the encounter begins), the round, the monster and the moment.
	The fight rolls the same dice with speech or without (`tests/lua/test_round.lua`'s 2.1
	fight and `test_speech.lua` check it), and the form and the live client say the same.
- **Where it shows**: in the round's lines, as "Troll: “Tickles.”" (`.fight-speech`,
	italic; a `speech` event for `fight.js`; in `fights.log` the line starts with
	`speech.MARK`, "\31"). The start comes first on the encounter's page (before an
	ambush); a wave's monsters speak when it comes on. Its death line is also on the
	victory page (`.dk-scene-quote`, `fights.result.said`), its victory line on the death
	page (`.fight-taunt`, `fights.result.taunt`).
- **Hooks**: `fight/round.lua` calls `speech.turn` before an enemy acts (not while a status
	blocks it) and `speech.start` for a new wave; `fight/encounter.lua` the start of an
	encounter; the engine tells it of HP changes and new statuses through
	`engine.listeners` (hurt, healed, death, the player's death: the monster acting has the
	last word, else the first standing).
- **Checked** by `dk check` (`content/kinds/monsters.lua`): known moments, lines of one line
	of text up to 200 characters, weights from 1, `chance` 0 to 99, `once` true (or
	"condition" on a line with a `when`), known conditions with sensible values, and every
	status key it names (a `status` list's, a condition's) a status file (the flat form's
	`speech.statuses`). Speech isn't synced or overridable: it is read from the file when
	the fight runs (`load.module`), so editing it takes effect on the next round.

Adding a monster: copy `app/content/monsters/goblin_shaman.lua` (or an original's file for
one that only attacks) to `<key>.lua`, edit it, run `./dk check`. With `roams = true` (the
default) it is met at random in its level band on the next page load (mind the admin
monsters page's level/map size note); it shows on `/help/monsters`. Deleting the file
retires it.

## Items

Items are content (see [Content](#content)): `app/content/items/<key>.lua`, synced into
`items` (`lib/content/kinds/items.lua`). The original items keep ids 1-33 (keys from the
names: `stick`, `battle_axe`, `destiny_blade`, ...), the original drops are accessories
34-65 (`life_pebble` ... `fortune_drop`), and the Herb, Potion and Ether are 66-68; the
Antidote, the Regen Potion and the Wand 69-71, and the 3.1 items after them (numbered by
the sync, by key). 3.1 added 60: plain steps in the weapon, armor and shield ladders and
pieces with a trade-off (the Warhammer's attack for dexterity, the Glass Blade's for max
HP, the Tower Shield, Ironclad Plate), staves and maces that cast with charges (Spark Rod,
Frost Staff, Ember Staff, Dawn Mace, Storm Lance; the Vigil Cuirass and Ward Shield cast
protection), consumables for every town (Trail Snack, Travel Tea for TP, Sleep Powder, Fire
Flask, Acid Vial, Hi-Potion, Hi-Ether, Elixir, tonics, Cure-All, Weakening Dust, Bitter
Draught, Void Flask), market rings and charms, and drops at every level band (TP pieces,
the four-piece Thornwood set with a cost on each, charms that cast). 3.2 added the gear that
answers the elements and statuses ([Elements and wards](#elements-and-wards)): rings and
charms that resist fire, frost, lightning, shadow or holy (+15% rings, +25% charms), rings
and charms that ward off sleep, poison and venom (25-50%), an armor and a shield that resist
one element and take its opposite badly (Rimefur Coat, Cinder Shield), the Cinder Blade (fire)
and Blessed Mace (holy), and an `element` on the Ember Staff (fire), Frost Staff (frost), Spark
Rod and Storm Lance (lightning); the towns near the monsters they answer sell them, with the
three ward draughts (`seed.sql`, and step 24 of `migrations.lua` for existing databases).

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
	(default true; with a `drop_level`), `icon`, `casts` and `charges` (below), and a
	weapon's `element` (3.2: its attack's, default `"neutral"`; "Deals Fire damage" on its
	lines; see [Elements and wards](#elements-and-wards)).
- **Icons** (schema version 14): `icon = "herb"` names `public/images/items/herb.png`
	(`[a-z0-9_]+`, square; every item has one since 3.1, see [Icons](#icons)).
	Absent or `""`: the Inventory panel keeps the slot's icon, and icon buttons (the shop,
	the fight menu) and the bag grid show `/static/images/skills/default.png` (the spells'
	default). `dk check` fails, naming the item file, when the PNG is missing; an icon deleted
	after the sync falls back at once (`items.icon` checks the file). Overridable in the admin
	panel. Shown in the bag grid on `/inventory` (32px) and before the equipped items' names,
	in the Inventory panel instead of the slot icon, on the shop's buttons and its purchase
	page, in the fight menu's Gear and Items buttons and in item tooltips (`.tip-icon`).
- **Items that cast** (2.4): gear with `casts = "<spell key>"` (a spell usable in fights)
	and `charges = <max>` (1-1000) casts that spell in fights while equipped, a charge
	instead of MP (see [Fight engine](#fight-engine) for the button and its contract). Each
	`user_items` row has its own `charges`: full when obtained (shop, drop, `t_give`; any
	`inventory.add` / `inventory.equip_new`), one spent per cast, 0 refuses. Resting at an inn
	refills the equipped ones (`inventory.recharge`; the inn page lists them, "Your Wand is
	fully charged again."); bag items keep theirs. `rechargeable = false` makes one single
	use: the inn passes it by, and the cast that spends its last charge uses it up (the entry
	is deleted, stats clamped; the round adds "Your Wand is used up."). Lines: "Casts Magic
	Bolt", "3/5 Charges" ("1 Charge"), then "Single use" for one that isn't rechargeable
	(`items.charge_lines`, on `/inventory`, in tooltips, in the shop and on `/help/items`).

```lua
-- app/content/items/wand.lua
return {
	name = "Wand",
	description = "A short rod of polished ash. ...",
	category = "weapon", price = 75, attack = 2,
	casts = "magic_bolt",           -- the spell it casts (app/content/spells/magic_bolt.lua)
	charges = 5,                    -- charges when full
	icon = "wand",                  -- public/images/items/wand.png
}
```
- Validation (`dk check`): gear has `max_stack` 1; only gear has attack, defense,
	modifiers and `casts`; `casts` needs `charges` >= 1 and `charges` (and `rechargeable =
	false`) needs `casts`; the spell
	must exist and be castable in fights; only consumables have `use`/`can_use`, `power`, `messages`, `data`,
	`usable_in` and `target`, and a consumable needs `use`; quest items can't be sellable;
	`sellable = true` needs a price.
- Admins override name, description, price, attack, defense, icon, charges, rechargeable, drop level, sellable,
	droppable, a weapon's element, the modifiers' stats, elements, statuses and amounts (an
	override can add a modifier: both its `modifiers.N.stat` (or `.element`, `.status`) and
	`.amount`) and a consumable's power, numbers and message strings at `/admin/items`.
- Modifier stats: `maxhp`, `maxmp`, `maxtp`, `strength`, `dexterity`, `attack`, `defense`,
	`exp_bonus_pct`, `gold_bonus_pct` (see [Derived stats](#derived-stats)); and (3.2)
	resistances `{ kind = "resist", element = "fire", amount = 25 }` (-100 to 200: "Fire
	Resistance +25%") and wards `{ kind = "ward", status = "sleep", amount = 25 }` (0 to 100,
	a status file's key: "Sleep Ward +25%"), shown after the stats on its lines, in its
	tooltips and in the shop's (`items.affinity_lines`).
- Use: a consumable can be used in town (from `/inventory`) and in fights ("Use Item",
	costs the turn like a spell; `fight/act.lua`) per its `usable_in`, with the player as
	caster. Refusals (already full, ...) and errors cost nothing; the item is taken from
	the bag only when it was used.
- The town page (`home/town.html`) shows the town's places as light cards (3.1:
	`.town-banner`: a faint wash and a hairline that sit in the page, a little stronger when
	pointed at; the picture, `public/images/buildings/`, a 64px round medallion in a thin
	ring; the name in the links' colour, a line under it): the Inn (`/inn`, its price) and the
	Market (`/shop`: the shop and the map store in one, page title "Market").
- Maps (3.1, schema version 18): `town_maps(town_id, map_id)` is the maps a town's market
	sells (`game.town_maps`, `game.sells_map`; the admin town editor's Maps field takes town
	names, its own left out); by default each town sells its neighbours' along the road (the
	towns before and after it by id), so the map to a far town is bought near it. The
	market lists them under Maps (`.market-map`: the price, or, on the player's map already,
	where the town is and its TP); `GET/POST /maps/buy/#id` (`town/maps.lua`, in the
	market's dialog) refuses a map the town doesn't sell; `GET /maps` redirects to the
	market.
- Shops: `town_items(town_id, item_key)` is what a town sells, by item key (schema version
	19; before, by id): a list may name an item the content sync hasn't added yet, and one
	that is gone or retired isn't sold (`items.town`, `items.sold_in` join on the key). The
	admin town editor takes keys (it refuses one no item has: a typo); `seed.sql` lists a
	fresh install's by key, and a migration that adds wares to existing databases names keys
	too (step 19 adds the 3.1 wares and, at last, the Antidote and Regen Potion), so nothing
	depends on the order ids are given in. Any item a town sells can be bought as often as the
	gold and the bag allow (2.4: no more "Already purchased", a copy of the item worn
	included); the server checks that the town sells it, the gold and the bag's room.
	Weapons, armor and shields go into the bag (3.0; what is worn stays) or are worn at
	once, the player's choice: with an old item in the slot it goes into the bag (needs a
	free slot) or is sold back (its value counts toward the price). Everything else goes into the bag (`qty`, up to the room on a stack or
	a new one, and the gold). The Sell section buys any sellable bag item.
- Drops: a victory without a level-up drops an item 1 in 30 times, picked uniformly among
	the non-retired droppable items with `drop_level` at or below the monster's level (the
	original drops' odds). `users.dropcode` holds it until the player takes it, equips it
	or leaves it (moving on drops it too).
- The drop card (3.1, `fight/drop_offer.html`, `routes/fight.lua` `drop_offer`): the
	victory page shows it at once (a level-up's too): the purchase's look (`town.css .buy`:
	the picture and name with its tooltip, its kind; what it changes against the piece worn
	in its slot, or what it gives, or does) and the choices as plain buttons, each with what
	it does beside it (`.drop-why`), `POST /drop`:
	**Equip it** (`equip=<slot>`: into its slot, or an accessory into the first empty
	accessory slot; with all three taken, one choice per slot, "in place of" what is there;
	the piece it replaces goes into the bag, so that needs room: otherwise the choice says
	"No room in your bag for your Club"; equipping into an empty slot needs none), **Put it
	in your bag** (`take`) or, with a full bag, **Make room** (a link, `GET /drop/room`, a dialog:
	the bag but quest items, each with a Discard button that throws the stack away and takes
	the drop, `take` + `discard=<entry>`), and **Leave it** (`leave`). What became of it is
	kept on the victory page (`fights.result.drop_note`: "The Branch is in your bag.") and
	the answer leads back there (`/victory`); a refusal shows on the card. `GET /drop` leads
	to the victory page; without one (its fight gone) the card has a page of its own.
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
| `items.attributes(item)`, `items.special_lines(item)`, `items.affinity_lines(item)`, `items.use_lines(item)`, `items.stat_line(stat, n)` | display lines (`"Attack Power +250"`, `"Gold Bonus +10%"`, `"Deals Fire damage"`, `"Fire Resistance +25%"`, `"Power 30"`) |
| `items.signed(stat, n)`, `items.compare(item, old)`, `items.compare_view(item, old)`, `items.category_label(item)` | `"+5"`, `"+10%"`; wearing `item` instead of `old` stat by stat (`{ stat, label, new, old, delta }`: the shop's tooltips) and as text (the purchase and the drop card); "Weapon", "Consumable" |
| `items.icon(item)`, `items.icon_url(item)` | its picture's URL, or nil / the default icon |
| `items.casts(item)`, `items.spell(item)`, `items.charge_lines(item [, charges])`, `items.rechargeable(item)` | it casts a spell; that spell's row; `{ "Casts Magic Bolt", "3/5 Charges" [, "Single use"] }`; an inn refills it |

Adding an item: copy a file in `app/content/items/` to `<key>.lua`, edit it, run
`./dk check`. The next page load syncs it: give it a `drop_level` for monsters to drop it,
or add its key to a town's shop in the admin town editor. It shows up on `/help/items`.

## Inventory

`user_items(id, user_id, item_id, qty, equipped, charges)`: a stack of one item (`charges`:
an item that casts, see [Items](#items)), equipped in a slot
(`weapon`, `armor`, `shield`, `accessory1`-`accessory3`; one per slot) or in the bag
(`equipped` NULL). `lib/inventory.lua` holds the rules; the pure ones are unit-tested in
`tests/lua/test_inventory.lua`:

- The bag holds `control.inventory_size` stacks (default 12; "Bag Size" in the admin main
	settings). Equipped items don't count, a stack counts once, quest items never count (a
	quest can't be blocked by a full bag). Topping up a stack that isn't full
	(`qty < max_stack`) is always allowed (`inventory.room`).
- Equipping a bag item swaps it with what is in the slot (never needs a free slot);
	an accessory goes into the first empty accessory slot (the page's Equip sends no slot),
	and only with all three taken does the page offer the slots ("Equip in place of:" a
	button per accessory worn, `slot=1-3`). Unequipping needs room in the bag.
	After any equipment change current HP/MP/TP are clamped to the new maxima
	(`inventory.changed`).
- `/inventory` (link in the left nav, and "Bag: n / 12" in the right one) opens with the
	character (3.1, `.inv-sheet`: name, level and class, the HP/MP/TP bars of the Character
	panel, `game.bars`, experience, the next level and gold with their bonuses, from
	`town/character.lua` `character.sheet`; beside it the fighting stats, Attack, Defense,
	Strength, Dexterity, as plain figures; no frame), then shows the slots
	and the bag grid (free slots shown) with equip, unequip, use and discard (confirmation;
	how many for a stack; not quest items). Every action is a POST that renders the page
	with what happened.

| Function | |
|---|---|
| `inventory.entries(uid)`, `inventory.bag(uid)`, `inventory.equipped(uid)` (slot -> entry, cached per request), `inventory.entry(uid, id)`, `inventory.find(uid, item_id)` | entries `{ id, user_id, qty, equipped, item }` |
| `inventory.size()`, `inventory.used(bag)`, `inventory.free(bag, size)`, `inventory.room(item, bag, size)` | the cap |
| `inventory.add(uid, item, qty)`, `inventory.take(entry [, qty])` | into / out of the bag |
| `inventory.full_charges(item)`, `inventory.spend_charge(entry)`, `inventory.recharge(uid)` | an item's charges when obtained; one charge used (true: a single-use item's last, the item is gone); the inn: refill the equipped rechargeable items (returns them) |
| `inventory.equip(uid, entry, slot)`, `inventory.equip_new(uid, item, slot)`, `inventory.unequip(uid, slot)`, `inventory.free_accessory_slot(uid)` | equipment (they clamp) |
| `inventory.stats(user)`, `inventory.names(uid)` | effective stats, equipped names per slot |

## Hotbar

(3.1, `docs/plans/hotbar.md`.) The fight menu is a bar of ten slots on the number keys: **1
Attack**, **9 Guard** (3.2) and **0 Run**, fixed, and **2-8** the player's other fight
actions where they put them (`app/lib/hotbar.lua`, `hotbar.FIRST` and `hotbar.LAST`).

- **Actions** (`hotbar.actions(user)`): the equipped gear that casts (by slot), the fight
	spells known, the fight consumables in the bag (bag order), keyed `spell:<spells id>` or
	`item:<items id>` (gear and consumables are both items; the route tells them apart).
- **The table** `user_hotbar (user_id, kind, ref_id, slot)` (schema version 17) keeps every
	action a character has **met**: on the bar (`slot` 2-8, unique per character) or off it
	(`slot` NULL: taken off, or the bar was full when it came). Attack, Guard and Run aren't
	stored. Schema version 22 moved what sat on 9 (Guard's key since) to the first free key
	of 2-8, or off the bar.
- **The bar** (`hotbar.arrange(user_id, keys)`, keys: the actions at hand in the menu's
	order): the stored slots, then each action **not met yet** in the first free slot (off
	the bar when none is free). It only reads: GET pages show the bar this way without
	writing it ([pure GETs](#routes)).
- **Settling** (`hotbar.settle(user)`, from `encounter.begin`): when a fight begins, the
	actions not met yet are written where `arrange` put them. So the bar is fixed for the
	fight and after: an action never moves unless the player moves it, a new one takes a
	free key at the next fight, and one met while the bar was full stays off it even when a
	key frees later.
- **Not at hand** (a consumable used up, gear not worn, a spell forgotten): its slot
	stays, greyed (`.hotbar-gone`: the picture, its tooltip, and why: "none left", "not worn",
	"not known"); pressing its key does nothing.
- **The fight page** (`templates/fight/fight.html`; `hotbar_view` in `routes/fight.lua`
	builds `bar`, slots 2-8 `{ n, button | gone, why }`, and `more`, the buttons off the bar;
	the template adds 1 Attack, 9 Guard and 0 Run): each
	slot `<li class="hotbar-slot" data-hotkey="<n>">` with `<kbd class="hotkey">` and its
	button (`aria-keyshortcuts="<n>"`); an empty one dashed (`.hotbar-empty`, hidden from
	screen readers). Then `.fight-more` ("More") with the rest, without keys.
- **The keys** (`public/js/hotbar.js`, every page): 1-9 and 0 press the slot's button on a
	page with `form[data-fight]` (a locked turn's Continue for any of them), as a click
	would (the live client sends it, `fight.js` plays the round); not while a field has the
	keyboard (the chat), a modifier is held, a dialog is open, the key repeats or the live
	client is busy; a disabled button (MP short; every button while a round plays) does
	nothing. The script marks `<html class="dk-hotbar-js">`; the key badges and the "(or any
	number key)" hint show only then, since without it the keys do nothing.
- **Arranging** (`GET/POST /hotbar`, linked from the Functions box, `app/town/hotbar.lua`,
	`templates/town/hotbar.html`; not while fighting: `common.not_fighting`): the ten slots, each of 2-8 with its tile and
	a list (`slot2` ... `slot8`: "Empty" and every choice, `hotbar.choices`: the actions at
	hand and those on the bar now); **Save** (`save`) puts the chosen ones on their keys and
	everything else met off the bar (`hotbar.save`; an unknown key is the cheat page, the
	same action in two lists keeps the first); **Reset** (`forget`: not `reset`, which would
	hide the form's `reset()` from the live client) forgets the arrangement
	(`hotbar.reset`): the bar fills again. Both redirect to `/hotbar?saved=1` or
	`?reset=1`. Then "Your actions", each with where it is. With `hotbar.js` the tiles drag
	(HTML drag and drop): onto a slot (its list takes the action; where the action was gets
	the slot's old one: a swap), between slots, or back to the actions (the slot empties),
	then the form saves through the live client, in place (`scene.js` doesn't fade `/hotbar`
	into `/hotbar`). Keyboard and touch use the lists.
- Tests: `tests/e2e/hotbar.sh` (filling, settling, the fight's bar, greyed slots, More,
	saving, refusals, reset, new actions, Guard's fixed key), `tests/e2e/migrate.sh` (steps 17
	and 22),
	`tests/browser/client.js` (a number key plays a round, not while typing; a drag saves).

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
that give expected effective stats), used by the migration. `stats.monster(row, mods)`
applies the same rules to a monster and its equipment (see [Monsters](#monsters)).

Modifiers are gear's passive bonuses, plain data (not code: they are summed, displayed and
overridden): `{ kind = "stat", stat = "strength", amount = 50 }` (amount may be negative),
`{ kind = "resist", element = "fire", amount = 25 }` and `{ kind = "ward", status = "sleep",
amount = 25 }` (3.2, see [Elements and wards](#elements-and-wards); `stats.MODIFIERS`: what
each names and its amount's range), checked by `stats.validate_modifiers(list)`, stored as
text by `stats.encode_modifiers` (`"stat stat=strength amount=50; resist element=fire
amount=25"`, read back by `stats.decode_modifiers`) and summed by `stats.modifiers(list)`
(stats) and `stats.affinities(items)` (`{ resist = { fire = 25 }, ward = { sleep = 25 } }`).
`inventory.stats` adds `resist`, `ward` and `attack_element` (the weapon's element) to the
effective stats, and `stats.player` copies them for the fight.

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
- A post is drawn as a parchment card (`community/news/post.html`, `.news-post`:
	`backgrounds/parchment_tile.jpg` tiled at its size, 800x600, seamless; a thin brown
	edge; the title a link to its page, the date and author under it, the text, the
	discussion's link): on `/news`, `/news/#id` and, with
	`excerpt` (the first paragraph, Read more, All news), in the town's Latest News.
- The forum's look (3.1, `community.css`): over each page a bar (`.forum-bar`) with the
	way back (`Forum › General`, the current place as text) and, on a board that takes
	them, New Thread. The rest is a parchment sheet (`.forum-sheet`, the news posts'
	parchment): the boards and threads as rows (a thread with who started it under its
	title), the columns' names small and light, an engraved line between rows (a dark
	hairline over a light one: `--ink-line`, `--engrave`); a thread's title, then its posts,
	who and when over each; the pages (`.forum-pages`: small raised boxes, the current one
	pressed in, `aria-current="page"`; the news archive's too) and the forms at the foot,
	their fields pressed into the sheet and their buttons (`.forum-button`) raised.
- A news post and a forum reply also send live notices (see [Notices](#notices)).
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
	 `tests/fixtures/schema_v0.sql` (version 0) to `schema_v9.sql` (version 9),
	 `schema_v11.sql` to `schema_v14.sql`, `schema_v21.sql` and `schema_v22.sql` with the game
	 data of that time (`seed_v3.sql` to `seed_v9.sql`, `seed_v11.sql` to `seed_v14.sql`,
	 `seed_v21.sql`, also version 22's), migrates them, checks the data and compares
	 the column, foreign key and index layout with a fresh install. Never edit the
	 fixtures; add a `schema_vN.sql` copy of the old schema when a test needs to start
	 from version N.

## Roles

An account's role is `users.authlevel` (`app/lib/roles.lua` names them): **0** a player,
**1** an administrator (the control panel, the admin event channel, News threads, and
everything a moderator may), **2** blocked (can't play: `auth.game`), **3** a moderator (3.1:
deletes Babble Box messages; no control panel). `roles.name(level)` ("player", "admin",
"blocked", "moderator"), `roles.is_admin(user)`, `roles.can_moderate(user)` (administrators
and moderators), `roles.is_blocked(user)`; every check goes through them. Administrators
set roles in the user editor (`roles.CHOICES`: User, Moderator, Admin, Blocked); `dk user
admin <name>` makes an administrator. The chat draws administrators' messages gold and
moderators' green ([Chat](#chat)).

## Sessions, CSRF, accounts

- `lib/session.lua`: `session.create(req, user_id, remember)`, `session.destroy(req)`
	(also publishes `logout` for the session's pages), `session.destroy_user(user_id)`,
	`session.publish_logout(user_id [, s])` (`logout` for one session's pages or all),
	`session.live_id(s)`. The cookie `dk_session` holds 32 random bytes as hex
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
| `expect_row text` | `expect_body` on the body without its lore divs (`.help-lore`: the help pages' rows) |
| `expect_text text`, `t_text` | the body's text without tags and tooltip templates (a sentence with an item name that has a tooltip); entities stay |
| `t_ok` / `t_fail msg` | custom assertions |
| `t_sql "SQL"` | run SQL on the test DB (sqlite3 or python3); `t_has_sql` |
| `t_register user pass email charname [class]`, `t_login user pass [remember]`, `t_logout` | account shortcuts |
| `t_spells username "1,6"`, `$T_KNOWN` | set the spells a user knows; SQL expression for a users row's known spell ids (`SELECT $T_KNOWN FROM users ...` → `1,6`) |
| `t_give username key [qty [slot]]`, `t_items_clear username`, `$T_ITEMS` | give an item (into the bag, or equipped in `slot`; an item that casts with full charges); take all away; SQL expression for a users row's items (`stick@weapon,herbx3`) |
| `t_fight username monster_id hp [round]`, `t_fight_new username`, `t_fight_win`, `t_fight_clear username`, `t_fight_status username who key [data [ticks]]` | a fight in progress against a monster (round 2 by default; not on the clock yet: its first POST or tick starts it at its time); an encounter beginning where the player stands, as on a map move (the current jar's player: `POST /__test/encounter`; `$BODY` is the fight page); the current jar's won fight (`t_fight user m 0`) paid by a round, `$BODY` the victory page; no fight; a status on the player (who 1) or the monster (2), data like `'chance=i:5'` |
| `t_tick [seconds]` | the clock moves on (default 10 s: a tick; `$T_NOW` too, until the next script) and the server's tick runs there (`POST /__test/tick`, the current jar logged in; the e2e server's own tick is off: `tick = false`); `$BODY` says what it advanced |
| `t_calm username`, `$T_CALM_LAT`, `$T_CALM_LON` | put the player at the calm place (-3, 3): the Midlands' plain (no terrain field), and the weather brings no [field](#fields) to it from `$T_START` until nightfall 1400 s later (`tests/lua/test_fields.lua` checks it), and it has Midworld's level band and no town. A check of a fight's numbers (damage, healing, a status's data or duration, an attack that never lands) fights there, so the battlefield is the same, none, on every run: the weather is a pure function of the place and the pinned time, and elsewhere it may bring the sun (fire +10%), fog (attack -15%) or mud (dexterity -20%). The weather's fields have tests of their own (`tests/e2e/fields.sh`) |
| `$T_ROUND`, `$T_MONSTER`, `$T_MONSTER_HP`, `$T_SLEEP`, `$T_UBER_DAMAGE`, `$T_UBER_DEFENSE`, `$T_STATUSES`, `$T_WORLD` | SQL expressions for a users row's fight in progress (0 when there is none; a finished fight kept for its page doesn't count) and statuses (`player:regen/4,enemy:sleep`; world statuses `regen/9`) |
| `t_stats`, `expect_stats "maxhp maxmp maxtp str dex atk def" label` | the logged-in character's effective stats from `/character` |
| `t_mail_latest`, `t_mail_count` | outbox |
| `t_wait_for path text` | poll up to 5 s (hot reload) |
| `t_fetch path 'a=1' [curl args]` | POST like live.js (the chat): `Accept: application/json`, the CSRF token (from the page's `data-csrf`) in `X-CSRF-Token` |
| `t_live GET\|POST path ['a=1'] [curl args]`, `t_live_page`, `t_live_forget`, `w_ops`, `w_payload op [arg]`, `w_has op [arg]`, `w_lacks op [arg]` | a live request like the live client's (python3; `X-DK-Live`, `X-DK-Have` from the jar's hash map, which the answer's `hashes` frame updates); take the map from the last full page / start empty; the answer's frames (`op args length` lines), a frame's payload, assertions |
| `live_open name [curl args]`, `live_close name`, `live_stop` | `GET /live` in the background with the current jar (to `$T/live.<name>`); end one / all |
| `live_has name text`, `live_lacks name text`, `live_wait name text [tries]`, `live_count name text` | the stream has (waits up to 3 s) / hasn't the text; how many lines have it |
| `live_publish channel event data`, `live_frames_ok name` | `POST /__test/publish`; the stream is well-formed (retry, id/event/data blocks, comments) |
| `$T_NOW`, `$T_START` | the time every request pins the game's clock at (`X-Test-Now`, see [Clock and weather](#clock-and-weather)); `T_NOW=<unix> t_get /` for another; every script starts at `$T_START` (4000000000) |
| `$BASE`, `$T` (temp dir), `$CONFIG`, `$OUTBOX`, `$ADMIN_USER`, `$ADMIN_PASS`, `$BIN`, `$ROOT` | the server log is `$T/server.log` (one access line per request) |

Lua unit tests: put `tests/lua/test_<name>.lua` returning `{ name = function() assert(...) end }`.
`run.sh` runs them inside a dk VM, where they can `require("lib.php")` and friends.

`tests/lua/test_patterns.lua` is the contract for the monsters' fight patterns
([Monsters](#monsters)): every monster that isn't retired fights 40 seeded states through
`round.play` and `round.advance` (the player's level and stats around the monster's, both
sides' HP, its MP, stock, `m.turn` and the round, statuses on either side, an ally, and no
field or each field as the world's and as a spell's). Its conditions and actions must log no
warnings, HP and MP stay whole numbers and MP never goes below 0; and every loadout entry
of weight > 0, its class's too, must be eligible (weighed by `fight/ai.lua` with
`fight/monster.lua`) in at least one state (up to 1,000 states). A failure names the
monster, the entry, its `when` as written and how often the condition passed, the MP was
there and `can_cast` / `can_use` allowed it.

JavaScript unit tests: `tests/js/test_<name>.js` tests the pure functions of
`public/js/<name>.js` (which exports them through `module.exports` when there is no DOM).
`run.sh` feeds the two files on stdin to `node` (or Windows' `node.exe` under WSL; `NODE=`
picks one) and skips them when there is none.

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
./dk stats   --config /tmp/dk-dev/config.lua         # metrics of the running server
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
