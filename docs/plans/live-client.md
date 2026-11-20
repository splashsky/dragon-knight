# Plan: 3.0 — the live HTML client

Status: **done** — version **3.0** (started after 2.4.0 with `view.GAME_VERSION =
"3.0.0-dev"`, `DK_VERSION "3.0.0-dev"` and a new top changelog entry `version = "3.0.0",
date = "unreleased"`); each step below says how it was implemented ("As implemented"),
then keeps its design as approved. Implemented in six steps: **L0** pure GETs, **L1** regions and the
wire protocol (server), **L2** the client, **L3** fights on the client, **L4** live sync,
**L5** measure, document, release.

Decisions taken with the owner: updates are **region hashes + DOM morph** (only changed
regions travel, only changed nodes are touched); a slow request may show a **thin progress
bar after ~250 ms** (nothing else new is visible); **every layout is live** (game, admin,
accounts, help); **all GETs become pure** (the fight's state changes move into the POSTs
that cause them).

## Goals

- **Looks identical.** Every page renders the same with and without JavaScript, and the
	same as 2.4. The only new visible thing is the progress bar on slow requests.
- **Server-authoritative.** The client keeps no game state and builds no game markup.
	Every byte of HTML comes from the templates; the client only decides where it goes.
	What the client shows after any request is what a full page load of the same URL would
	show.
- **Seamless.** After the first page load there are no more full page loads: links and
	forms go through `fetch`, and focus, typed text, scroll positions, open panels, the
	event stream and the chat survive navigation. Back/forward work and restore scroll.
- **Cheap and precise.** Only the regions whose HTML changed travel; the client morphs
	them, touching only the nodes that differ; a POST and the page it redirects to are
	one round trip (the server follows its own redirects).
- **No build, no dependencies.** Plain scripts in `public/js/` (the existing style: IIFEs,
	no modules, no framework); the C engine needs no changes.
- **Progressive enhancement.** Without JavaScript, before it has arrived, or when anything
	in it fails, the game is plain links and forms exactly as today. Every enhanced action
	has a defined fallback (below).

## L0: pure GETs — ✅ done

**As implemented** (`docs/APP.md` "Pure GETs", "Fight engine", "Fight API"): schema
version 15 adds `fights.outcome`, `fights.log` and `fights.result`;
`app/fight/encounter.lua` holds how a fight begins (`encounter.begin(user_id)`, from `POST
/move`: the monster picked where the player stands, its first strike played and saved, a
death included) and ends (`encounter.win`: the rewards paid in the winning round and kept
for `GET /victory`; `encounter.die`). One change from the design below: **`POST /fight`
still answers with the fight page itself** (no redirect), as in 2.4. `GET /fight` now
renders the same page from the saved fight and its last round's lines, so the two can't
differ, no-JS players keep 2.4's single request per round, and the live client gets the
same answer either way. A stale form shows the fight as `GET /fight` does, with its note
(no `?stale=1`). **3.0.1 then did the redirect after all**: every `POST /fight` ends with
`302 /fight` (or `/victory`, `/`), a stale form's note and a refused command's reason are
kept with the last round's lines (`fights.log`, `encounter.with_note`), and refusals became
a note on the fight page instead of an error page (for JavaScript and plain forms alike). A "Continue" when nothing blocks the turn plays nothing and shows the page
as it is. A finished fight is forgotten on the next move, travel or encounter
(`state.forget`, `state.clear`). Test hooks: `POST /__test/encounter` (`t_fight_new`) and
`GET /__test/routes` in `app/routes/test.lua`; `t_fight_win` pays a won fight through a
round. `tests/e2e/pure.sh` snapshots every game table (all but `sessions`, `meta`,
`users.onlinetime`/`online`) around every GET and HEAD route of the router, in town,
exploring, fighting (with a status and an ally), after a victory with a drop, after a death
and as an administrator; `migrate.sh` covers v14 → v15 (`schema_v14.sql`, `seed_v14.sql`)
and v7 → 15.

The design as approved:

A **GET (or HEAD) changes no game state.** Bookkeeping stays allowed: the session touch
and expiry slide, presence (join, sweep), the content sync, the CSRF cookie seed. This is
what lets the client refetch any page at any time (back/forward, resync, another tab
acting) and show exactly what the server would.

Today two GETs play the game: `GET /fight` (picks the monster when an encounter has just
begun, plays its first strike, counts the fight's round) and `GET /victory` (pays the
rewards, rolls the drop, ends the fight). Changes (schema version **15**):

- `fights.outcome TEXT NOT NULL DEFAULT ''` ('' in progress, `victory`, `death`) and
	`fights.log TEXT NOT NULL DEFAULT ''` (the last round's lines, one `<part>\t<line>` per
	line, `part` one of `yourturn`, `allyturn`, `monsterturn`, `roundend`). A finished fight
	is **kept** (model, statuses, log, rewards in `fights.data`) so its page can be shown
	again, until the next encounter begins (`state.begin`) or the player moves or travels.
	`state.load` returns the fight with its `outcome`; the round pipeline only ever sees
	fights in progress.
- `POST /move`: when the 1-in-5 roll hits, the encounter begins there: the monster is
	picked, the first strike (ambush) is played and saved, then `302 /fight`. Same dice,
	same order, one request earlier.
- `POST /fight` (Post/Redirect/Get): plays the round, saves its lines, then `302 /fight`.
	Victory: the rewards are paid in this POST (experience, gold, levels, spells, the drop
	roll; same functions, same order), the fight is kept with outcome `victory`, `302
	/victory`. Death: outcome `death` (`currentaction` and the player's numbers as today),
	`302 /fight`. Escape: cleared, `302 /`. A stale form (another round): nothing played,
	`302 /fight?stale=1`.
- `GET /fight`: the fight in progress with its last round's lines, the form carrying
	`fights.round` as is (no increment); after a death, the fight as it ended with the
	"You have died" block; a won fight redirects to `/victory`; no fight: the old "Cheat
	attempt" page. `?stale=1` adds the stale note.
- `GET /victory`: the kept rewards (nothing paid); no won fight: `302 /`.
- The round counter counts played rounds: the encounter's first strike is round 1, the
	first form carries 2, as the numbers came out before.
- `POST /drop` and the other POSTs that render a page directly stay as they are (a POST
	may answer with a page); their address is the POST's (see L2, "POST results").
- Migration: pending encounters (a fights row without enemies, from `state.begin` before
	15) are cancelled (the player is back to Exploring at the same spot); won but unpaid
	fights are paid in the step's `after_sync` with the same payout function, and kept as
	`victory`.
- HEAD keeps its rollback (now a safety net, not a requirement).

**Tests**: `tests/e2e/pure.sh`: every GET route of the route table, for a player in town,
exploring, fighting, after a victory with and without a drop, after a death, and an
administrator: the game tables (everything but `sessions`, `meta`, the presence columns)
are byte-identical before and after. The fight scripts (`fight.sh`, `fight_api.sh`,
`playthrough.sh`, `wand.sh`, `effects.sh`, `monsters.sh`) follow the new flow; the seeded
form-vs-API comparisons keep their meaning. `migrate.sh`: v14 → v15 with a pending
encounter and a won unpaid fight.

## L1: regions and the wire protocol (server) — ✅ done

**As implemented** (`docs/APP.md` "Live client"): `app/lib/wire.lua` (markers, split,
skeleton hashes, `changed`, `hashes`, encode/decode, the have header, internal-redirect
helpers), `view.layout` returning `res.live` for live requests and `wire.page` (markers
stripped, `<html data-h>`) otherwise, `main.lua`'s `live_response` (redirects followed on
the server with the cookies set so far, `go`, `doc`, `Vary`). The regions are as below
(the left and right columns' boxes each a region; the chat split into `chat-posts` and
`chat-form`). Changes from the design: the `hashes` frame carries only the hashes that
changed (and `name=-` for regions gone), since sending all of them every time cost more
than a typical answer's regions; `layout/head.html` now loads every script on every page
(`live.js` and `fight.js` too; the `scripts` layout option is gone), so `head` is the same
everywhere and a move into a fight doesn't fall back to `go`. Measured on a dev install: an
unchanged page costs the footer's timing line (~0.4 KiB), a map move ~1.1 KiB (`loc`,
`foot`), a fight round ~4.8 KiB (`main`, `charpanel`, `foot`) against a 10.7 KiB page.
Tests: `tests/lua/test_wire.lua`, `tests/e2e/live_wire.sh` with the `t_live` helpers of
`tests/run.sh` and `tests/wire.py`.

The design as approved:

**Regions.** A layout or template marks the parts of a page that change on their own:

```
{{{ region("left") }}}<aside class="dk-left" data-r="left">...</aside>{{{ endregion() }}}
```

`region(name)`/`endregion()` (helpers in `lib/view.lua`) emit invisible markers
(`<\1name>` and `</\1>`: a `<` never comes out of escaped text, so they can't be forged
by user data) around the element whose `data-r` names the region. Regions nest. Names
are unique in a page. Two are special: `root` is `<body>` (its attributes and
everything in it) and `head` is the contents of `<head>` except `<title>`.

The main layout's regions (the others follow the same idea): `root`, `banner` (the
banner slot), `left` (with `loc`, `towns`, `functions`: the left column's boxes), `main`
(the middle column), `right` (with `charpanel`, `invpanel`, `spellpanel`, and `side`: the
online count and the chat, with `chat-posts` and `chat-form`), `foot` (the footer's
timing line), `themes` (the theme picker, which carries the page in `back`). Adding
`data-r` attributes changes nothing visible.

**Hashes.** After rendering, `lib/wire.lua` splits the page at the markers in one pass
and hashes each region's **skeleton**: its HTML with every child region replaced by a
placeholder (`<\1name>`), so a region's hash changes only when its own markup does. Hash:
the first 12 hex digits of SHA-256 (`dk.crypto.sha256`). A full page strips the markers
(one `gsub`) and carries every hash on `<html data-h="root=… left=…">`, so the client
knows from the first load what it has.

**A live request** is any GET or POST with `X-DK-Live: 1`; it may send `X-DK-Have: name=hash
...` (the regions it has). The **same route, guards and handler** run; then:

- `view.layout` renders the layout with markers and, instead of the page, answers with
	the regions whose hash differs from the client's (walking from `root`: a region the
	client has with the same hash is skipped and its children are compared; a region sent
	whole includes its children). `head` is never sent: when it differs (a theme change, a
	new stylesheet or script after a deploy) the answer is `go` and the client loads the
	page normally.
- A **redirect to a same-site path with a GET route is followed on the server**
	(`main.lua`, up to 5 hops, a fresh dispatch with the cookies the earlier hops set, so
	login and logout work): a POST and the page it lands on are one round trip, and the
	answer's `url` is where it landed. A redirect elsewhere becomes `go`.
- An HTML page that isn't a layout's (the 500 and 503 pages) becomes `doc`. Anything
	else (JSON, text, the event stream) passes through unchanged.
- Responses get `Vary: X-DK-Live` (pages are already `private, no-cache`).

**The wire format** (`application/x-dk-live`): a line `DK1`, then frames:

```
<op> [<arg> ...] <length>\n<length bytes of payload>\n
```

Lengths are in bytes, payloads are raw (no escaping: HTML goes as HTML), unknown ops are
skipped (forward compatible). Ops, in this order:

| Op | Payload |
|---|---|
| `title <n>` | the document title |
| `url <n>` | the page's address (path and query) |
| `events <kind> <n>` | JSON for a player of that kind (L3: `fight`, the round's events), played before the regions apply |
| `region <name> <n>` | the region's element as HTML (outerHTML; `root`: the `<body>`), children included |
| `hashes <n>` | `name=hash` for every region of the page now, space-separated |
| `go <n>` | load this URL normally instead |
| `doc <n>` | a whole HTML document to show instead |

The HTTP status is the page's (a 404 page is a 404 with a wire body).

**Tests**: `tests/lua/test_wire.lua` (split, skeleton hashes, nesting, unbalanced markers
fail loudly in dev and fall back to `root` otherwise, encode/decode round trip);
`tests/e2e/live_wire.sh` (a `t_live` helper with a small byte-exact frame reader):
for every page of `pure.sh`, the live answer without `X-DK-Have` rebuilds exactly the
full page's body; with the page's own hashes, nothing but `title`/`url`/`hashes` (and the
always-changing `foot`) comes back; a move sends `loc` but not `towns`; redirects followed
(POST /move → the fight, login, logout); `go` for a changed `head` and external redirects;
`doc` for a 500; CSRF failures; HEAD.

## L2: the client — ✅ done

**As implemented** (`docs/APP.md` "Live client", "The client", "Live pages"):
`public/js/client.js` (~520 lines) as designed below, with these decisions made on the
way: it is loaded first of the page scripts and listens on `window`, so the other scripts'
`document` listeners act first (the chat's form stays live.js's); history entries carry a
key and their scroll is kept in memory (popstate comes after the browser left the entry),
and also written to `history.state` for reloads; `url` is sent only for a page a GET shows
(a POST's own page, like "You have travelled to Midworld", keeps the address on screen and
is marked, and a refresh keeps its middle column); `go` may be empty (load the address on
screen). Parts of L4 came with it, as the client needed them: live.js runs on every page
and starts and stops its stream with `<body data-live>` (now on the minimal layout too, so
help and popups don't drop it), reports its own changes with `DK.touched`, resyncs and
handles logout through `DK.refresh()`, and toasts stay out of popups. Tests:
`tests/js/test_client.js`, and `tests/e2e/browser.sh` driving `tests/browser/client.js` in
headless Chrome/Edge over the DevTools protocol (45 checks), `GET /__test/slow` for the
progress bar.

The design as approved:

`public/js/client.js` (new, loaded on every page before the others): the protocol, the
morph, navigation, forms, history, the progress bar. It exposes `window.DK` for the other
scripts: `DK.visit(url)`, `DK.refresh()`, `DK.on("events:<kind>", fn)` (a player
returning a promise), `DK.on("applied", fn)`.

**What it takes over.** Clicks on same-origin `<a href>` (left button, no modifier keys,
no `target`, `download`, `data-popup` or `data-native`, not a hash on the same page, not
`/static/` or `/live`) and submits of same-origin forms (urlencoded, no `target` or
`data-native`; the pressed button is included via `new FormData(form, submitter)`, or
appended by hand where unsupported). Everything else is native.

**Requests.** One visit in flight at a time: a new GET aborts a running GET
(`AbortController`); anything started while a POST runs waits for it; a second submit of
the same form while it runs is ignored. Headers: `X-DK-Live: 1`, `X-DK-Have`, the CSRF
token in `X-CSRF-Token`. After 250 ms without an answer the progress bar shows (`<html
class="dk-busy">`, `aria-busy` on `main`).

**Applying an answer.** `events` players run first (forms disabled meanwhile); then each
`region` is morphed into `[data-r=name]` (`root` into `<body>`), the hash map is replaced
by `hashes`, the title set, and the URL pushed (a new address) or replaced (the same).
After a POST the submitted form, if still there, is `reset()`, so its controls show what
the server rendered (cleared after success, kept values after a validation error).

**The morph** (~150 lines): attributes synced; children matched by key (`data-r`, `id`,
`data-id`, `data-k`), else by position and tag; text nodes updated in place; `<template>`
contents replaced when they differ; an element of another tag replaced. It never removes
elements marked `data-client` (the tooltip box, toasts, the progress bar, the screen-reader
announcer), never touches a control's live value except through the form `reset()` above
(so typed chat text survives), and leaves client-owned attributes alone (`open` on
`details[data-keep-open]`, tooltip.js's `data-tip-title`).

**History.** `history.scrollRestoration = "manual"`; each entry's state holds its scroll
position. A new address scrolls to the top (or to the `#hash`); the same address keeps
the scroll (a fight round). Back/forward: a live GET of that address (pure since L0), then
the saved scroll. **POST results** (a page a POST rendered without redirecting, like "You
travelled to Midworld") get their POST address like a native submit; when such a view is
refreshed (L4) its `main` is kept and only the other regions update.

**Focus and screen readers.** Focus stays where it was when that element survives the
morph; otherwise (a new address) it goes to the middle column, and the new title is
announced in a polite live region.

**Fallbacks.**
- No JavaScript, or old browsers (no `fetch`, `AbortController`, `TextDecoder` or
	`history.pushState`): nothing is intercepted.
- JavaScript still loading: links and forms work natively until it runs (scripts are
	`defer`); nothing on the page depends on it.
- A GET that fails (network error, a non-wire answer, a script error while applying) or
	takes longer than 10 s: a normal navigation to the same URL.
- A POST whose request fails before an answer: the client can't know whether it was
	applied, so it loads the current URL normally (safe: GETs are pure) and the page shows
	the truth. A POST answered with something other than the wire format: that document is
	shown (`doc` handling).
- `go`: a normal navigation. `doc`: the document replaces the page
	(`document.open/write/close`), as a native navigation would show it.

**Tests**: `tests/js/test_client.js` (node, pure functions: the frame reader, the have-map,
which links and forms qualify); a browser check `tests/browser/` driven over the DevTools
protocol with headless Chrome/Edge when one is installed (skipped like node otherwise):
navigation without reloads (a `window` marker survives), regions applied, back/forward and
scroll, the chat's typed text kept across a move, a slow request's bar, a killed
connection falling back.

## L3: fights on the client — ✅ done

**As implemented** (`docs/APP.md` "Fight events"): the fight routes record the round's
trace for live requests and attach its events (`opts.events` on the page, `res.events` on a
redirect, carried by `main.lua` into the page the redirects land on); `fight.js` is a
player (`DK.on("events:fight")`), with the 2.3 animations, the forms locked while it plays,
an 800 ms pause before a victory or escape moves on, and the focus back on the button used.
One change from the design: **the monsters' and allies' bars stay fight.js's** rather than
the template's, so the no-JS page is exactly 2.4's; they carry `data-client`, so the
morph keeps them, and they are updated from `data-value`/`data-max` after every answer. The
JSON fight API and `view.fragments`/`view.fragment_page` are gone; an error (a refusal) is
the error page for everyone. `fight_api.sh` reads live answers (`fa.py` builds the old `d`
from the frames, so its seeded form-vs-client comparisons stand), `tips.sh` reads a live
answer's regions, `browser.sh` plays a round in the browser, and `dkbench`'s JSON fighters
send live requests (without `X-DK-Have`: the whole page each time, the most a live answer
costs).

The design as approved:

- `fight.js` becomes a player: `DK.on("events:fight", play)` plays the round's events on
	the page that is showing (lines, bars, statuses, allies, skip, reduced motion: as in
	2.3), then the regions apply. The fight routes attach the round's events to their
	redirect (`res.events`), and `main.lua` carries them into the answer of the page it
	lands on.
- The bars of monsters and allies are rendered by the template (they were added by
	fight.js): the same look, with or without JavaScript, and nothing for the morph to
	remove.
- The JSON fight API (`Accept: application/json`, `{ events, fragments, redirect }`) and
	`view.fragments`/`view.fragment_page` go away: the wire format replaces them.
	`fight_api.sh` keeps its seeded form-vs-live comparisons over the wire; `dkbench` sends
	live requests where it sent JSON (`make bench` compares form and live fights).

## L4: live sync — ✅ done

**As implemented** (`docs/APP.md` "Live pages", "Events"): resync, a reconnect, the
bfcache, and logout go through `DK.refresh()` (L2); `stale` on `user:<id>` after every
successful POST of a player (`main.lua` `publish_stale`; `req.quiet` for the chat's and the
banner dismissal), the sending page's `X-DK-Tab` ignored by it, debounced 250 ms, hidden
pages on showing again (and after a minute hidden); markup prototypes (`chat-post`,
`online-name`, `banner`, `toast`) filled by live.js's `proto()`, the events carrying what
the markup needs (`when`, `delete` for chat messages, `url` for presence). One change from
the design: **`GET /live/state` stays**: live.js uses it to ask, before reopening a
stream after an error status, whether the player is still logged in, and as the resync
for pages without the live client (a browser with EventSource but without the client's
needs). Prototypes leave out the page's address (`back`), since it would change their
region with every page. Tests: `live_wire.sh` ("the player's other pages"), `browser.sh` (a
second tab following a move without a page load; a chat post from the prototype equal to
the server's markup), `chat.sh`, `presence.sh`, `notices.sh`.

The design as approved:

- **Resync** (the stream's `resync`, a reconnect, a page back from the bfcache, a tab
	visible again after more than a minute) is `DK.refresh()`: a live GET of the current
	address with the hashes; only what changed comes back. `GET /live/state` goes away.
- **Other tabs and devices.** After every successful POST of a logged-in player (but
	chat posts and banner dismissals) `main.lua` publishes `stale` on `user:<id>` with the
	sending tab's id (`X-DK-Tab`, random per tab). Every other page of the player refreshes
	(debounced 250 ms; a hidden tab when it becomes visible). Tabs of one browser share the
	stream as before; the sender ignores its own.
- **Markup prototypes.** live.js stops building markup: the chat post, the online name,
	the banner and the toast come from `<template data-proto="…">` elements rendered with
	the page (so an administrator's chat posts carry the delete button with their token);
	live.js clones them and fills `data-slot` elements with `textContent` only.
- The stream stays open across navigation (no reconnect per page). live.js starts it when
	`<body data-live>` appears (after a live login) and stops it when it goes.

## L5: measure, document, release — ✅ done

**As implemented** (`docs/PERF.md` "3.0: the live client"): measuring bytes per action
showed the chat panel (in the town page's middle column, elsewhere in the right column)
resent whole with its 50 messages, and a third of every navigation spent on fields that
change on every page. Hence placeholders for regions the client has inside a region sent
whole (`<template data-r-keep>`), regions in new markup adopted by name (moved and
morphed: the chat keeps its typed text between columns), and `chat-back`, `theme-back`,
`foot-time` as regions of their own: a move ~0.8 KiB, a fight round ~3.8 KiB, a navigation
1–6 KiB, against 13–20 KiB pages. Splitting and hashing a page costs ~0.15 ms (a plain
search for the marker byte instead of a Lua pattern: 0.21 → 0.15 ms). Latency against 2.4
couldn't be compared on this machine (runs of the same build varied 2–3×); that needs a
quiet machine with pinned CPUs.

The design as approved:

- `make bench BENCH_SCENARIO=mixed` and `realtime-mixed` with live requests: bytes per
	action and p99 against the 2.4 numbers (target: no p99 regression; a move or a fight
	round well under 3 KiB on the wire); the cost of splitting and hashing a page
	(`docs/PERF.md`).
- `docs/APP.md`: "Live client" (regions, the protocol, adding a region, the fallbacks),
	"Pure GETs", the fight sections; `PLAN.md` (URL map: no stateful GETs; phases);
	`README.md`.
- Changelog, version `3.0.0`.

## Out of scope for 3.0

Prefetching on hover, optimistic updates, server-side diffing below the region level,
HTTP/2, offline play.
