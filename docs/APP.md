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
| Live pages: chat, who's online, notices, broadcast banner | `app/lib/{chat,presence,notices,banner}.lua`, `app/town/babble.lua`, `app/routes/live.lua`, `app/admin/broadcast.lua` | `templates/layout/{chat,chat_posts,online,online_list,side_live,banner,live_attrs}.html`, `templates/town/babble.html`, `templates/admin/broadcast.html`, `public/js/live.js` | `tests/e2e/{chat,presence,notices}.sh`, `tests/lua/test_chat.lua` |
| Themes, font | `app/lib/themes.lua`, `app/routes/theme.lua` | `templates/layout/{head,logo,theme_picker}.html`, `public/css/themes/*.css`, `public/images/themes/*`, `public/fonts/vollkorn/*` | `tests/e2e/theme.sh` |
| Accounts | `app/routes/auth.lua`, `app/lib/{auth,session,csrf,mail}.lua` | `templates/auth/*` | `tests/run.sh` |
| Home (town / exploring view) | `app/routes/home.lua` | `templates/home/*` | `tests/run.sh` |
| Town, shop, explore, heal, character, map | `app/routes/town.lua`, `app/town/*` | `templates/town/*`, `public/css/town.css` | `tests/e2e/town.sh` |
| Items, inventory, derived stats | `app/content/items/*.lua`, `app/lib/{items,inventory,stats}.lua`, `app/town/{inventory,shop}.lua`, `app/admin/items.lua` | `templates/town/{inventory,inventory_discard,shop,shop_buy}.html`, `templates/fight/drop*.html`, `templates/admin/item{,s}.html` | `tests/e2e/{inventory,town,fight}.sh`, `tests/lua/test_{items,stats,inventory}.lua` |
| Fight, victory, drops | `app/routes/fight.lua`, `app/fight/{combat,act}.lua`, `app/lib/leveling.lua` | `templates/fight/*`, `public/css/fight.css` | `tests/e2e/fight.sh`, `tests/lua/test_{fight,leveling}.lua` |
| Smooth fights (the JSON fight API) | `app/fight/events.lua`, `app/routes/fight.lua`, `app/lib/view.lua` (`view.fragments`) | `templates/fight/*`, `public/js/fight.js`, `public/css/fight.css` | `tests/e2e/fight_api.sh`, `tests/lua/test_round.lua` |
| Fight engine (round pipeline, statuses, summons, AI, world statuses) | `app/fight/{state,engine,round,ai,act}.lua`, `app/lib/{statuses,summons,world}.lua`, `app/content/{statuses,summons}/*.lua`, `app/admin/effects.lua` | `templates/fight/{fight,statuses}.html`, `templates/admin/{effects,effect}.html` | `tests/lua/test_round.lua` (+ `fight_original.lua`, `fight_model.lua`, `spells_original.lua`), `tests/e2e/effects.sh` |
| Monsters (content with MP, equipment, items, spells) | `app/content/monsters/*.lua`, `app/lib/content/kinds/monsters.lua`, `app/lib/monsters.lua`, `app/fight/monster.lua`, `app/admin/effects.lua`, `app/community/help.lua` | `templates/community/help/monsters.html`, `templates/admin/{effects,effect}.html` | `tests/lua/test_monsters.lua`, `tests/e2e/monsters.sh` |
| Content (statuses, summons, classes, spells, items, monsters) | `app/content/{statuses,summons,classes,spells,items,monsters}/*.lua`, `app/lib/content/*`, `app/lib/{classes,spells,items,statuses,summons,monsters}.lua`, `app/cli/{content,check}.lua`, `app/admin/{classes,spells,items,effects,content}.lua` | `templates/admin/{class,classes,spell,spells,item,items,effect,effects,content_form,content_status}.html` | `tests/e2e/content.sh`, `tests/lua/test_{content,items}.lua` |
| Scripted spells and items (what they do) | `app/lib/action.lua`, `app/lib/content/{sandbox,scripted}.lua`, `app/fight/{act,engine}.lua` | | `tests/lua/test_action.lua` (+ `effects_original.lua`), `tests/e2e/content.sh` |
| Forum (boards), help, changelog | `app/routes/community.lua`, `app/community/{forum,help,changelog}.lua`, `app/lib/paging.lua` | `templates/community/{forum,help}/*`, `templates/community/changelog.html`, `public/css/community.css` | `tests/e2e/community.sh` |
| News (town box, `/news`, News board threads) | `app/lib/news.lua`, `app/community/news.lua`, `app/admin/news.lua` | `templates/community/news/*`, `templates/home/town.html`, `templates/admin/news.html` | `tests/e2e/news.sh`, `tests/lua/test_news.lua` |
| Realtime (event streams) | `app/routes/live.lua`, `app/lib/json.lua` | | `tests/e2e/live.sh`, `tests/lua/test_json.lua`, `tests/c/test_hub.c` |
| Admin panel | `app/routes/admin.lua`, `app/admin/*` | `templates/admin/*`, `templates/layout/admin.html`, `public/css/admin.css` | `tests/e2e/admin.sh` |
| Install / CLI / migrations | `app/install.lua`, `app/cli/{user,migrate}.lua`, `app/lib/migrations.lua`, `app/sql/*` | `templates/errors/503.html` | `tests/run.sh`, `tests/e2e/migrate.sh` (`tests/fixtures/{schema_v*,seed_v3,...,seed_v8}.sql`), `tests/lua/test_db.lua` |
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
- GETs should not change state. The deliberate exceptions are guarded by game state, so
	a reload is harmless: the `onlinetime`/session touch (and the presence join and sweep),
	`GET /fight` (monster pick, first
	strike, the fight's `round` counter) and `GET /victory` (pays out once).
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
| `view.json(t [, status, headers])` | `application/json` (`lib/json.lua`), `Cache-Control: no-store`; `view.wants_json(req)`: the request sent `Accept: application/json` (live.js's fetch) |
| `view.back_path(req)` / `view.back_to(req [, fallback])` | this page's path and query (for a form's `back` field) / where to redirect after a form with `back`: that path if it is same-site with a GET route, else `fallback` (`/`) |
| `view.chat(req, large)` / `view.online()` | ctx for `layout/chat.html` / `layout/online.html`, or nil when the Babble Box / Who's Online is turned off |
| `view.render(name, ctx, req)` | a rendered template string (for building fragments) |
| `view.fragments(req, template, ctx)` | the parts of the page `view.page` would draw, as HTML: `{ main, nav_left, nav_right }` (the middle column, and the side columns' boxes from the user row as it is now); same templates, so a page and its fragments can't drift |
| `view.fragment_page(req, title, template, ctx [, t])` | JSON for a page fetched by a script: `t` plus `title`, `url` (`req.path` unless `t.url`) and `fragments` (fight.js, see [Fight API](#fight-api-smooth-fights)) |
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
- `scripts`: more scripts for the page, names of `public/js/<name>.js` (`{ "fight" }` on
	the fight pages); `layout/head.html` adds them after `live.js`.
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
`layout/side_live.html`) and `scripts` (opts). The main layout marks the parts a script may
swap: `<aside class="dk-left" data-nav-left>`, `<main class="dk-middle" data-main>` and
`<div class="dk-nav-right" data-nav-right>` around `layout/nav_right` (not the whole right
column: the chat below it keeps its scroll position and typed text). Include `{{{ include("layout/head") }}}` in `<head>` to get the
CSS links (`dk.css` + the four feature stylesheets + the theme's), `dk.js` and, with
`live`, `live.js`; put `theme-{{ theme.key }}` in the `<body>` class followed by
`{{{ include("layout/live_attrs") }}}`, start the body with
`<div class="dk-banner-slot" data-banner-slot>{{{ include("layout/banner") }}}</div>`, and
use `{{{ logo() }}}` and `{{{ theme_picker() }}}`.

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
| `babble` | `babble` | `{ id, author, text, time }` (a new chat message; `time`: unix seconds) | `POST /babble` (`chat.post`) |
| `babble` | `delete` | `{ id }` | `POST /babble/#id/delete` (administrators) |
| `presence` | `join` | `{ id, name, online }` (`online`: how many are online now) | a player's first request while not online (`session.load`) |
| `presence` | `leave` | `{ id, name, online }` | the presence sweep |
| `notices` | `news` | `{ id, title, author, url }` | a news post (`/admin/news`) |
| `notices` | `banner` | `{ id, text, expires, ttl }` (`expires`, `ttl`: unix time and seconds left, absent without an expiry) | `/admin/broadcast` (set) |
| `notices` | `clear` | `{ id }` | `/admin/broadcast` (clear) |
| `user:<id>` | `reply` | `{ thread, title, author, url }` | a reply in a forum thread the player started or posted in (not to the one replying; at most 200 players) |
| `user:<id>` | `logout` | `{ session }` (one session's pages) or `{ all = true }` | logout; password change, lost password, a new password set in the user editor |
| (server) | `resync`, `bye` | empty | the hub: missed events are gone / shutdown |

The `admin` channel exists for administrators' streams; nothing uses it yet.

### Live pages

`public/js/live.js` runs on the pages of logged-in players (main and admin layouts:
`<body data-live data-csrf=... data-live-session=... [data-live-admin]>`, from
`layout/live_attrs.html`). Everything it does is also there without it: forms post and
pages reload.

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
- **Resync.** On `resync` (and after a reconnect or a takeover) every tab fetches
	`GET /live/state?back=<page>`: `{ chat, online = { count, html }, banner }`, the live
	parts rendered by the same templates as the page, and swaps them in.
- **Event data goes in with `textContent` only.** Links in notices are used only when they
	are same-site paths (`/...`, not `//`).
- **Logout.** `logout` with `all`, or with the page's own `data-live-session`
	(`session.live_id`, a hash of the session row: not the token), closes the stream and
	reloads (to `/login`); the pages of the player's other sessions ignore it.
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
	page with `textContent`/DOM methods (idempotent: an event may come twice).
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
| `logo()` | the theme's logo, linked to `/` → HTML |
| `theme_picker()` | the theme selector (a POST form to `/theme` that comes back to this page) → HTML |
| `url(path, seg..., [query_table])` | `url("/forum/thread", 7, {start = 15})` → `/forum/thread/7?start=15` (segments urlencoded) |
| `number(n)` | PHP `number_format($n)`: `1234567` → `1,234,567` |
| `date(ts)` | PHP `date("F j, Y")` (legacy `prettydate`) |
| `datetime(ts)` | `Y-m-d H:i:s` (what legacy printed for raw MySQL datetimes) |
| `nl2br(s)` | escapes, then adds `<br />` → HTML |
| `req` | the request (`req.user`, `req.path`, …) |
| `php` | the `lib.php` module |
| `ipairs pairs next select type tostring tonumber string table math utf8 os.date os.time dk` | Lua builtins |

## Themes

A theme is a stylesheet and a logo; the layout (columns, sizes, boxes) is the same in
every theme. `app/lib/themes.lua` lists them:

| Key | Name | Stylesheet | Logo |
|---|---|---|---|
| `default` | Default | `/static/css/themes/default.css`: the snow background (`public/images/themes/default/background.jpg`), near-black text and borders, dark red links with a bright red hover, translucent white title boxes | `/static/images/themes/default/logo.png` (shown at 355×120) |
| `retro` | Retro | `/static/css/themes/retro.css`: the original tiled `background.jpg` and colours | `/static/images/logo.gif` (409×108) |

```lua
-- an entry of themes.list (the selector lists them in this order)
{
	key = "retro",                                  -- [a-z0-9_]: the cookie value, body class theme-retro
	name = "Retro",                                 -- shown in the selector
	stylesheet = "/static/css/themes/retro.css",
	logo = { src = "/static/images/logo.gif", width = 409, height = 108,
		alt = "Dragon Knight" },                    -- the logo's alt text is the game's name; this if it has none
}
```

- **Choosing.** Every page with a footer (main and admin layouts, help and changelog
	pages) ends with the selector, `{{{ theme_picker() }}}` ("Theme: Default · Retro", the
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
- **Theme CSS** only overrides `dk.css` and the feature stylesheets: background, colours,
	borders, logo effects. Since only the current theme's file is linked, plain selectors
	(`body`, `a`) are enough; `body.theme-<key>` is there for feature CSS that needs to
	differ by theme. Keep sizes and layout in `dk.css` so every theme fits the same.
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
| `game.gear_rows(names)` | the Inventory panel's rows from `inventory.names()`: `{label, icon|badge, name, empty}` (weapon, armor, shield, accessory slots 1–3) |
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
	for the kind's `admin_fields` (classes: name, description, sort, playable, starting
	stats; spells: name, description, MP, power, numbers and message strings; items: see
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
A field of type `keys` with `refs = "<kind>"` lists keys of another kind (checked by
`load.all`); `write_children` maps them to ids; an optional `validate_refs(flat, all,
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

**The model** (`fight/state.lua`; tables `fights`, `fight_combatants`, `fight_statuses`):

| | |
|---|---|
| `f` | `{ user_id, round, wave, data, st, in_fight, combatants, next_id }`. `round` is the original `currentfight` counter (1: the encounter just began, no monster picked; +1 per fight page, without the original's cap of 255); `st` is `game.player(user)` (the player's HP/MP/TP stay in `users`) |
| combatant `c` | `{ id, side = "player" \| "ally" \| "enemy", kind = "player" \| "monster" \| "summon", entity_id, wave, hp, maxhp, mp, maxmp, turns_left, data, row, statuses }`, numbered from 1 per fight (the player is 1); `row` is the summons row, or the monsters row with its equipment counted (`monsters.effective`); `mp`/`maxmp`: a monster's MP; `data`: a monster's `immune` and item stock (`stock_<position>`) |
| status instance | `{ status_id, key, row, turns_left, data, applied_round, source }`: `data` holds the params it was applied with, `source` the combatant who applied it |

`state.load(user, st)`, `state.save(f)`, `state.clear(user_id)` (victory, escape, death)
and `state.begin(user_id)` (a new encounter: explore). Saved values are **names and plain
data only** (whole numbers, text, booleans: `state.encode`, "name=i:5" lines;
`action.params` refuses functions and tables), so a fight in progress never holds code: a
charged spell's release step is saved by name.

**Encounters and waves.** A fight is an ordered list of waves of enemies (`c.wave`); today
every encounter is one wave with one monster (the original random pick). The pipeline
already acts with every enemy of the current wave; when the wave is defeated the next one
enters ("Another monster appears: ..."), and the victory is "no enemy left". `/victory`
pays each defeated enemy's rewards (summed) and rolls for a drop once (at the highest
level). The player's actions aim at "the current target" (`engine.target`: the first
living enemy of the wave, `s.target` in spells), so a target picker can come later without
changing spell files.

**The round** (`round.play(f, a)`; `a.kind`: `attack`, `spell`, `item`, `run`, `continue`,
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

### Fight API (smooth fights)

With JavaScript the fight pages play a round in place: `public/js/fight.js` (loaded only on
the fight pages: `scripts = { "fight" }`) sends the fight forms with `fetch` and plays the
answer's events one by one. The server side is the same routes (`routes/fight.lua`) asked
with `Accept: application/json` (`view.wants_json`): the same handlers, the same round
code, the same templates.

**Answers.** Instead of a page, `GET`/`POST /fight`, `GET /victory`, `GET`/`POST /drop` and
`GET /dead` answer:

```lua
{
	events = { ... },             -- the round (below); [] for a page without a round
	fragments = {                 -- view.fragments: the page's parts, by the page's templates
		main = "<section class=\"box fight\">...",   -- the middle column (fight, victory, drop, death)
		nav_left = "...", nav_right = "...",        -- the side columns' boxes (HP, gold, bag, ...)
	},
	round = 7,                    -- the fight's round now (what the next form must carry); absent when over
	url = "/fight", title = "Fighting",   -- the page's address and title
	stale = true,                 -- only when the form was stale (below)
}
-- or, where the page would redirect (a 302 would be followed by fetch, losing the events):
{ events = { ... }, redirect = "/victory" }   -- also "/" (escaped, nothing pending), "/fight"
-- or, instead of an error page (refusals, invalid choices; nothing changed):
{ error = "Your Hit Points are already full. Please go back and try again." }
```

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
	                               -- enemy), say (anything else); the last event of a round that
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

**Stale rounds.** Every fight form carries the round it was shown at (`<input type="hidden"
name="round">`, the `fights.round` the page saved). A `POST /fight` with another round (a
second click, an older tab, a resubmitted page) plays nothing: the answer is the fight as
`GET /fight` shows it (that GET counts a round, as always) with the note "That command came
from an older page, so nothing happened." (`stale = true` in JSON); a won fight goes on to
`/victory`, and a fight that is over (not fighting any more) redirects to `/`. A form
without the field (from before 2.3) plays as before. The counter has no cap (the original's
stopped at 255), so long fights are protected too.

**fight.js.** Forms marked `data-fight` (the fight commands, the drop's Take/Leave) and links
in the middle column to the four fight pages (the victory page's drop link) go through
fetch (POST: the form's fields plus the button pressed, `X-CSRF-Token` from the form's
`csrf` field or `<body data-csrf>`). Meanwhile the forms' controls are disabled and
`data-main` is `aria-busy`. Then it:

1. clears the round lines (`[data-fight-log]`) and plays the events: each line is added
	(in the page's paragraphs, `fight-yourturn` ... `fight-roundend`) 400 ms after the
	previous one; its changes update the player's numbers and bars in the right column
	(`[data-meter=hp|mp|tp]` values, `[data-bar=hp|mp|tp]` bar widths), the numbers and bars of the monsters and
	allies (`[data-fighter=<id>][data-stat=hp|mp][data-value][data-max]`; fight.js adds the
	bars), the status chips of a combatant's line (made if the page had none), allies
	joining and leaving. A click in the middle column, any key (not while typing) or the
	"Skip" button plays the rest at once; with `prefers-reduced-motion` there are no delays
	and no animations (`fight.css`).
2. swaps the fragments in (`data-main`, `data-nav-left`, `data-nav-right`), sets the title
	and `history.replaceState`s the answer's `url`, so a reload shows the same page (and
	the screen ends up exactly as the server rendered it);
3. follows a `redirect` after a short pause: another fight page is fetched the same way,
	anything else (`/`) is a normal navigation;
4. shows an `error` as a note above the form (the form stays; nothing was played).

Any network error, non-JSON answer (a 403 for CSRF, a redirect to `/login`) or failure
before the answer posts the form (or follows the link) as without JavaScript; a stale
round then shows the fight as it is. A failure after the answer reloads the page.

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
- **MP**: every original monster has `maxmp` = the Mage's total MP at its level (start +
	gains in `classes/mage.lua`, at least 5), written into its file. A monster's MP is full
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
	 `tests/fixtures/schema_v0.sql` (version 0) to `schema_v9.sql` (version 9) with the
	 game data of that time (`seed_v3.sql` to `seed_v9.sql`), migrates them, checks the data and compares
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
| `t_ok` / `t_fail msg` | custom assertions |
| `t_sql "SQL"` | run SQL on the test DB (sqlite3 or python3); `t_has_sql` |
| `t_register user pass email charname [class]`, `t_login user pass [remember]`, `t_logout` | account shortcuts |
| `t_spells username "1,6"`, `$T_KNOWN` | set the spells a user knows; SQL expression for a users row's known spell ids (`SELECT $T_KNOWN FROM users ...` → `1,6`) |
| `t_give username key [qty [slot]]`, `t_items_clear username`, `$T_ITEMS` | give an item (into the bag, or equipped in `slot`); take all away; SQL expression for a users row's items (`stick@weapon,herbx3`) |
| `t_fight username monster_id hp [round]`, `t_fight_new username`, `t_fight_clear username`, `t_fight_status username who key [data [turns]]` | a fight in progress against a monster (round 2 by default); an encounter that just began; no fight; a status on the player (who 1) or the monster (2), data like `'chance=i:5'` |
| `$T_ROUND`, `$T_MONSTER`, `$T_MONSTER_HP`, `$T_SLEEP`, `$T_UBER_DAMAGE`, `$T_UBER_DEFENSE`, `$T_STATUSES`, `$T_WORLD` | SQL expressions for a users row's fight (0 when there is none) and statuses (`player:regen/4,enemy:sleep`; world statuses `regen/9`) |
| `t_stats`, `expect_stats "maxhp maxmp maxtp str dex atk def" label` | the logged-in character's effective stats from `/character` |
| `t_mail_latest`, `t_mail_count` | outbox |
| `t_wait_for path text` | poll up to 5 s (hot reload) |
| `t_fetch path 'a=1' [curl args]` | POST like live.js and fight.js: `Accept: application/json`, the CSRF token (from the page's `data-csrf`) in `X-CSRF-Token` |
| `live_open name [curl args]`, `live_close name`, `live_stop` | `GET /live` in the background with the current jar (to `$T/live.<name>`); end one / all |
| `live_has name text`, `live_lacks name text`, `live_wait name text [tries]`, `live_count name text` | the stream has (waits up to 3 s) / hasn't the text; how many lines have it |
| `live_publish channel event data`, `live_frames_ok name` | `POST /__test/publish`; the stream is well-formed (retry, id/event/data blocks, comments) |
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
