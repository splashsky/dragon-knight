# Dragon Knight

A browser RPG inspired by *Dragon Warrior* for the NES: explore a map, fight monsters,
level up, collect drops, buy gear and maps in towns, chat in the babble box and the forum.
Open pages update live: chat messages, who's online, news and forum notices, and the
administrator's announcements; fights play out in place, blow by blow.

This is a rewrite of **Dragon Knight 1.1.11** (originally PHP/MySQL by renderse7en,
released 3/26/2006) as a single self-contained program: a small HTTP server written in C
that runs the game logic in Lua and stores everything in SQLite. Game mechanics, data,
messages and the three-column look are kept as in the original.

- Original project: [renderse7en/dragon-knight](https://github.com/renderse7en/dragon-knight)
	(the PHP source is also in this repository's history, on `master`).
- See also: [Dragon Scourge](https://github.com/renderse7en/dragon-scourge)
- [Original live demo](http://dragon.se7enet.com/)

## Architecture

- **One binary, `./dk`.** A hand-written HTTP/1.1 server (one I/O thread on `epoll`
	— `poll` elsewhere — with keep-alive, pipelining and a timer heap; a worker thread per
	CPU that writes its response straight to the socket; static files under `/static/`
	cached in memory or sent with `sendfile`, with `ETag`/`Last-Modified` and 304s; a fast
	503 when requests queue up). Lua 5.5.1 and SQLite 3.54.1 are vendored under `vendor/`
	and compiled in, unmodified. Nothing else is needed at runtime.
- **A fresh Lua VM per request**, share-nothing like PHP. Each pool VM lives in its own
	memory arena: it is built once (libraries, `dk` API, config and app modules loaded),
	snapshotted, and after every request restored to that snapshot with one memory copy, so
	no state survives a request and no request pays for VM construction.
- **Bytecode cache + hot reload.** Lua modules and templates are compiled once and cached
	as bytecode. An inotify watcher on `app/`, `templates/` and the config file drops the
	cache and retires stale spare VMs, so an edit shows up on the next browser refresh, with
	no rebuild or restart.
- **Templates** (`templates/**/*.html`) are compiled to Lua by the C side:
	`{{ expr }}` (HTML-escaped), `{{{ expr }}}` (raw), `{% lua statements %}`,
	`{# comments #}`, with `-` trim markers. Errors report `template:line`.
- **Event streams (server-sent events).** `GET /live` keeps a connection open on which
	the server pushes events (chat, notices, …). Streams belong to the I/O thread, not to
	a worker or a VM: a hub fans each event out as one shared buffer to every subscriber,
	keeps the last events of each channel for reconnects (`Last-Event-ID`), sends
	heartbeats and drops clients that stop reading. Lua publishes with `dk.publish`, and
	events go out only when the request's transaction commits.
- **SQLite** (WAL), one connection per worker. Every request runs in one transaction
	(`BEGIN IMMEDIATE … COMMIT`, rolled back on any error), so game updates are atomic;
	workers take turns on an in-process lock, and a background thread checkpoints the WAL.
- **Measured.** `make bench` loads a temporary install with scripted players, and
	`dk stats` (or `/admin/server`) shows the server's live metrics; `docs/PERF.md` has
	the numbers.

`PLAN.md` describes the engine and its Lua API in detail; `docs/APP.md` is the guide to
the Lua app (routes, views, templates, helpers, tests).

## Requirements

A C11 compiler and `make` on Linux. That's all. (The test suite also uses `bash`, `curl`
and `sqlite3` or `python3`.)

## Quick start

```sh
make run PORT=8080                     # then open http://127.0.0.1:8080/ and log in as admin / admin
```

`make run` builds `./dk` and serves the game in the foreground (Ctrl-C stops it). The first
time, it creates `config.lua` from `config.example.lua` with a random `secret` and installs
the game with an administrator `admin` / `admin` (`ADMIN_USER`, `ADMIN_EMAIL`, `ADMIN_PASS`
change that); later runs reuse both, and an out-of-date database is backed up and migrated
first, so pulling new code and `make run` just works. `BIND=0.0.0.0` listens on every
interface (default: the config's `bind`); `CONFIG=path` uses another config file.

By hand:

```sh
make                                   # builds ./dk
cp config.example.lua config.lua       # then edit: port, paths, secret, dev = false
./dk install --admin admin admin@example.com 'a-good-password'
./dk serve                             # http://127.0.0.1:8080/
```

`dk install` prints a random `secret` if the config has none; paste it into `config.lua`.
The database and the mail outbox go to `data/` by default. Serve over HTTPS through a
reverse proxy in production and set `cookie_secure = true`. After updating the game, run
`make migrate` (check, back up, then `./dk migrate`) to bring an existing database up to
date; it does nothing when it already is. To run the game on a server, see
[Deployment](#deployment).

## Command line

Every command accepts `--config PATH` (default `./config.lua`). Only `dk install` and
`dk serve` create the database; `dk migrate`, `dk content`, `dk user` and `dk backup` exit
with status 3 when it doesn't exist.

| Command | |
|---|---|
| `dk serve [--port N] [--bind ADDR]` | run the HTTP server; `--port` (1–65535, or 0 for any free port) and `--bind` (an IPv4 or IPv6 address) override the config |
| `dk install [--admin USER EMAIL PASS] [--charname NAME] [--class ID\|KEY] [--partial] [--force]` | create the schema, load the default game data, sync the content files and create the administrator (`--class`: by id or key, default 1 / `mage`; `--partial`: no game data except the classes, spells and items; `--force`: drop existing tables first) |
| `dk migrate [--status]` | upgrade an existing database to the current schema and sync the content files, in one transaction (`--status`: show the versions only). Until it runs, the game answers every page with a 503 "run `dk migrate`" page |
| `dk content sync` | load and validate the content files (`app/content/`) and update the database now (the running game does this by itself on the next request after a file changes); fails, changing nothing, when a file is invalid |
| `dk content status` | content files, database rows (and retired ones) and admin overrides per kind, whether the database is in sync, and any errors |
| `dk backup [OUTPUT]` | copy the database, safely while `dk serve` runs (SQLite backup API, one consistent snapshot), check the copy with `PRAGMA integrity_check` and print its path. OUTPUT defaults to `<db dir>/backups/<db name>-YYYYMMDD-HHMMSS.db` (UTC); an existing file is never overwritten. Exit status 3 if the database does not exist |
| `dk user list` | list accounts |
| `dk user passwd USER NEWPASS` | set a password (ends the user's sessions) |
| `dk user admin USER` | make a user an administrator |
| `dk check` | compile every Lua module and template, build a VM and validate the content files; non-zero exit on error (naming the file) |
| `dk stats` | the running server's metrics (connections, requests and latency buckets, queue, workers, VM pool, database lock waits and checkpoints, static cache, event streams and subscribers per channel, memory), read from its stats socket (`stats_socket`, by default `dk.sock` next to the database); administrators see the same on `/admin/server` |
| `dk version` | print the version and the Lua/SQLite versions |

## Configuration

`config.example.lua` documents every key. Server keys (`bind`, `port`, `workers`,
`spares`, paths, request limits and the tuning keys below) are read at startup. App keys (`dev`, `secret`,
`pbkdf2_iterations`, `cookie_secure`) are re-read for every fresh VM, so they apply on the
next request. Game settings (game name, map size, forum, email verification, …) live in
the database and are edited in the admin panel at `/admin`. Character classes, spells and
items are content files (see [Adding a class, a spell or an item](#adding-a-class-a-spell-or-an-item));
the admin panel can override their names, descriptions, starting stats, MP costs, spell
icons, prices, power and messages per server.

The config file is plain Lua evaluated in a sandbox (no `io`, `os`, `require` or `load`).

## Themes and font

Players pick a look in the footer of every page ("Theme: Default · Retro"); the choice is
a cookie (`dk_theme`, one year), so it works logged in or out and needs no account.

- **Default**: new artwork, a light snow background and the red-dragon "Dragon Knight"
	logo, with dark red links.
- **Retro**: the original 2006 background, logo and colours.

Themes only change images and colours: the three-column layout is the same. A theme is a
stylesheet in `public/css/themes/`, its images in `public/images/themes/<key>/` and an
entry in `app/lib/themes.lua`; see `docs/APP.md`, "Themes".

The whole site, in every theme, is set in [Vollkorn](https://github.com/FAlthausen/Vollkorn-Typeface)
by Friedrich Althausen (`public/fonts/vollkorn/`, Regular, Italic, Bold and Bold Italic),
licensed under the SIL Open Font License 1.1 (`public/fonts/vollkorn/OFL.txt`).

Server tuning keys (the defaults suit a small server; see `docs/PERF.md`):

| Key | Default | |
|---|---|---|
| `workers` | `0` | worker threads; 0 = one per CPU the process may use, at least 2 |
| `spares` | `0` | Lua VMs in the pool; 0 = workers + 1 |
| `queue_timeout_ms` | `2000` | a request that waited longer for a worker gets a fast `503` with `Retry-After: 1` (0 = never) |
| `access_log` | `true` | one log line per request, written by a background thread; `false` turns them off |
| `stats_socket` | next to the database | Unix socket `dk stats` reads; `""` = none |
| `static_cache_bytes` / `static_cache_file_max` | 8 MiB / 256 KiB | static files kept in memory; larger ones are sent with `sendfile` |
| `vm_memory_limit` | 256 MiB | address space per Lua VM: a request needing more Lua memory fails with a 500 |
| `vm_gc_pause` | `1000` | Lua GC pause (%) of request VMs |
| `db_cache_kb` / `db_mmap_bytes` | 8192 / 0 (off) | SQLite page cache and memory-mapped I/O per connection |
| `db_checkpoint_ms` | `1000` | background WAL checkpoint interval (0 = SQLite's automatic checkpoints in requests) |

Event streams (`GET /live`, see below):

| Key | Default | |
|---|---|---|
| `max_streams` | `512` | open event streams in all; one more gets `503` with `Retry-After: 5` (0 = streams off) |
| `max_streams_per_ip` | `8` | open event streams per client address (0 = no limit); behind a reverse proxy every client has the proxy's address, so raise it there |
| `stream_queue_bytes` | 256 KiB | a stream with more unsent bytes than this (after the socket took what it could) is not reading: it is closed |
| `stream_heartbeat_ms` | `15000` | a `: ping` comment on streams that had nothing else for half that long (0 = none) |
| `stream_replay_events` / `stream_replay_seconds` | 200 / 300 | events kept per channel so a reconnecting client (`Last-Event-ID`) gets what it missed (0 = no replay: it is told to resync) |

Events are numbered `<boot>-<n>` (`boot` is random per server start), so a client that
reconnects after a restart, or after its missed events were dropped, gets an
`event: resync` instead of a replay. Streams are exempt from `keepalive_timeout` and
`request_timeout`; at shutdown each gets `event: bye` before it is closed. Behind nginx,
`X-Accel-Buffering: no` (sent by dk) turns off buffering for the stream; give the proxy a
read timeout longer than the heartbeat.

**`GET /live`** (logged-in players): the player's event stream with the channels
`babble`, `presence`, `notices`, `user:<id>` (their own) and, for administrators,
`admin`. `public/js/live.js` opens one per browser (its tabs share it) and keeps the page
live: the Babble Box (the chat, in the right column of every game page), who's online,
toasts for news posts and replies in your forum threads, and the broadcast banner
(`/admin/broadcast`); a logout or password change closes the pages' streams. Without
JavaScript the same parts work with forms and page loads. The event catalogue and how to
add a live feature are in `docs/APP.md`, "Realtime".

Who's online counts a player while they have a live page open or made a request within
`online_seconds` (app-level key, default 600); departures are checked every
`presence_sweep_seconds` (default 60) by the first request after that. The app-level key
`test_routes = true` adds `POST /__test/publish` (publish an event as any logged-in user)
and the `X-Test-Seed` request header (seeds the dice) for the end-to-end tests and the
realtime benchmark; never set it on a real server.

**Smooth fights**: on the fight pages `public/js/fight.js` sends the fight's forms with
`fetch` (`Accept: application/json`); the same routes answer with the round as a list of
events (each line of the fight page with the HP, MP, statuses and allies it changed) and
the page's parts rendered by the same templates, and the script plays the round line by
line (click or any key to skip; no delays with reduced motion) before swapping them in.
Every fight form carries its round number, so a double click or an old tab plays nothing.
Without JavaScript the fight pages are the same forms and page loads. The JSON shape is in
`docs/APP.md`, "Fight API".

## Deployment

A server needs only the `dk` binary, `app/`, `templates/`, `public/` and a `config.lua`;
the game writes to `data/` (database, mail outbox, backups). The binary has to be built
for the server's OS and CPU: build on the same kind of machine (or on the server).

**Release tarball.** `make dist` builds an optimized binary (in `build/release/`, apart from
the development build) and packs `dist/dk-VERSION-OS-ARCH.tar.gz` with a `dk-VERSION/`
directory: `dk`, `app/`, `templates/`, `public/`, `config.example.lua`, `README.md`,
`LICENSE`. It never contains a `config.lua` or `data/`.

**`make deploy`** installs the working tree into a directory, locally or over ssh:

```sh
make deploy DEST=/srv/dk                                   # local directory
make deploy DEST=dk@game.example.org:/srv/dk RESTART='sudo systemctl restart dk'
make deploy DEST=game:dk CONFIG=prod.lua                   # ~/dk on host "game"
```

It builds the release binary and runs `dk check` on the working tree, then copies the
binary (under a temporary name, renamed into place, so a running server is never handed
a half-written file), syncs `app/`, `templates/` and `public/` (deleting files that are
gone from them) and copies `config.example.lua`, `README.md` and `LICENSE`. Nothing else
in DEST is touched: not `config.lua`, not `data/`. In DEST it then runs `./dk check`,
`./dk backup` and `./dk migrate` with `--config CONFIG` (default `config.lua`, relative
to DEST), and finally `RESTART` if given. DEST is remote when it has a `:` before its
first `/` (as with `rsync` and `scp`); remote steps run over `ssh`, and `rsync` is needed
on both machines. If the server's `uname -sm` differs from this machine's, the binary is
not copied (with a warning) and the server keeps its own. The deployment assumes the
default `app_dir`, `template_dir` and `public_dir`.

First-time setup on the server, after a first `make deploy` (which stops with these
steps because there is no database yet):

```sh
cd /srv/dk
cp config.example.lua config.lua      # set secret, dev = false, cookie_secure, bind/port
./dk install --admin admin admin@example.com 'a-good-password'
./dk serve                            # or the systemd unit: deploy/dk.service
```

[`deploy/dk.service`](deploy/dk.service) is an example systemd unit: a dedicated `dk`
user, `WorkingDirectory=/srv/dk`, `Restart=on-failure`, and sandboxing that leaves only
`/srv/dk/data` writable. Deploy as that user (`DEST=dk@host:/srv/dk`) so the files and
the database keep one owner.

**Upgrades** are the same `make deploy DEST=... [RESTART=...]`: sync, check, back up,
migrate. Lua and template changes are live as soon as the files land (hot reload), so
no restart is needed for them; a changed binary runs after a restart (the script says
which case it is). The files land before the migration runs: in between, if the new
code expects a newer schema, requests get the "run `dk migrate`" 503 page rather than
new code running against the old schema. Each deploy leaves a backup in
`data/backups/`; to restore one, stop the server and copy it over `data/dk.db`
(removing `data/dk.db-wal` and `data/dk.db-shm`).

On a server that builds from a source checkout instead, `make` then `make migrate`
does the same check, backup and migration.

## Make targets

| Target | |
|---|---|
| `make` | build `./dk` (objects in `build/`) |
| `make run [PORT=8080] [BIND=addr] [CONFIG=config.lua]` | build and serve in the foreground; first use creates the config and installs the game (admin / admin), an old database is backed up and migrated (see [Quick start](#quick-start)) |
| `make test` | lint, C unit tests, Lua unit tests and end-to-end tests |
| `make lint` | check tab indentation |
| `make bench [BENCH_SCENARIO=mixed]` | release build + `tools/dkbench`, then load a temporary install with scripted keep-alive clients and print latency percentiles, req/s and server CPU/RSS (`pages`, `fights`, `static`, `mixed`, `idle`, `realtime` — 1,000 event streams and the fan-out latency of published events —, `realtime-mixed` — the target scale: 1,000 idle players with streams, 50 active ones playing (form and JSON fights), chat, reconnects —, `soak` — the same for an hour (`BENCH_SECONDS`), sampled every 30 s, with a pass/fail summary and a CSV —, or `all`; `BENCH_BUILD=dbg\|tsan` serves with the ASan/UBSan or ThreadSanitizer build; see `docs/PERF.md`) |
| `make release` | optimized build in `build/release/dk` (`-O2`, no sanitizers) |
| `make dist` | release tarball `dist/dk-VERSION-OS-ARCH.tar.gz` |
| `make backup [CONFIG=config.lua]` | `./dk backup` |
| `make migrate [CONFIG=config.lua]` | `./dk check`, then `./dk backup`, then `./dk migrate`; stops at the first failure |
| `make migrate-status [CONFIG=config.lua]` | `./dk migrate --status` |
| `make deploy DEST=dir\|[user@]host:dir [CONFIG=config.lua] [RESTART='command']` | see [Deployment](#deployment) |
| `make clean` / `make distclean` | remove the objects and `./dk` / also `build/` and `dist/` |

Variables: `BUILD=dir` (object dir), `BIN=path` (binary), `DEBUG=1` (`-O0 -g`,
ASan/UBSan, malloc counting), `TSAN=1` (ThreadSanitizer, with `CC=clang`), `CONFIG=path`, `DIST=dir` (where `make dist` writes), and for `make run`
`PORT`, `BIND`, `ADMIN_USER`, `ADMIN_EMAIL`, `ADMIN_PASS`.

## Development

- Edit `app/**/*.lua` or `templates/**/*.html` and refresh the browser.
- `./dk check` catches syntax errors in every module and template, and invalid content
	files.
- `make test` builds and runs the C unit tests, then `tests/run.sh`: a temporary copy of
	the app on a random port, Lua unit tests (`tests/lua/`), core end-to-end checks and the
	feature scripts in `tests/e2e/` (including a full playthrough and a concurrency check).
- `E2E_ONLY=town,fight tests/run.sh` runs only some feature scripts; `tests/run.sh -k`
	keeps the temp dir (database, server log) for inspection.
- `tests/e2e/quickstart.sh` covers `make run` and `dk serve --port/--bind`;
	`tests/e2e/backup.sh` and `tests/e2e/deploy.sh` cover `dk backup`, `make dist` and
	`make deploy` (to a temporary directory, and to a "remote" one through a stand-in
	`ssh`); the first run builds `build/release/dk`, and the deploy checks are skipped
	without `rsync`.
- `make DEBUG=1 test` builds with `-O0 -g` and AddressSanitizer/UndefinedBehaviorSanitizer;
	the e2e run fails on any sanitizer report in the server log.
- `make TSAN=1 CC=clang BUILD=build/tsan BIN=build/tsan/dk ctest` builds and runs the C
	unit tests under ThreadSanitizer (`make ctest`: just the C tests).
- `make BUILD=build/x BIN=build/x/dk` keeps objects and the binary in a separate
	directory (parallel checkouts, CI); run its tests with `BIN=build/x/dk tests/run.sh`.
- The C code builds warning-free with `-Wall -Wextra`. Lua code uses no globals (in Lua
	5.5 `global` is a reserved word). The project indents with tabs.

## Adding a class, a spell, an item or a monster

Character classes are data files, `app/content/classes/<key>.lua` (Mage, Warrior and
Paladin are `mage.lua`, `warrior.lua`, `paladin.lua`). Copy one to a new name (the file
name is the class's permanent key: lowercase letters, digits and `_`), change the name,
description, starting stats, first experience step (`exp_base`; the rest of the curve is
global unless the class sets its own `exp_stages`) and per-level gains, and run
`./dk check`. Every kind of content file may also have `lore`: a few lines of story (a
blank line between paragraphs, at most 2,000 characters) shown in the entry's tooltip and on
the help pages, which administrators can override. The running game picks the file up on the
next page load and offers the class at registration (its name there has a tooltip with its
points and lore); on another server, deploy it like any code change. Deleting a file retires
the class (no longer offered; its characters keep it).

### Adding a spell

Spells are content files too, `app/content/spells/<key>.lua`, and *scripted*: the numbers
and texts are data (name, description, MP cost, `power`, messages; synced into the
database and overridable in the admin panel), and what the spell does is a Lua function,
`cast`, written against a small action API (a `caster` and a `target` with `:heal`,
`:hurt`, `:buff`, `:sleep`, `:afflict` for statuses, dice with `s:roll`, lines with
`s:say`). A copy of `hurt.lua` with other numbers is a new damage spell:

```lua
-- app/content/spells/firebolt.lua
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll(s.power // 2, s.power)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Firebolt",
	description = "Burns the monster. Some monsters are immune.",
	mp = 8,
	power = 24,
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
	},
	cast = cast,              -- or inline: cast = function(s) ... end
}
```

A class learns it when a class file lists its key in `levels[N].spells`. `heal.lua` shows
a self-targeted spell usable in town with a refusal (`can_cast`, "already full"). In fights
and in the Fast Spells box a spell is an icon button: give it `icon = "firebolt"` and put
`firebolt.png` (square) in `public/images/skills/`, or leave it out for `default.png`;
`./dk check` fails, naming the spell file, if the PNG doesn't exist. Its buttons get a
tooltip by themselves (name, MP cost, where it can be cast, `description` and `lore`), so
write the description as what the spell does and the lore as its story. The
formats, the action API, the sync and the admin overrides are described in `docs/APP.md`
("Content", "Scripting spells and items", "Spells", "Items").

### Adding an item

Items are data files too, `app/content/items/<key>.lua` (the original weapons, armor and
shields, the monster drops as accessories, and the Herb, Potion and Ether). Copy one
(`herb.lua` for a potion-like item, `stick.lua` for a weapon, `life_pebble.lua` for a
drop) and set its name, category (`weapon`, `armor`, `shield`, `accessory`, `consumable`,
`quest` or `misc`), price, attack or defense, modifiers while equipped (for example
`modifiers = { { kind = "stat", stat = "maxhp", amount = 50 } }`) and how many stack in
one bag slot (`max_stack`). A consumable is scripted like a spell: `power`, messages and a
`use` function (see `herb.lua` and `potion.lua`, and `docs/APP.md`, "Scripting spells and
items"). Give it a
`drop_level` for monsters of that level and up to drop it, or add its key to a town's shop
in the admin town editor. `./dk check` validates it; the next page load picks it up. Its `description` and `lore` show
in its tooltip (with its stats) wherever the item is listed: the Inventory panel, the
Inventory page, the shops and the purchase page; and on `/help/items`.

### Adding a status or a summon

Effects that last several turns are **statuses**, `app/content/statuses/<key>.lua`: a
name, a duration, when they tick, whether they keep the bearer from acting, and Lua hooks
(`on_tick`, `on_apply`, `modify_damage_taken`, ...). Spells and items apply them by key
(`s.target:afflict("poison", { turns = 3 })`); applying one again replaces it. Allies are
**summons**, `app/content/summons/<key>.lua` (HP, attack, defense and an `act` function),
called with `s:summon("wolf", { turns = 5 })`. Copy `poison.lua` or `wolf.lua` to start;
`hyper_beam.lua` and `solar_beam.lua` show actions over two turns (recharge, charge). See
`docs/APP.md`, "Fight engine".

### Adding a monster

Monsters are data files too, `app/content/monsters/<key>.lua` (the original 151 keep
their ids and only attack). Copy one and set its name, level (where it is met and what it
drops), maximum HP, damage and armor, rewards, immunity and MP (`maxmp`). A monster can
also carry equipment (`equipment = { weapon = "broadsword" }`: the items' attack, defense
and modifiers count like a character's), use consumables (`items`, with a stock per
encounter) and cast spells (`spells`; `uses_mp = false` makes them free). Each turn it
picks by weight among its attack (`attack_weight`) and what it may use now; a `when`
function (inline or free-standing) can make an entry depend on the fight:

```lua
-- app/content/monsters/goblin_shaman.lua (excerpt)
local function low_hp(m) return m.hp < m.maxhp // 3 end

return {
	name = "Goblin Shaman", level = 5, maxhp = 40, maxdam = 8, armor = 4, maxexp = 12, maxgold = 15,
	maxmp = 17, attack_weight = 3,
	roams = false,                    -- not met at random (default true)
	equipment = { weapon = "dagger" },
	spells = {
		{ spell = "hurt", weight = 2 },
		{ spell = "heal", weight = 3, when = function(m) return m.hp < m.maxhp // 2 end },
	},
	items = { { item = "potion", weight = 4, stock = 2, when = low_hp } },
}
```

`./dk check` validates it (unknown keys, an item in the wrong slot, ...); the next page
load picks it up, and a roaming monster is met at random in its level band. Its name on the
fight page has a tooltip (level, `description`, `lore`), and `/help/monsters` shows its lore.

Tooltips work on anything: an element with `data-tip` and a `<template class="tip">` child
(or `data-tip="text"`) gets one, placed inside the window, on hover, keyboard focus or a long
press (`public/js/tooltip.js`; see `docs/APP.md`, "Tooltips" and "Lore"). See
`docs/APP.md`, "Monsters".

## Project layout

```
src/            C engine: http, vmpool, codecache, tmpl, config, crypto, util, Lua/SQLite bindings, backup, CLI
app/            Lua application
  main.lua        request entry point (sessions, routing, CSRF, errors)
  routes/         route registration per area
  lib/            router, session, csrf, auth, view, game helpers, PHP-compatible helpers, mail
  town/ fight/ community/ admin/   feature modules
  content/        content files: classes/, spells/, items/, statuses/, summons/, monsters/ (one Lua file each: data, plus code for spells, consumables, statuses and summons, conditions for monsters), synced into the DB
  install.lua, cli/, sql/          `dk install`, `dk user`, `dk migrate`, `dk content`, schema and seed data
templates/      HTML templates (layout/, auth/, home/, town/, fight/, community/, admin/, errors/)
public/         static files served at /static/ (css/ with themes/, js/, images/ with themes/, fonts/vollkorn/)
scripts/        run.sh (`make run`), deploy.sh (`make deploy`)
tools/          dkbench.c (load generator) and bench.sh (`make bench`)
deploy/         dk.service (example systemd unit)
tests/          c/ (C unit tests), lua/ (Lua unit tests), run.sh + e2e/ (end-to-end), fixtures/
vendor/         Lua 5.5.1 and SQLite 3.54.1, unmodified (see vendor/VERSIONS)
docs/APP.md     app developer guide
docs/PERF.md    performance: how to measure, baseline and results
PLAN.md         design notes: engine API, URL map, data model
```

## Security notes

- All SQL uses bound parameters; the few dynamic identifiers come from whitelists.
- Templates escape output by default; user text is stored raw and escaped on display.
- Passwords are PBKDF2-HMAC-SHA256 (210,000 iterations by default, random salt); older
	hashes are upgraded on the next login.
- Server-side sessions: the `dk_session` cookie holds 32 random bytes (HttpOnly,
	SameSite=Lax, `Secure` with `cookie_secure`); the database stores only its SHA-256.
	Changing or resetting a password ends all of the user's sessions.
- Every POST needs a CSRF token: the per-session token when logged in, an HMAC-signed
	double-submit cookie (keyed by `secret`) on the login/registration forms.
- Every action that changes the game is a POST. The GETs that change state (opening a
	fight, collecting a victory) are one-shot by game state, and HEAD never writes.
- The static file server rejects path traversal; request size and time limits are
	configurable. Set `dev = false` in production to hide tracebacks.

## Differences from the original

The full version history, including the original 2003–2006 changelog, is on the
in-game `/changelog` page (also linked from the version number in the footer).

- Clean URLs (`/inn`, `/shop/buy/3`, `/forum/thread/7`, …) and HTML5/CSS markup with the
	original images and layout.
- Two themes (2.3): Default, with new artwork, and Retro, the original background and logo,
	chosen in the page footer; the whole site uses the Vollkorn typeface (15px) instead of
	11px Verdana, with slightly wider side columns.
- PBKDF2 password hashes, server-side sessions and CSRF tokens instead of the original
	cookie scheme; escaping and parameterized SQL throughout.
- Email (registration verification, lost password) is written as `.eml` files to the
	outbox directory instead of being sent; email verification is off by default.
- Installation and upgrades are the `dk install`, `dk migrate` and `dk backup` commands
	(and `make deploy`); there is no web installer.
- The admin "page compression" setting is gone (the server doesn't gzip).
- There are no difficulty levels: everyone plays at the original Easy difficulty (no
	multiplier on monster HP, damage, experience or gold).
- The experience needed per level, the TP gained per level and the HP bonus every tenth
	level (and at 99) are formulas fitted to the original level table (`app/lib/leveling.lua`;
	the Mage's experience within 0.44% of it, TP and HP exactly), no longer columns of the
	levels table.
- Character classes are content files (`app/content/classes/`) instead of the levels table
	and the class names in the settings: classes can be added without code changes, and
	administrators override names, descriptions, availability and starting stats per
	server (`/admin/classes`). All classes share the Mage's experience curve, scaled by
	their own first step (Warrior and Paladin need up to about 10% more experience than in
	the original from level 45 and 18 on); a class can define its own curve.
- Tooltips (2.4) on the spell buttons, the fight menu's Attack and Run icon buttons, items
	in the Inventory panel, on the Inventory page and in the shops, the monster you fight and
	the classes at registration, and lore for classes, spells, items, monsters, statuses and
	summons (in the tooltips and on the help pages).
- Spells are content files too (`app/content/spells/`), scripted in Lua instead of a type
	and an attribute (the original 19 behave exactly as before); administrators override
	names, descriptions, MP costs, power, icons and messages per server (`/admin/spells`). The
	spells a character knows are a table (`user_spells`) instead of a list in the users row.
	Spells are icon buttons (2.3.1) in the fight menu and the Fast Spells box, with their MP
	cost and greyed out when the MP don't cover them, instead of a drop-down list.
- Items and drops are content files (`app/content/items/`): the drops are accessories
	(three accessory slots, as the three inventory slots were), and there are consumables:
	Herbs, Potions and Ethers, sold in towns and usable in town or in fights (taking the
	turn). Administrators override names, prices, power, modifiers and drop levels per
	server (`/admin/items`); the town editor lists a shop's items by key.
- Fights are rounds (2.2): your turn, your allies', each monster's, then effects that last
	several turns tick and run out. Spells and items can poison, regenerate, put anyone to
	sleep, make you charge or recharge a powerful spell, or call an ally that fights at your
	side (and that monsters may attack instead of you); the fight page shows them, and a
	turn you can't act in offers only "Continue". Some effects (a Regen Potion) also last
	outside fights, a few moves at a time. Fights without them play exactly as before.
- Monsters are content files (`app/content/monsters/`): administrators override their
	stats per server (`/admin/monsters`), and monsters have magic points and can carry
	equipment, use items and cast spells, chosen by weight (the original monsters only
	attack, exactly as before; three new ones, not met at random, show the rest).
- An inventory: besides what is equipped, a bag of 12 slots (a stack counts once; quest
	items don't count; size in the settings) with an Inventory page to equip, take off, use
	and discard items. Buying a weapon, armor or shield offers to keep the old one in the bag
	or sell it; shops buy back bag items for half their price; a monster's drop goes into
	the bag (or is left behind) instead of replacing an inventory slot's item.
- Character stats are derived: the database keeps base stats (grown by level-ups) and the
	equipped items add theirs, instead of adding and subtracting item bonuses on every
	change.
- The Babble Box is a live chat (2.3) in the right column of every game page instead of an
	iframe in towns (at most one message per 2 seconds; administrators can delete
	messages), and who's online, news, replies to your forum threads and the
	administrator's broadcast banner show up on open pages as they happen.
- Fights play a round in place (2.3, with JavaScript): the lines appear one by one with the
	HP and MP bars and the statuses changing, then the page updates without a reload; a
	second click or an old tab no longer plays an extra round.
- The built-in forum is only available when the forum type is set to "Internal". It has
	boards (`/forum/1`, …): General, and News, where only administrators start threads.
- News posts have a title and an author, and posting one also starts its discussion thread
	in the News board. The town shows the first paragraph of the latest post with "Read
	more" and the reply count; `/news` lists every post.
- Gameplay fixes:
	- Bris sells its full item list.
	- In the shop, the sell-back value of the item you replace counts toward the price.
	- Heal spells can't be cast when HP is at or above the maximum, in town or in a fight
		(no MP spent, and in a fight the monster doesn't act).
	- Running away can fail: the monster blocks you, attacks, and the damage counts (a
		fatal blow is a normal death). A successful run ends the fight.
	- Damage/defense spell buffs end with the fight (on running away and on death too).
	- The gold bonus is a percentage of the gold gained (it was of the experience), and the
		gold cap warning talks about gold.
	- Dying on a spell turn keeps the MP spent.
	- A victory grants every level its experience covers ("You have gained N levels!").
	- Any equipment change clamps current HP/MP/TP to the new maxima.
	- "This monster has dropped an item" only shows when there is an item.
	- The character sheet shows the experience for level 100 at level 99.
	- Spells of an unknown type are refused in fights.
	- Strength and dexterity from items count toward attack and defense power whatever the
		slot (stats are derived from the equipment).

	Other fixes of crashes or exploits are commented in the code (`fixed: …`); harmless
	quirks of the original are kept (`legacy: …`).

## License

The Vollkorn font files in `public/fonts/vollkorn/` are Copyright 2017 The Vollkorn Project
Authors and licensed under the SIL Open Font License, Version 1.1 (`public/fonts/vollkorn/OFL.txt`).
Everything else:

MIT License

Copyright (c) 2017 renderse7en

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
