# Dragon Knight

A browser RPG inspired by *Dragon Warrior* for the NES: explore a map, fight monsters,
level up, collect drops, buy gear and maps in towns, chat in the babble box and the forum.

This is a rewrite of **Dragon Knight 1.1.11** (originally PHP/MySQL by renderse7en,
released 3/26/2006) as a single self-contained program: a small HTTP server written in C
that runs the game logic in Lua and stores everything in SQLite. Game mechanics, data,
messages and the three-column look are kept as in the original.

- Original project: [renderse7en/dragon-knight](https://github.com/renderse7en/dragon-knight)
	(the PHP source is also in this repository's history, on `master`).
- See also: [Dragon Scourge](https://github.com/renderse7en/dragon-scourge)
- [Original live demo](http://dragon.se7enet.com/)

## Architecture

- **One binary, `./dk`.** A hand-written HTTP/1.1 server (one `poll()` I/O thread with
	keep-alive and pipelining, a pool of worker threads, static files under `/static/` with
	`Last-Modified`/304). Lua 5.5.1 and SQLite 3.54.1 are vendored under `vendor/` and
	compiled in, unmodified. Nothing else is needed at runtime.
- **A fresh Lua VM per request**, share-nothing like PHP. A warmer thread keeps a pool of
	pre-built spare VMs (libraries, `dk` API, config and app modules already loaded), so a
	request never pays for VM construction; used VMs are closed off the request path.
- **Bytecode cache + hot reload.** Lua modules and templates are compiled once and cached
	as bytecode. An inotify watcher on `app/`, `templates/` and the config file drops the
	cache and retires stale spare VMs, so an edit shows up on the next browser refresh, with
	no rebuild or restart.
- **Templates** (`templates/**/*.html`) are compiled to Lua by the C side:
	`{{ expr }}` (HTML-escaped), `{{{ expr }}}` (raw), `{% lua statements %}`,
	`{# comments #}`, with `-` trim markers. Errors report `template:line`.
- **SQLite** (WAL), one connection per worker. Every request runs in one transaction
	(`BEGIN IMMEDIATE … COMMIT`, rolled back on any error), so game updates are atomic.

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
| `dk install [--admin USER EMAIL PASS] [--charname NAME] [--class ID\|KEY] [--partial] [--force]` | create the schema, load the default game data, sync the content files and create the administrator (`--class`: by id or key, default 1 / `mage`; `--partial`: no game data except the classes and spells; `--force`: drop existing tables first) |
| `dk migrate [--status]` | upgrade an existing database to the current schema and sync the content files, in one transaction (`--status`: show the versions only). Until it runs, the game answers every page with a 503 "run `dk migrate`" page |
| `dk content sync` | load and validate the content files (`app/content/`) and update the database now (the running game does this by itself on the next request after a file changes); fails, changing nothing, when a file is invalid |
| `dk content status` | content files, database rows (and retired ones) and admin overrides per kind, whether the database is in sync, and any errors |
| `dk backup [OUTPUT]` | copy the database, safely while `dk serve` runs (SQLite backup API, one consistent snapshot), check the copy with `PRAGMA integrity_check` and print its path. OUTPUT defaults to `<db dir>/backups/<db name>-YYYYMMDD-HHMMSS.db` (UTC); an existing file is never overwritten. Exit status 3 if the database does not exist |
| `dk user list` | list accounts |
| `dk user passwd USER NEWPASS` | set a password (ends the user's sessions) |
| `dk user admin USER` | make a user an administrator |
| `dk check` | compile every Lua module and template, build a VM and validate the content files; non-zero exit on error (naming the file) |
| `dk version` | print the version and the Lua/SQLite versions |

## Configuration

`config.example.lua` documents every key. Server keys (`bind`, `port`, `workers`,
`spares`, paths, request limits) are read at startup. App keys (`dev`, `secret`,
`pbkdf2_iterations`, `cookie_secure`) are re-read for every fresh VM, so they apply on the
next request. Game settings (game name, map size, forum, email verification, …) live in
the database and are edited in the admin panel at `/admin`. Character classes and spells
are content files (see [Adding a class or a spell](#adding-a-class-or-a-spell)); the admin
panel can override their names, descriptions, starting stats, MP costs and effect amounts
per server.

The config file is plain Lua evaluated in a sandbox (no `io`, `os`, `require` or `load`).

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
| `make release` | optimized build in `build/release/dk` (`-O2`, no sanitizers) |
| `make dist` | release tarball `dist/dk-VERSION-OS-ARCH.tar.gz` |
| `make backup [CONFIG=config.lua]` | `./dk backup` |
| `make migrate [CONFIG=config.lua]` | `./dk check`, then `./dk backup`, then `./dk migrate`; stops at the first failure |
| `make migrate-status [CONFIG=config.lua]` | `./dk migrate --status` |
| `make deploy DEST=dir\|[user@]host:dir [CONFIG=config.lua] [RESTART='command']` | see [Deployment](#deployment) |
| `make clean` / `make distclean` | remove the objects and `./dk` / also `build/` and `dist/` |

Variables: `BUILD=dir` (object dir), `BIN=path` (binary), `DEBUG=1` (`-O0 -g`,
ASan/UBSan), `CONFIG=path`, `DIST=dir` (where `make dist` writes), and for `make run`
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
- `make BUILD=build/x BIN=build/x/dk` keeps objects and the binary in a separate
	directory (parallel checkouts, CI); run its tests with `BIN=build/x/dk tests/run.sh`.
- The C code builds warning-free with `-Wall -Wextra`. Lua code uses no globals (in Lua
	5.5 `global` is a reserved word). The project indents with tabs.

## Adding a class or a spell

Character classes are data files, `app/content/classes/<key>.lua` (Mage, Warrior and
Paladin are `mage.lua`, `warrior.lua`, `paladin.lua`). Copy one to a new name (the file
name is the class's permanent key: lowercase letters, digits and `_`), change the name,
description, starting stats, first experience step (`exp_base`; the rest of the curve is
global unless the class sets its own `exp_stages`) and per-level gains, and run
`./dk check`. The running game picks the file up on the next page load and offers the class
at registration; on another server, deploy it like any code change. Deleting a file retires
the class (no longer offered; its characters keep it).

Spells work the same way: `app/content/spells/<key>.lua` holds a spell's name,
description, MP cost, where it can be cast and its effects (heal, damage, sleep, attack or
defense buffs), for example `effects = { { kind = "damage", max = 20 } }`. A class learns
it when a class file lists its key in `levels[N].spells`. The formats, the sync and the
admin overrides are described in `docs/APP.md` ("Content", "Spells").

## Project layout

```
src/            C engine: http, vmpool, codecache, tmpl, config, crypto, util, Lua/SQLite bindings, backup, CLI
app/            Lua application
  main.lua        request entry point (sessions, routing, CSRF, errors)
  routes/         route registration per area
  lib/            router, session, csrf, auth, view, game helpers, PHP-compatible helpers, mail
  town/ fight/ community/ admin/   feature modules
  content/        content files: classes/, spells/ (one Lua data file each), synced into the DB
  install.lua, cli/, sql/          `dk install`, `dk user`, `dk migrate`, `dk content`, schema and seed data
templates/      HTML templates (layout/, auth/, home/, town/, fight/, community/, admin/, errors/)
public/         static files served at /static/ (css/, js/, images/)
scripts/        run.sh (`make run`), deploy.sh (`make deploy`)
deploy/         dk.service (example systemd unit)
tests/          c/ (C unit tests), lua/ (Lua unit tests), run.sh + e2e/ (end-to-end), fixtures/
vendor/         Lua 5.5.1 and SQLite 3.54.1, unmodified (see vendor/VERSIONS)
docs/APP.md     app developer guide
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
- Spells are content files too (`app/content/spells/`), with a list of effects instead of
	a type and an attribute; administrators override names, descriptions, MP costs and
	effect amounts per server (`/admin/spells`). The spells a character knows are a table
	(`user_spells`) instead of a list in the users row.
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
	- Equipping a drop into an empty slot clamps current HP/MP/TP to the new maxima.
	- "This monster has dropped an item" only shows when there is an item.
	- The character sheet shows the experience for level 100 at level 99.
	- Spells of an unknown type are refused in fights.
	- Shop items with a strength/dexterity special update attack/defense power whatever
		the slot.

	Other fixes of crashes or exploits are commented in the code (`fixed: …`); harmless
	quirks of the original are kept (`legacy: …`).

## License

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
