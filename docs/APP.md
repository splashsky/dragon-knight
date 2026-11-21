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
| Live pages: chat, who's online, notices, broadcast banner | `app/lib/{chat,presence,notices,banner}.lua`, `app/town/babble.lua`, `app/routes/live.lua`, `app/admin/broadcast.lua` | `templates/layout/{chat,chat_posts,online,online_list,side_live,banner,live_attrs}.html`, `templates/town/babble.html`, `templates/admin/broadcast.html`, `public/js/live.js` | `tests/e2e/{chat,presence,notices}.sh`, `tests/lua/test_chat.lua` |
| Tooltips, lore | `app/lib/tips.lua`, `app/lib/view.lua` (`tip`, `paragraphs`), the kinds' `lore` field (`app/lib/content/schema.lua`) | `templates/tip/tip.html`, `public/js/tooltip.js`, `public/css/dk.css` (`.dk-tip`, `.tip-*`) | `tests/e2e/tips.sh`, `tests/js/test_tooltip.js`, `tests/lua/test_content.lua` |
| Themes, font | `app/lib/themes.lua`, `app/routes/theme.lua` | `templates/layout/{head,logo,theme_picker}.html`, `public/css/themes/*.css`, `public/images/themes/*`, `public/fonts/vollkorn/*` | `tests/e2e/theme.sh` |
| Accounts | `app/routes/auth.lua`, `app/lib/{auth,session,csrf,mail}.lua` | `templates/auth/*` | `tests/run.sh` |
| Home (town / exploring view) | `app/routes/home.lua` | `templates/home/*` | `tests/run.sh` |
| Town, shop, explore, heal, character, map | `app/routes/town.lua`, `app/town/*` | `templates/town/*`, `public/css/town.css` | `tests/e2e/town.sh` |
| Items, inventory, derived stats | `app/content/items/*.lua`, `app/lib/{items,inventory,stats}.lua`, `app/town/{inventory,shop,inn}.lua`, `app/admin/items.lua` | `templates/town/{inventory,inventory_discard,shop,shop_buy,inn}.html`, `templates/fight/drop*.html`, `templates/admin/item{,s}.html`, `public/images/items/*` | `tests/e2e/{inventory,town,fight,wand}.sh`, `tests/lua/test_{items,stats,inventory}.lua` |
| Fight, victory, drops | `app/routes/fight.lua`, `app/fight/{combat,act,encounter}.lua`, `app/lib/leveling.lua` | `templates/fight/*`, `public/css/fight.css` | `tests/e2e/fight.sh`, `tests/lua/test_{fight,leveling}.lua` |
| Hotbar (the fight's number keys) | `app/lib/hotbar.lua`, `app/town/hotbar.lua`, `app/routes/fight.lua` (`hotbar_view`), `app/fight/encounter.lua` (settling) | `templates/fight/{fight,action}.html`, `templates/town/hotbar.html`, `public/js/hotbar.js`, `public/css/{fight,town}.css` | `tests/e2e/hotbar.sh`, `tests/e2e/browser.sh` |
| Smooth fights (fight events) | `app/fight/events.lua`, `app/routes/fight.lua` | `templates/fight/*`, `public/js/fight.js`, `public/css/fight.css` | `tests/e2e/fight_api.sh`, `tests/lua/test_round.lua`, `tests/e2e/browser.sh` |
| Fight engine (round pipeline, statuses, summons, AI, world statuses) | `app/fight/{state,engine,round,ai,act}.lua`, `app/lib/{statuses,summons,world}.lua`, `app/content/{statuses,summons}/*.lua`, `app/admin/effects.lua` | `templates/fight/{fight,statuses}.html`, `templates/admin/{effects,effect}.html` | `tests/lua/test_round.lua` (+ `fight_original.lua`, `fight_model.lua`, `spells_original.lua`), `tests/e2e/effects.sh` |
| Monsters (content with MP, equipment, items, spells) | `app/content/monsters/*.lua`, `app/lib/content/kinds/monsters.lua`, `app/lib/monsters.lua`, `app/fight/monster.lua`, `app/admin/effects.lua`, `app/community/help.lua` | `templates/community/help/monsters.html`, `templates/admin/{effects,effect}.html` | `tests/lua/test_monsters.lua`, `tests/e2e/monsters.sh` |
| Content (statuses, summons, classes, spells, items, monsters) | `app/content/{statuses,summons,classes,spells,items,monsters}/*.lua`, `app/lib/content/*`, `app/lib/{classes,spells,items,statuses,summons,monsters}.lua`, `app/cli/{content,check}.lua`, `app/admin/{classes,spells,items,effects,content}.lua` | `templates/admin/{class,classes,spell,spells,item,items,effect,effects,content_form,content_status}.html` | `tests/e2e/content.sh`, `tests/lua/test_{content,items}.lua` |
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
	 runs before any guard or handler.
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
| `auth.game` | legacy index.php chain: not logged in → `/login`; `control.gameopen == 0` → "Game Closed" page; `verifyemail == 1` and not verified → `/verify`; `authlevel == 2` → 403 blocked page |
| `auth.admin` | not logged in → `/login`; `authlevel ~= 1` → 403 |

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
| `view.chat(req, large)` / `view.online()` | ctx for `layout/chat.html` / `layout/online.html`, or nil when the Babble Box / Who's Online is turned off |
| `view.render(name, ctx, req)` | a rendered template string (a partial for JSON; mind region markers: `wire.strip`) |
| `view.layout(req, title, html, opts)` | wraps already-rendered HTML |

`opts`:

- `nav`: show the side columns and the logged-in top nav. Defaults to true when logged
	in. Legacy pages called with `display(..., false, false, false)` pass `nav = false`.
- `layout`: `"main"` (default) or `"minimal"`. Use `"minimal"` for popup pages
	(`/character`, `/map`). Any other name uses
	`templates/layout/<name>.html` (the admin panel uses `layout = "admin"`).
- `body_class`: extra class(es) on `<body>` for page-specific CSS (the layouts also add
	`theme-<key>`, see [Themes](#themes)). The help pages pass
	`{ layout = "minimal", nav = false, body_class = "help" }` for a full-width minimal
	page (`body.minimal.help` in `community.css`).
- `chat_inline`: the page shows the Babble Box itself (town page, `/babble`), so the
	right column doesn't.
- `status`: the HTTP status.
- `headers`: extra `{name, value}` pairs.

The layout re-reads `req.user` from the DB before drawing the nav, so stats changed by
the handler show up straight away (legacy `display()` did the same). A handler that renders
stats itself after changing them reads the row again (`game.user(id)`).

Layout ctx, if you write your own layout: `title`, `content` (HTML), `body_class`,
`theme` (the request's theme, see [Themes](#themes)), `gamename`, `nav` (table or nil),
`logged_in`, `version`, `build`, `elapsed()`, `queries()`, `banner` (the broadcast banner
or nil), `back` (`view.back_path`), `live` (logged in, not minimal: the page loads
live.js), `side` (with `nav`: the online count and the Babble Box for the right column,
`layout/side_live.html`). `layout/head.html` loads every script on every page (`dk.js`,
`tooltip.js`, see [Tooltips](#tooltips), `modal.js`, see [Modals](#modals), `client.js`,
`scene.js`, see [Scenes](#scenes),
`live.js`, `fight.js`, `hotbar.js`, see [Hotbar](#hotbar)): the head is the same
everywhere, so the live client never loads a page again for its scripts. The main layout marks the parts a script may
swap: `<aside class="dk-left" data-nav-left>`, `<main class="dk-middle" data-main>` and
`<div class="dk-nav-right" data-nav-right>` around `layout/nav_right` (not the whole right
column: the chat below it keeps its scroll position and typed text). Include `{{{ include("layout/head") }}}` in `<head>` to get the
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
`banner`, `left` (`loc`, `towns`, `functions`), `main`, `right` (`charpanel`, `invpanel`,
`spellpanel`, `online-count`, `chat` with `chat-posts` and `chat-form` with `chat-back`),
`foot` (with `foot-time`, the timing line), `themes` (with `theme-back`); `minimal` and
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
	`target`, `download` or `data-popup`, not another `#hash` of the same page, not
	`/static/` or `/live`) and submits of same-origin urlencoded forms (the pressed button
	included). `data-native` on a link, a form or an ancestor keeps it native. Its click and
	submit listeners are on `window`: the other scripts' (on `document`) come first, and a
	form one of them handles itself (`preventDefault`: the chat) is left alone.
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
	(by name) is the page's own element, moved and morphed (the chat panel moving from the
	town page's middle column to the right one keeps its scroll and typed text). Regions
	taken out while an answer applies are kept aside until it is done, for a later region of
	the same answer. It never removes elements marked `data-client` (the tooltip box, the
	toasts, the progress bar, the announcer: give anything a script adds to the page that
	attribute), never touches the live value of a control (typed text survives; only the
	form `reset()` above), and leaves `open` on `<details>` and tooltip.js's
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
stream starting and stopping), links, back/forward with their scroll, typed text and a
folded chat kept, the chat, a move, a POST's own page (resting at the inn), the progress bar, a newer link
winning, the minimal layout, a broken page loaded natively. `GET /__test/slow?ms=N` (test
routes only) is a page that takes its time.

## Scenes

The live client changes pages smoothly (`public/js/scene.js`). Any action of the player's
that changes the middle column (a link or form: the inn and resting there, the shop and
selling, the map store and buying a map, the inventory, ...) fades it out (0.15 s, in the
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
	live client's morph leaves it alone) and opened with `showModal()`: the page behind is
	inert and dimmed, Escape closes it, focus stays inside. Its first field or button gets
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
route runs: `tests/e2e/fight_api.sh` plays a round twice with the same dice); `tests/e2e/live.sh` reads streams with `curl -N` (the `live_*` helpers
of `tests/run.sh`, see [End-to-end tests](#end-to-end-tests)).

### Events

What the game publishes (data is JSON; event names are unique across channels, because
the browser sees only the name):

| Channel | Event | Data | Published by |
|---|---|---|---|
| `babble` | `babble` | `{ id, author, text, time, when, delete }` (a new chat message; `time`: unix seconds, `when`: as the page shows it, `delete`: the address administrators delete it with) | `POST /babble` (`chat.post`) |
| `babble` | `delete` | `{ id }` | `POST /babble/#id/delete` (administrators) |
| `presence` | `join` | `{ id, name, url, online }` (`url`: the character page; `online`: how many are online now) | a player's first request while not online (`session.load`) |
| `presence` | `leave` | `{ id, name, url, online }` | the presence sweep |
| `notices` | `news` | `{ id, title, author, url }` | a news post (`/admin/news`) |
| `notices` | `banner` | `{ id, text, expires, ttl }` (`expires`, `ttl`: unix time and seconds left, absent without an expiry) | `/admin/broadcast` (set) |
| `notices` | `clear` | `{ id }` | `/admin/broadcast` (clear) |
| `user:<id>` | `reply` | `{ thread, title, author, url }` | a reply in a forum thread the player started or posted in (not to the one replying; at most 200 players) |
| `user:<id>` | `logout` | `{ session }` (one session's pages) or `{ all = true }` | logout; password change, lost password, a new password set in the user editor |
| `user:<id>` | `stale` | `{ tab }` (the sending page's `X-DK-Tab`, or `""`) | every successful POST of the player (`main.lua`), but those that set `req.quiet` (the chat's, the banner's dismissal): their other pages ask for themselves again |
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
	again (also after more than a minute hidden, whatever happened).

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

The Babble Box (`lib/chat.lua`, routes in `town/babble.lua`, `layout/chat.html`): a
`<details>` panel (folding it is remembered by live.js in `localStorage`) in the right
column of every in-game page, and larger in the middle of the town page and of `/babble`
(its own page; old links to the iframe land there). `control.showbabble` turns it off
everywhere.

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
- `POST /babble/#id/delete` (administrators; the button shows for them): deletes the
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
- Popups: `<a href="/character" target="_blank" data-popup="250x600">` (`dk.js` opens a
	sized window; without JS it's a normal link).
- The compass (`layout/nav_left.html`): the original's picture (`public/images/compass.png`,
	its four pieces joined) with a submit button over each quarter (`.compass-rose`: the
	triangles between the diagonals, `clip-path`, lit within the parchment by a `mask`),
	named `north`, `west`, `east`, `south` like the old text buttons, so `POST /move` reads
	them as before. `dk.js` presses them for the arrow keys (not while a field has the
	keyboard or a modifier is held; a held key walks on only while the live client is free).
- Item and skill tiles (`dk.css` "frames"): a gradient frame drawn as a background layer
	under the tile, through a 2px transparent border, bright at the top to dark at the
	bottom: gold (`--frame-gold`, lit on hover) for spells, items and gear, steel for the
	fight's Attack and Run (`.action-btn`), crimson for quest items in the bag; the tile
	itself is `--icon-bg`, a fine grain (`--icon-noise`: an SVG noise filter in a `data:`
	URL, no image file) over a warm off-white a little darker at the edges
	(`--icon-ground`, radial), which item pictures without a ground of their own sit on
	everywhere (the bag, lists, the Inventory panel, tooltips, the purchase dialog). The
	bag's cards are light (`--tile`) in a thin gold frame. Retro sets the frames to plain
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
- Images: `/static/images/<file>`. A link-styled submit button:
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
	characters), else to `/`. An unknown key is a 400 page and changes nothing. Popups
	(minimal layout) have no selector but use the theme. No database: the
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
level, description, lore) and the class names on the registration page (starting HP/MP, the
description's points, lore). Names that aren't links get `class="tip-term" tabindex="0"`.

## Lore

`lore` is an optional content field of every kind (classes, spells, items, monsters,
statuses, summons): story text, up to 2,000 characters (`schema.LORE_MAX`), several lines,
a blank line between paragraphs (the lines of a paragraph are joined, so files may wrap
it). Synced into the kinds' `lore` columns (schema version 13), overridable in the admin
panel (a textarea on every content admin page), escaped wherever it shows
(`paragraphs(text)`): in the tooltips (`.tip-lore`) and on the help pages under each entry
(`.help-lore`: classes on `/help`, spells, statuses and allies on `/help/spells`, items on
`/help/items`, monsters on `/help/monsters`). Empty lore shows nothing. The Mage, Warrior,
Paladin, Heal, Magic Bolt, the Herb, the Wand and the Blue Slime have some to begin with:

```lua
-- app/content/spells/heal.lua (excerpt)
	lore = [[
The first word every young Mage learns, and the last one a wise one forgets. Spoken
softly over a wound, it draws warmth back into tired flesh. Old soldiers say a Heal cast
in time is worth a hundred herbs.]],
```

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

## Content

Classes, spells, items, statuses, summons and monsters are **content**: Lua files in git,
one per entity, hot-reloaded like the code and synced into the database, where players' rows
reference them by id. Spells, consumables, statuses and summons also carry code: what they
do (see [Scripting spells and items](#scripting-spells-and-items) and
[Fight engine](#fight-engine)); monsters may carry conditions (see [Monsters](#monsters)).

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
	admin overrides. Kinds sync in `schema.KINDS` order (statuses, summons, spells,
	classes, items, monsters: kinds others reference first; spells before classes, whose
	`class_spells` rows need the spell ids, items and spells before monsters). The original
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
	`/admin/spells/#id`, `/admin/items/#id`, `/admin/{statuses,summons,monsters}/#id`,
	shared code in `admin/content.lua` and `templates/admin/content_form.html`) write them
	for the kind's `admin_fields` (every kind: lore; classes: name, description, sort, playable, starting
	stats; spells: name, description, MP, power, icon, numbers and message strings; items: see
	[Items](#items); monsters: see [Monsters](#monsters); a value equal to the file's
	deletes the override) and offer "reset to file". Field names are those of the
	flat form: `name`, `levels.17.hp`, `levels.17.spells` (`"heal,hurt"`), `power`,
	`data.min`, `messages.hit`, `messages.enemy.hit`, `modifiers.2.stat`.
- **Migrations into content**: a migration that turns old rows into content writes the
	old values into `content_adopt(kind, key, field, value)`; the next sync turns those
	that differ from the file (and are valid) into overrides (that is how schema version 4
	kept edited class names and levels data, version 5 edited spell names, MP and amounts,
	version 6 edited items and drops, version 7 turned edited effect amounts into
	`power`, and version 9 kept edited monster stats).

Adding a class: copy `app/content/classes/mage.lua` to `app/content/classes/<key>.lua`,
edit it, run `./dk check`; the class shows up on the registration page on the next page
load. Deleting the file retires the class. Adding a kind: a `kinds/<kind>.lua` module
(`fields` with types, `field(name)`, `admin_fields(flat)`, optional
`validate_extra`/`write_children`), its table (`id`, `key` UNIQUE, the field columns,
`retired`) and an entry in `schema.KINDS` (in sync order: kinds others reference first).
A field of type `keys` with `refs = "<kind>"` lists keys of another kind (type `key`: one
key or `""`, an item's `casts`; both checked by `load.all`); `write_children` maps them to ids; an optional `validate_refs(flat, all,
err)` checks more against the other kinds' files (a monster's weapon must be a weapon). A kind with code uses
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
	overridable in the admin panel, which shows the current icon. Heal and Magic Bolt have one so far.
	**Adding an icon**: put `<name>.png` in `public/images/skills/` (square; shown at 44px in
	fights and 34px in Fast Spells, scaled by CSS), set `icon = "<name>"` in the spell file
	and run `./dk check`. The two current PNGs are 256×256 (120–165 KB); smaller files
	(88×88 for 2× screens) would load faster.
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
	with power 4 (3-4 damage), none to monsters immune to hurt spells; the Wand casts it.
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

**Combatants** (`s.caster`, `s.target`; the player, monsters and summons alike) have
read-only fields `id` (the combatant's number in the fight), `side` (`"player"`, `"ally"`,
`"enemy"`), `name`, `is_player`, `level`, `hp`, `maxhp`, `mp`, `maxmp`, `tp`, `maxtp`,
`attack`, `defense`, `strength`, `dexterity`, `immune` (0, 1: hurt spells, 2: hurt and
sleep), and, from its statuses, `asleep`, `sleep_chance`, `uber_damage`, `uber_defense`;
and methods:

| | |
|---|---|
| `:heal(stat, n)` | restores up to `n` of `"hp"`, `"mp"` or `"tp"`, never above the maximum (and never lowering a value above it); returns what it restored |
| `:hurt(n)` | takes `n` HP (may go below 0; the fight decides who died); returns `n` |
| `:spend(stat, n)` | uses up `n` of a stat (a cost) |
| `:buff(kind, pct)` | `"damage"`: +pct% damage dealt, `"defense"`: -pct% damage taken, until the end of the fight (the statuses `uber_damage` / `uber_defense`; 0 ends it) |
| `:sleep(chance)` | asleep (the status `sleep`); stays asleep while `rand(1, 15) <= chance` at the start of each of its turns (0 wakes it) |
| `:afflict(key, params)` | applies the status `key` (see [Fight engine](#fight-engine)); `params`: names and plain values (`turns`: how long; the rest is the status's `t.data`); replaces an instance it has |
| `:cure(key or kind)` | removes a status, or all of a kind (`"harmful"`, `"helpful"`, `"neutral"`); returns how many |
| `:has_status(key)`, `:status(key)`, `:statuses([kind])` | what it has: `{ key, name, kind, turns_left, data }` copies |

Amounts are whole numbers >= 0; anything else is an error. The handle's numbers follow its
own changes during the action (heal, then read `hp`).

**Running an action** (`action.perform`): the framework checks the place (`usable_in`,
retired; the caller's message), runs `can_cast`/`can_use` (which may only decide: changing
anything there is an error), then `cast`/`use`, then deducts a spell's MP from the caster.
Nothing touches the game state meanwhile: the handles record an ordered list of events
(`heal`, `hurt`, `spend`, `buff`, `sleep`, `afflict`, `cure`, `summon`, `say`), and the
caller applies them (`fight/engine.lua` `engine.apply` on the fight model; outside fights
`lib/world.lua`) and saves. A refusal, or an error, returns no events, so nothing changes
and no MP, item or turn is spent. In fights the player's action is step 2 of the round
pipeline (`fight/act.lua` `act.run(f, action)`, see [Fight engine](#fight-engine)); town
casting (`town/heal.lua`) and the inventory's Use (`town/inventory.lua`) call
`action.perform` and `world.apply`.

More context methods: `s:summon(key, params)` (an ally joins, in fights; `s.summon_room`
says how many more may), `s:charge(turns, step)` and `s:recharge(turns)` (multi-stage
actions), and the file's `stages = { release = fn }` (named steps; see
[Fight engine](#fight-engine)).

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
the player's choice (known spell, MP, item in the bag) and saves.

**The fight menu** (`templates/fight/fight.html`, one form posting to `/fight`) is the
**hotbar** (3.1, see [Hotbar](#hotbar)): ten slots on the number keys, each an icon button
(`.action-btn`, `.spell-btn`, styled in `dk.css` and the themes; the slots in `fight.css`):
**1 Attack** `<button type="submit" name="fight" value="Fight" aria-label="Attack"
aria-keyshortcuts="1">` with `images/skills/attack.png`, **2-9** the player's actions, and
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
field is there (`form.fight`, `form.run`), so `fight=Fight` and `run=Run` (the text buttons
before 2.4, old forms, tests) and whatever value a button sends play the same. Each button
sits in a span carrying its tooltip (`.action-tip`, `.spell-tip`; `tips.attack(power,
weapon)`: "Attack", the player's attack power and weapon, what it does; `tips.run()`), as
fight.js disables the buttons while a round plays. A turn a status blocks shows only the
"Continue" text button (`continue=Continue`; any command is a Continue then), which any
number key presses.
**The model** (`fight/state.lua`; tables `fights`, `fight_combatants`, `fight_statuses`):

| | |
|---|---|
| `f` | `{ user_id, round, wave, data, st, in_fight, combatants, next_id, outcome, log, result }`. `round` counts the rounds played (the encounter's first strike is round 1, so the first form carries 2; no cap, unlike the original's 255); `st` is `game.player(user)` (the player's HP/MP/TP stay in `users`); `outcome`: `""` in progress, `"victory"` or `"death"` for a finished fight kept for its page; `log`: the last round's lines (`encounter.log_of`, `encounter.lines`); `result`: a victory's rewards |
| combatant `c` | `{ id, side = "player" \| "ally" \| "enemy", kind = "player" \| "monster" \| "summon", entity_id, wave, hp, maxhp, mp, maxmp, turns_left, data, row, statuses }`, numbered from 1 per fight (the player is 1); `row` is the summons row, or the monsters row with its equipment counted (`monsters.effective`); `mp`/`maxmp`: a monster's MP; `data`: a monster's `immune` and item stock (`stock_<position>`) |
| status instance | `{ status_id, key, row, turns_left, data, applied_round, source }`: `data` holds the params it was applied with, `source` the combatant who applied it |

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

**The round** (`round.play(f, a)`; `a.kind`: `attack`, `spell`, `item`, `gear`, `run`, `continue`,
or `ambush`: the monster swung first):

1. the player's turn starts: statuses with `tick_on = "turn_start"` tick; a status that
	 blocks the action makes the turn a skip (with its `blocked` message);
2. the player's action. A refused spell or item (or one whose code fails) leaves the fight
	 exactly as it was: the round runs on a copy (`state.copy`), so even the turn-start
	 ticks are undone;
3. each ally (summon), in the order summoned: turn-start ticks, then its `act` unless
	 blocked;
4. each enemy of the current wave: turn-start ticks (the monster's sleep is a status: its
	 wake-up roll), then, unless blocked, an action and a target chosen by `fight/ai.lua`;
5. turn ends for the player, the allies and the enemies: `turn_end` ticks, then the
	 statuses count down and expire; allies count their rounds down and leave.

After each step that changed HP the round checks the outcome: the player dead is the
death (as before), the last enemy defeated the victory, an ally at 0 HP leaves ("Your Wolf
has been defeated.", or its `on_death`). The result `r` has the lines of each part
(`player`, `allies`, `enemies`, `ending`; the fight page shows them in that order), the
model after the round (`r.f`) and `escaped`, `victory`, `died` or `refused`.
`round.start(f)` rolls a new encounter (each enemy's HP, then who swings first).
`round.locked(f)`: the player has a blocking status, so the page offers only "Continue"
and the route turns any command into `continue`.

**The trace.** With `f.trace = {}` set on the model before `round.play` (the JSON fight
API does), the round records in `r.f.trace`, in order, every line it says, every change
of HP, MP or TP, every status applied, counted down, expiring or removed and every ally
joining, counting down or leaving, each with its step (`f.doing`: who acts and how, set by
`engine.doing(f, c, kind)` / `engine.done(f, prev)` around the code that acts). Lines go
through `engine.say(f, line)`. Tracing rolls nothing and changes nothing (the equivalence
test below traces every other fight); `fight/events.lua` turns it into the API's events.

**Equivalence.** Fights without summons or new statuses roll exactly the original's dice,
in the same order, with the same messages and results: no AI roll with one action and one
target, sleep and the damage/defense buffs as statuses with the original formulas.
`tests/lua/test_round.lua` plays 1,000 seeded fights through the pipeline and through a
frozen copy of the 2.1 fight (`tests/lua/fight_original.lua`) and compares every roll,
line and state.

### Statuses

A status (`app/content/statuses/<key>.lua`, table `statuses`) is a named, timed effect on
a combatant: poison, a buff, sleep, "recharging".

```lua
-- app/content/statuses/poison.lua
local function tick(t)                       -- t: the status context
	local damage = t:roll(t.data.min, t.data.max)
	t.bearer:hurt(damage)
	if t.bearer.is_player then t:say("hurt_you", damage) else t:say("hurt", t.bearer.name, damage) end
end

return {
	name = "Poisoned",
	description = "Loses hit points at the end of every turn.",
	kind = "harmful",            -- harmful | helpful | neutral (an antidote cures "harmful")
	tick_on = "turn_end",        -- turn_start | turn_end: when on_tick runs
	turns = 3,                   -- default duration (0: until removed or the fight ends)
	data = { min = 2, max = 5 }, -- defaults of t.data (admin-overridable)
	messages = { hurt = "The %s takes %d poison damage.", hurt_you = "You take %d poison damage." },
	on_tick = tick,              -- or inline: on_tick = function(t) ... end
}
```

- Fields: `name`, `description`, `kind`, `tick_on`, `scope` (`"fight"`, the default: ends
	with the fight; `"world"`: outside fights only; `"both"`), `turns`, `blocks_action`
	(`true`, or a `function(t)` returning true while it blocks), `data`, `messages`
	(`blocked`: said when it blocks the player's turn; `blocked_other`: anyone else's, `%s`
	the name). Hooks, all optional: `on_apply(t)`, `on_tick(t)`, `on_expire(t)` (ran out),
	`on_remove(t)` (cured or replaced), `modify_damage_dealt(t, damage)` and
	`modify_damage_taken(t, damage)` (return the new damage, a whole number >= 0; they only
	decide, like `can_cast`).
- The context `t`: `t.bearer` and `t.source` (handles; `source` may be nil),
	`t.turns_left` (nil: no limit), `t.data` (the status's data under the params it was
	applied with), `t.name`, `t.messages`, `t.round`, `t.in_fight`, `t:roll`, `t:say`,
	`t:expire()` / `t:remove()` (end it, once the hook returns), `t:release()` (charging:
	run the charged action's stage).
- Applying: `s.target:afflict("poison", { turns = 2, min = 1, max = 3 })` from any
	context. **Re-applying replaces** the instance: the old one's `on_remove` runs (not
	`on_expire`), then the new one's `on_apply`, with the new duration and params even when
	shorter; there is no stacking.
- Timing: a status counts the bearer's turns that begin after it was applied (a poison the
	player casts ticks at the end of the monster's turn in the same round; a regen the
	player casts on itself first ticks in the next round). It counts down at the end of the
	bearer's turn and expires at 0.
- The original mechanics are statuses 1-3: `sleep` (blocks; at the start of each turn
	`rand(1, 15) > chance` wakes it: "The monster has woken up."), `uber_damage` and
	`uber_defense` (damage modifiers with the original formulas). `:buff` and `:sleep`
	apply them; anyone can be put to sleep or buffed now.
- Robustness: an error in a hook is logged as a warning and removes that status (without
	its hooks); the round goes on. At most `engine.MAX_STATUSES` (10) per combatant (more
	are not applied, logged); at most `engine.MAX_TICKS` (100) runs of status and summon
	code per round (the rest is skipped, logged). A status whose file is gone (retired) ends
	when the fight loads.
- **World statuses** (`scope = "world"` or `"both"`, applied outside a fight, like the
	Regen Potion's) live in `user_statuses`, tick on map moves (one move is one turn:
	`lib/world.lua` `world.move`; they can't take the last hit point), outlast fights and
	take no part in them; the character page lists them. Their lines aren't shown yet (the
	move redirects to the map). In a fight a "world" status isn't applied, and outside one a
	"fight" status isn't (logged).

### Multi-stage actions

- **Recharge** (Hyper Beam): `cast` hits, then `s:recharge(1)` puts the caster in
	`recharging` (blocks): its next turn is skipped ("You must recharge this turn."; the page
	offers only "Continue") and the monster still acts.
- **Charge** (Solar Beam): `cast` calls `s:charge(1, "release")`: the caster is `charging`
	(blocks) with the params `{ entity = "solar_beam", from = "spell", release = "release" }`
	(names only). At the start of its next turn the status runs out and its `on_expire`
	calls `t:release()`, which runs the file's `stages.release(s)` with the caster and its
	current target: that turn's action.

```lua
-- app/content/spells/solar_beam.lua (excerpt)
local function release(s)
	local damage = s:roll((s.power / 6) * 5, s.power)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
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
side, called by `s:summon("wolf", { turns = 5 })` (in fights; a file refuses in `can_cast`
when `s.summon_room` is 0: at most `control.max_allies` allies, default 1, "Allies" in the
main settings).

```lua
-- app/content/summons/wolf.lua
local function act(a)                        -- a: the summon's context
	local damage = a:roll(a.self.attack // 2, a.self.attack)
	a.target:hurt(damage)
	a:say("bite", a.self.name, damage)
end

return {
	name = "Wolf", hp = 30, attack = 12, defense = 5, dexterity = 4,
	turns = 5,                                 -- rounds it stays (0: the whole fight)
	messages = { bite = "Your %s bites the monster for %d damage.", gone = "Your %s runs off into the wild." },
	act = act,                                 -- once per round, after the player
	on_expire = function(a) a:say("gone", a.self.name) end,   -- optional; on_summon, on_death too
}
```

The context `a`: `a.self` (its handle), `a.target` (chosen by the AI), `a.data` (its
params), `a.turns_left`, `a:roll`, `a:say`. Monsters may attack an ally instead of the
player; the original formula then uses the ally's defense and dexterity. An ally leaves at
0 HP, when its rounds run out or when the fight ends; an error in its code removes it.

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
(`routes/fight.lua`): when `req.live`, the round records its trace and `go` puts the events
on its redirect (`res.events`), which `main.lua` carries into the answer of the page it
lands on (`/fight`, `/victory`, `/`). Everything
else is the page: the same handlers, the same round code, the same templates, so what stays
on screen is what a page load shows. (2.3's JSON fight API, `Accept: application/json` with
`fragments`, is gone: the live client replaced it.)

**Events** (`fight/events.lua`, from the round's trace): one per line of the page, in the
page's order, with what changed with it; a change in a step that hasn't said anything is
an event without `text`. The texts are exactly the lines the page shows (unescaped:
put them in with `textContent`). Nothing else of the model leaks (no status data, rolls,
stock, immunity).

```lua
{
	part = "player",               -- the page's paragraph: player, allies, enemies, ending
	actor = "enemy", actor_id = 2, actor_name = "Goblin Shaman",   -- who acts (a status: its bearer)
	type = "spell",                -- attack, spell, item, status (a status's tick or hook, or the
	                               -- turn's countdown), summon (an ally acting, joining, leaving),
	                               -- blocked (a status blocks the turn), run, ambush, wave (the next
	                               -- enemy), speech (a monster speaking: "Troll: “Tickles.”", see
	                               -- [Monster speech](#monster-speech)), say (anything else); the last event of a round that
	                               -- ended: victory, death or escape (no text)
	text = "The monster casts Hurt on you for 14 damage.",   -- absent: a change without a line
	hp = { { who = "player", id = 1, name = "Fapi", from = 300, to = 286, max = 300 } },
	mp = { { who = "enemy", id = 2, name = "Goblin Shaman", from = 17, to = 12, max = 17 } },
	tp = { ... },                  -- who: player | ally | enemy; an enemy's MP only if the page shows it
	status = { { who = "player", id = 1, name = "Fapi", key = "poison", status = "Poisoned",
		turns = 3, change = "add",   -- add | remove | expire | turns (counted down)
		statuses = { { key = "poison", name = "Poisoned", turns = 3 } } } },   -- the bearer's, after it
	summon = { { change = "join", id = 3, name = "Wolf", hp = 30, max = 30, turns = 5 } },   -- join | leave | turns
}
```

Lists are present only when not empty; `turns` is absent for an unlimited status or ally.
Changes go with their step's latest line (a spell's line, then its damage and MP cost).

**Every command comes back to the fight page** (Post/Redirect/Get): a `POST
/fight` that played a round saves its lines (`fights.log`) and redirects to `/fight` (a
victory to `/victory`, an escape to `/`), and `GET /fight` shows them, as often as it is
loaded. The live client follows the redirect on the server, so a round is still one
request, with its events.

**Refusals** (not enough MP, a spell not learned, an item not in the bag, a wand without
charges, a content file's `s:refuse`): nothing is played or spent, and the fight page comes
back with the reason as a note above the commands (`<p class="fight-note error"
role="alert">`), the last round's lines still there; the note is kept with them
(`encounter.with_note`) until the next round replaces them. Their texts were written for an
error page of their own: the note leaves out "Please go back and try again.".

**Stale rounds.** Every fight form carries the round it was shown at (`<input type="hidden"
name="round">`, `fights.round`, which only a played round counts up). A `POST /fight` with
another round (a second click, an older tab, a resubmitted page) plays nothing: the fight
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
status chips of a combatant's line (made if the page had none), allies joining and leaving.
A click in the middle column, any key (not while typing) or the "Skip" button plays the rest
at once; with `prefers-reduced-motion` there are no delays and no animations (`fight.css`).
A round that ends in a victory or an escape pauses 800 ms before the next page comes. Then
the regions apply; when the keyboard was in the middle column, the button that sent the
round gets the focus back (the same spell's button, unless it is now disabled; else
Attack). The monsters' and allies' bars are fight.js's (`span.fight-meter[data-client]`, so
the morph keeps them; it updates them from `data-value`/`data-max` after every answer):
without JavaScript there are none, as before. Without the live client the forms post as
plain forms and nothing is played.

**Adding an animated event type.** A new kind of line needs nothing: give the code that
says it a step (`local prev = engine.doing(f, c, "my_kind")` ... `engine.done(f, prev)`
around `engine.say` and the changes) and it arrives with `type = "my_kind"`; add the type to
the list above and to `TYPES` in `tests/e2e/fight_api.sh`. A new kind of change: record it
in the trace where it happens (`trace(f, { my_change = ..., id = c.id, ... })` in
`fight/engine.lua`), turn it into a field of the event in `events.build` (plain names and
numbers only), apply it in fight.js's `show(e, log)` (look elements up by
`data-fighter`; build DOM with `textContent`), add a CSS animation in `fight.css` (and its
`prefers-reduced-motion` exception), and extend the shape check in `fight_api.sh`.

## Monsters

Monsters are content (see [Content](#content)): `app/content/monsters/<key>.lua`, synced
into `monsters` (`lib/content/kinds/monsters.lua`) and the loadout tables
`monster_equipment`, `monster_items` and `monster_spells`. The original 151 keep ids 1-151
(keys from the names: `blue_slime` ... `lucifuge`) and only attack, exactly as before.
`goblin_shaman.lua`, `bog_witch.lua` and `bandit_captain.lua` are examples of the rest.

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
	immune = 0,                               -- 1: hurt spells, 2: hurt and sleep spells
	maxmp = 17,                               -- MP at the start of every encounter (default 0)
	uses_mp = true,                           -- spells cost it MP (default); false: free
	attack_weight = 3,                        -- its attack's weight (default 1; 0: fallback only)
	roams = false,                            -- met in random encounters (default true)
	equipment = { weapon = "dagger" },        -- slot = item key (weapon, armor, shield, accessory1-3)
	spells = {                                -- { spell, weight (default 1), when (optional) }
		{ spell = "hurt", weight = 2 },
		{ spell = "heal", weight = 3, when = function(m) return m.hp < m.maxhp // 2 end },
	},
	items = {                                 -- { item, weight, stock (per encounter; nil: no limit), when }
		{ item = "potion", weight = 4, stock = 2, when = low_hp },
	},
}
```

- **Validation** (`dk check`): the stats as above (`maxhp` >= 1, `immune` 0-2, weights >=
	1, `attack_weight` >= 0, `stock` >= 1 or absent); item and spell keys must be files;
	equipment must fit its slot (a weapon in `weapon`, an accessory in `accessory1`-`3`);
	items must be consumables and spells usable in fights; `when` must be a function.
- **MP**: every original monster has `maxmp` = the Mage's total MP at its level (the 2.2
	start of 0 + the gains in `classes/mage.lua`, at least 5), written into its file (the
	Mage's start of 5 since 2.4 left them as they were). A monster's MP is full
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
	read-only handle), `m:has_status(key)`, `m:status(key)`, `m:statuses(kind)`, plus
	`m.round` (the fight's round), `m.target` (the default opponent's handle: the player;
	`m.target:has_status("sleep")`) and `m.stock` (items: uses left). They only decide: no
	dice, no changes (an error, logged, makes the entry ineligible this turn). They stay in
	the file (`has_when` in the loadout tables marks them; the runtime takes them from the
	loaded file by position).
- **Stock** is per encounter: `stock_<position>` in the combatant's data counts down on
	each use (an entry without stock has no limit); the next encounter starts full.
- **Using** a spell or item is `action.perform` with the monster as caster (its MP cost
	skipped with `uses_mp = false`), applied by `engine.apply`; lines are the files'
	`messages.enemy` wordings, or the generic "The Goblin Shaman casts Heal." / "uses the
	Potion." plus what changed. A monster can't summon (no room on its side).
- **Random encounters** pick among the roaming, non-retired monsters of the level band
	(`monsters.roaming`: the original rows and order). Monsters with `roams = false` (the
	examples) are only met where content or a test puts them (`state.add_monster(f, row,
	wave)` + `round.start(f)`); an admin can let one roam.
- **Admin** (`/admin/monsters`, the shared content admin `admin/effects.lua`): name,
	description, level, the stats, `maxmp`, `uses_mp`, `attack_weight` and `roams` are
	overridable; the loadout is shown read-only (edit the file). The list keeps the
	original's check that the highest roaming level is the map size / 5.
- **Help** (`/help/monsters`): every non-retired monster with its effective stats and MP,
	and the spells, items (with stock) and equipment of those that have them.
- **Retired** monsters (file deleted) are no longer met; fights against them go on.

`lib/monsters.lua`: `monsters.get(id)`, `monsters.by_key(key)`, `monsters.active()`,
`monsters.all()`, `monsters.roaming(min, max)`, `monsters.loadout(row)` (`{ equipment,
items, spells }` with item and spell rows, read once per request; a row may carry its own
`loadout` table: tests), `monsters.condition(row, list, entry)` (the `when` function),
`monsters.effective(row)` (a copy with the equipment counted, base values in `base`),
`monsters.reload()`.

### Monster speech

Monsters may speak in a fight (`app/fight/speech.lua`): a `speech` table in the file holds
lists of lines for moments of the fight. Nothing is ever certain: each moment speaks by
chance, and lines may be held back for conditions, or to once a fight. The Goblin Shaman
(the commented example), the Troll, the Necromancer and the Red Dragon have some.

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
	(default true; with a `drop_level`), `icon`, `casts` and `charges` (below).
- **Icons** (schema version 14): `icon = "herb"` names `public/images/items/herb.png`
	(`[a-z0-9_]+`, square; Midworld's wares — the Stick, Branch, Club, Skivvies, Clothes,
	Leather Armor, Reed Shield, Buckler, Herb and Wand — and the Potion and Ether have one).
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
	item keys; Midworld sells the Wand). Any item a town sells can be bought as often as the
	gold and the bag allow (2.4: no more "Already purchased", a copy of the item worn
	included); the server checks that the town sells it, the gold and the bag's room.
	Weapons, armor and shields go into the bag (3.0; what is worn stays) or are worn at
	once, the player's choice: with an old item in the slot it goes into the bag (needs a
	free slot) or is sold back (its value counts toward the price). Everything else goes into the bag (`qty`, up to the room on a stack or
	a new one, and the gold). The Sell section buys any sellable bag item.
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
| `items.signed(stat, n)`, `items.compare(item, old)`, `items.category_label(item)` | `"+5"`, `"+10%"`; wearing `item` instead of `old` stat by stat (`{ stat, label, new, old, delta }`: the shop's tooltips and the purchase); "Weapon", "Consumable" |
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
| `inventory.full_charges(item)`, `inventory.spend_charge(entry)`, `inventory.recharge(uid)` | an item's charges when obtained; one charge used (true: a single-use item's last, the item is gone); the inn: refill the equipped rechargeable items (returns them) |
| `inventory.equip(uid, entry, slot)`, `inventory.equip_new(uid, item, slot)`, `inventory.unequip(uid, slot)`, `inventory.free_accessory_slot(uid)` | equipment (they clamp) |
| `inventory.stats(user)`, `inventory.names(uid)` | effective stats, equipped names per slot |

## Hotbar

(3.1, `docs/plans/hotbar.md`.) The fight menu is a bar of ten slots on the number keys: **1
Attack** and **0 Run**, fixed, and **2-9** the player's other fight actions where they put
them (`app/lib/hotbar.lua`).

- **Actions** (`hotbar.actions(user)`): the equipped gear that casts (by slot), the fight
	spells known, the fight consumables in the bag (bag order), keyed `spell:<spells id>` or
	`item:<items id>` (gear and consumables are both items; the route tells them apart).
- **The table** `user_hotbar (user_id, kind, ref_id, slot)` (schema version 17) keeps every
	action a character has **met**: on the bar (`slot` 2-9, unique per character) or off it
	(`slot` NULL: taken off, or the bar was full when it came). Attack and Run aren't stored.
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
	builds `bar`, ten `{ n, button | gone, why }`, and `more`, the buttons off the bar): each
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
	`templates/town/hotbar.html`; not while fighting: `common.not_fighting`): the ten slots, each of 2-9 with its tile and
	a list (`slot2` ... `slot9`: "Empty" and every choice, `hotbar.choices`: the actions at
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
	saving, refusals, reset, new actions), `tests/e2e/migrate.sh` (step 17),
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
	 `schema_v11.sql`, `schema_v12.sql` and `schema_v13.sql` with the game data of that time
	 (`seed_v3.sql` to `seed_v9.sql`, `seed_v11.sql` to `seed_v13.sql`), migrates them, checks the data and compares
	 the column, foreign key and index layout with a fresh install. Never edit the
	 fixtures; add a `schema_vN.sql` copy of the old schema when a test needs to start
	 from version N.

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
| `expect_text text`, `t_text` | the body's text without tags and tooltip templates (a sentence with an item name that has a tooltip); entities stay |
| `t_ok` / `t_fail msg` | custom assertions |
| `t_sql "SQL"` | run SQL on the test DB (sqlite3 or python3); `t_has_sql` |
| `t_register user pass email charname [class]`, `t_login user pass [remember]`, `t_logout` | account shortcuts |
| `t_spells username "1,6"`, `$T_KNOWN` | set the spells a user knows; SQL expression for a users row's known spell ids (`SELECT $T_KNOWN FROM users ...` → `1,6`) |
| `t_give username key [qty [slot]]`, `t_items_clear username`, `$T_ITEMS` | give an item (into the bag, or equipped in `slot`; an item that casts with full charges); take all away; SQL expression for a users row's items (`stick@weapon,herbx3`) |
| `t_fight username monster_id hp [round]`, `t_fight_new username`, `t_fight_win`, `t_fight_clear username`, `t_fight_status username who key [data [turns]]` | a fight in progress against a monster (round 2 by default); an encounter beginning where the player stands, as on a map move (the current jar's player: `POST /__test/encounter`; `$BODY` is the fight page); the current jar's won fight (`t_fight user m 0`) paid by a round, `$BODY` the victory page; no fight; a status on the player (who 1) or the monster (2), data like `'chance=i:5'` |
| `$T_ROUND`, `$T_MONSTER`, `$T_MONSTER_HP`, `$T_SLEEP`, `$T_UBER_DAMAGE`, `$T_UBER_DEFENSE`, `$T_STATUSES`, `$T_WORLD` | SQL expressions for a users row's fight in progress (0 when there is none; a finished fight kept for its page doesn't count) and statuses (`player:regen/4,enemy:sleep`; world statuses `regen/9`) |
| `t_stats`, `expect_stats "maxhp maxmp maxtp str dex atk def" label` | the logged-in character's effective stats from `/character` |
| `t_mail_latest`, `t_mail_count` | outbox |
| `t_wait_for path text` | poll up to 5 s (hot reload) |
| `t_fetch path 'a=1' [curl args]` | POST like live.js (the chat): `Accept: application/json`, the CSRF token (from the page's `data-csrf`) in `X-CSRF-Token` |
| `t_live GET\|POST path ['a=1'] [curl args]`, `t_live_page`, `t_live_forget`, `w_ops`, `w_payload op [arg]`, `w_has op [arg]`, `w_lacks op [arg]` | a live request like the live client's (python3; `X-DK-Live`, `X-DK-Have` from the jar's hash map, which the answer's `hashes` frame updates); take the map from the last full page / start empty; the answer's frames (`op args length` lines), a frame's payload, assertions |
| `live_open name [curl args]`, `live_close name`, `live_stop` | `GET /live` in the background with the current jar (to `$T/live.<name>`); end one / all |
| `live_has name text`, `live_lacks name text`, `live_wait name text [tries]`, `live_count name text` | the stream has (waits up to 3 s) / hasn't the text; how many lines have it |
| `live_publish channel event data`, `live_frames_ok name` | `POST /__test/publish`; the stream is well-formed (retry, id/event/data blocks, comments) |
| `$BASE`, `$T` (temp dir), `$CONFIG`, `$OUTBOX`, `$ADMIN_USER`, `$ADMIN_PASS`, `$BIN`, `$ROOT` | the server log is `$T/server.log` (one access line per request) |

Lua unit tests: put `tests/lua/test_<name>.lua` returning `{ name = function() assert(...) end }`.
`run.sh` runs them inside a dk VM, where they can `require("lib.php")` and friends.

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
