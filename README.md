# Dragon Knight

A browser RPG inspired by *Dragon Warrior* for the NES: explore a map, fight monsters,
level up, collect drops, buy gear and maps in towns, chat in the babble box and the forum.

This is a rewrite of **Dragon Knight 1.1.11** (originally PHP/MySQL by renderse7en,
released 3/26/2006) as a single self-contained program: a small HTTP server written in C
that runs the game logic in Lua and stores everything in SQLite. Game mechanics, data,
messages and the three-column look are kept as in the original.

- Original project: [renderse7en/dragon-knight](https://github.com/renderse7en/dragon-knight)
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
make                                   # builds ./dk
cp config.example.lua config.lua       # then edit: port, paths, secret, dev = false
./dk install --admin admin admin@example.com 'a-good-password'
./dk serve                             # http://127.0.0.1:8080/
```

`dk install` prints a random `secret` if the config has none; paste it into `config.lua`.
The database and the mail outbox go to `data/` by default. Serve over HTTPS through a
reverse proxy in production and set `cookie_secure = true`.

## Command line

Every command accepts `--config PATH` (default `./config.lua`).

| Command | |
|---|---|
| `dk serve` | run the HTTP server |
| `dk install [--admin USER EMAIL PASS] [--charname NAME] [--class 1-3] [--difficulty 1-3] [--partial] [--force]` | create the schema, load the default game data and create the administrator (`--partial`: no game data; `--force`: drop existing tables first) |
| `dk user list` | list accounts |
| `dk user passwd USER NEWPASS` | set a password (ends the user's sessions) |
| `dk user admin USER` | make a user an administrator |
| `dk check` | compile every Lua module and template and build a VM; non-zero exit on error |
| `dk version` | print the version and the Lua/SQLite versions |

## Configuration

`config.example.lua` documents every key. Server keys (`bind`, `port`, `workers`,
`spares`, paths, request limits) are read at startup. App keys (`dev`, `secret`,
`pbkdf2_iterations`, `cookie_secure`) are re-read for every fresh VM, so they apply on the
next request. Game settings (game name, map size, forum, email verification, class and
difficulty names, …) live in the database and are edited in the admin panel at `/admin`.

The config file is plain Lua evaluated in a sandbox (no `io`, `os`, `require` or `load`).

## Development

- Edit `app/**/*.lua` or `templates/**/*.html` and refresh the browser.
- `./dk check` catches syntax errors in every module and template.
- `make test` builds and runs the C unit tests, then `tests/run.sh`: a temporary copy of
  the app on a random port, Lua unit tests (`tests/lua/`), core end-to-end checks and the
  feature scripts in `tests/e2e/` (including a full playthrough and a concurrency check).
- `E2E_ONLY=town,fight tests/run.sh` runs only some feature scripts; `tests/run.sh -k`
  keeps the temp dir (database, server log) for inspection.
- `make DEBUG=1 test` builds with `-O0 -g` and AddressSanitizer/UndefinedBehaviorSanitizer;
  the e2e run fails on any sanitizer report in the server log.
- `make BUILD=build/x BIN=build/x/dk` keeps objects and the binary in a separate
  directory (parallel checkouts, CI); run its tests with `BIN=build/x/dk tests/run.sh`.
- The C code builds warning-free with `-Wall -Wextra`. Lua code uses no globals (in Lua
  5.5 `global` is a reserved word). The project indents with tabs.

## Project layout

```
src/            C engine: http, vmpool, codecache, tmpl, config, crypto, util, Lua/SQLite bindings, CLI
app/            Lua application
  main.lua        request entry point (sessions, routing, CSRF, errors)
  routes/         route registration per area
  lib/            router, session, csrf, auth, view, game helpers, PHP-compatible helpers, mail
  town/ fight/ community/ admin/   feature modules
  install.lua, cli/, sql/          `dk install`, `dk user`, schema and seed data
templates/      HTML templates (layout/, auth/, home/, town/, fight/, community/, admin/, errors/)
public/         static files served at /static/ (css/, js/, images/)
tests/          c/ (C unit tests), lua/ (Lua unit tests), run.sh + e2e/ (end-to-end)
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

- Clean URLs (`/inn`, `/shop/buy/3`, `/forum/thread/7`, …) and HTML5/CSS markup with the
  original images and layout.
- PBKDF2 password hashes, server-side sessions and CSRF tokens instead of the original
  cookie scheme; escaping and parameterized SQL throughout.
- Email (registration verification, lost password) is written as `.eml` files to the
  outbox directory instead of being sent; email verification is off by default.
- Installation and upgrades are the `dk install` command; there is no web installer.
- The admin "page compression" setting is gone (the server doesn't gzip).
- The built-in forum is only available when the forum type is set to "Internal".
- Gameplay fixes: Bris sells its full item list; when buying in a shop, the sell-back value
  of the item you replace counts toward the price; heal spells can't be cast when HP is
  already at or above the maximum. Other fixes of crashes or exploits are commented in
  the code (`fixed: …`); harmless quirks of the original are kept (`legacy: …`).

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
