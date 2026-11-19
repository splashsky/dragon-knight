# Dragon Knight → C + Lua rewrite plan

Branch: `c-lua-rewrite`. The original PHP 4 / MySQL game (v1.1.11) lives in `legacy/` as
the reference implementation and is deleted in the final phase.

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

## Repository layout (target)

```
Makefile              builds ./dk; `make test`; BUILD=dir for isolated object dirs
config.lua            runtime config (returned table); config.example.lua is committed
vendor/lua/           Lua 5.5.1 src/ (+ doc/manual.html — read §8 for 5.4→5.5 changes)
vendor/sqlite/        sqlite3.c / sqlite3.h amalgamation
vendor/VERSIONS       provenance + checksums
src/                  C engine (headers already written = contracts; see below)
  util.[ch]           sbuf, url/html encode, logging, time, read_file
  crypto.[ch]         sha256, hmac, pbkdf2, getrandom, ct_equal, hex
  tmpl.[ch]           template -> Lua source compiler
  config.[ch]         loads config.lua in a sandboxed throwaway state
  http.[ch]           poll() I/O thread + worker threads + static files
  codecache.[ch]      bytecode cache + inotify watcher + generation counter
  vmpool.[ch]         warm spare VMs, warmer/reaper thread
  bind.h              dk Lua API (bind_dk.c), SQLite binding (bind_db.c), db.c
  app.c               dk_hooks glue: worker_init opens DB; handle = acquire VM → bind_handle → release
  main.c              CLI: `dk serve`, `dk install`, `dk user`, `dk check`
app/                  Lua application (hot-reloaded)
  main.lua            returns handler(req) -> res
  routes.lua          route table assembly (requires route modules listed in it)
  lib/                router, session, auth, csrf, view, form, util, mail, game helpers
  game/               feature modules (town, explore, fight, heal, character, babble, ...)
  admin/              admin control panel modules
  install.lua         CLI: schema + seed data + admin user
  sql/schema.sql      SQLite schema
  sql/seed.sql        default game data ported 1:1 from legacy/install.php
templates/            *.html templates (hot-reloaded), organized by feature
public/               served at /static/ (images/, css/)
tests/c/              C unit tests (one main() per file, built by `make test`)
tests/run.sh          end-to-end smoke tests (bash + curl against a temp server)
data/                 runtime (gitignored): dk.db, outbox/
legacy/               original PHP (deleted at the end)
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
| `dk.vmstats()` | table of vmpool stats (debug page) |
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

The C side adds `Content-Length`, `Date`, `Server: dk`, `Connection`. Bodies other than
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

All state-changing actions are POST with a CSRF token; GETs never mutate except
`onlinetime` touch on authenticated requests (original behavior).

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
| `do=buy` / `buy2:id` / `buy3:id` | `GET /shop`, `GET /shop/buy/:id` (confirm), `POST /shop/buy/:id` |
| `do=sell` | (dead in legacy — towns.php has no `sell()`; omit) |
| `do=maps` / `maps2:id` / `maps3:id` | `GET /maps`, `GET /maps/buy/:id`, `POST /maps/buy/:id` |
| `do=gotown:id` | `POST /travel/:id` |
| `do=move` | `POST /move` (button name north/south/east/west) |
| `do=fight` / `victory` / `drop` / `dead` | `GET/POST /fight`, `GET /victory`, `GET/POST /drop`, `GET /dead` |
| `do=spell:id` | `POST /spell/:id` (heal spells out of combat) |
| `do=showchar` | `GET /character` (minimal layout, popup-friendly) |
| `do=onlinechar:id` | `GET /character/:id` |
| `do=showmap` | `GET /map` |
| `do=babblebox` | `GET/POST /babble` (iframe-able minimal page) |
| `do=ninja` | `GET /ninja` → 302 to the original shirt-ninja URL (keep the easter egg) |
| `forum.php` | `GET /forum`, `GET /forum/thread/:id[?start=n]`, `GET/POST /forum/new`, `POST /forum/reply/:id` |
| `help.php`, `help_items.php`, … | `GET /help`, `/help/items`, `/help/spells`, `/help/monsters`, `/help/levels` |
| `admin.php?do=…` | `/admin`, `/admin/settings`, `/admin/{items,drops,towns,monsters,spells,levels,users}[/:id]`, `/admin/news` |
| `install.php`, `upgrade_*.php` | `./dk install` CLI; upgrades dropped (fresh SQLite schema) |

Guard order for game routes (port of index.php header): not logged in → `/login`;
game closed → closed page; `verifyemail` on and not verified → `/verify`; banned
(authlevel 2) → blocked page.

## Data model

- Port every legacy table to SQLite without the `dk_` prefix: `babble, control, drops,
  forum, items, levels, monsters, news, spells, towns, users`, keeping column names so
  porting is mechanical. Add `sessions`.
- Times: store unix seconds INTEGER (`regdate`, `onlinetime`, `postdate`, `newpostdate`,
  `posttime`). Format in Lua.
- `users.password` = `pbkdf2$<iters>$<salt hex>$<hash hex>` (iters default 210000,
  overridable via `dk.config.pbkdf2_iterations` so tests can use a low value).
- `sessions(token_hash TEXT PRIMARY KEY, user_id INTEGER, csrf TEXT, created INTEGER,
  expires INTEGER, remember INTEGER)`. Cookie `dk_session=<random 32-byte hex>`,
  `HttpOnly; SameSite=Lax; Path=/`, `Max-Age` 1 year when "remember me", else a
  session cookie (server-side expiry 1 day, sliding). Store only `sha256(token)`.
- Seed data in `app/sql/seed.sql` must match `legacy/install.php` "complete setup"
  exactly (all rows of drops, items, levels, monsters, spells, towns, control).
- Email (registration verification, lost password) is written to
  `<outbox_dir>/<unix>-<rand>.eml` and logged; `control.verifyemail` defaults to 0.

## Mechanics fidelity

Game logic must match legacy PHP exactly. Helpers in `app/lib/php.lua`:

- `php.rand(min, max)`: PHP casts float args to int (truncate toward zero), and swaps if
  `min > max`; inclusive range via `math.random`.
- `php.ceil`, `php.number_format(n)`, `php.nl2br`, `php.prettydate(ts)` ("F j, Y").
- Preserve comma-list columns (`users.spells`, `users.towns`, `towns.itemslist`,
  `drops.attribute1/2` `"stat,value"` / `"X"`) and their semantics.
- Re-read legacy code for each feature; when legacy has an obvious bug that affects
  gameplay, keep the behavior unless it is a security hole, and note it in a comment.

## Coding rules (all agents)

- C11, `-Wall -Wextra` clean (warnings are bugs), no new dependencies, check every
  allocation and syscall result, no global mutable state without a mutex (except
  I/O-thread-only state). Keep functions small; comment only the non-obvious.
- Lua 5.5: `global` is a **reserved word**; for-loop control variables are **read-only**.
  Use `local` everywhere; modules return tables; no globals from app code.
- Never build SQL with string concatenation of user data. Always `?` params.
  (Identifiers like the level column `1_exp` may be chosen from a whitelist.)
- Templates escape by default; use `{{{ }}}` only for HTML built by trusted code.
- Do **not** `git commit` — the coordinator commits between phases.
- Use your own object dir (`make BUILD=build/<you>`), your own port, your own DB file
  and config (`./dk serve --config /tmp/opencode/<you>/config.lua`) to avoid colliding
  with parallel agents. Only edit files you own (listed in your task). If you need a
  change in someone else's file, say so in your final report.

## Phases

1. **Engine** (parallel):
   - **E1 — base**: `util.c`, `crypto.c`, `tmpl.c` + `tests/c/test_util.c`,
     `test_crypto.c` (NIST/RFC 4231/RFC 7914-style PBKDF2-SHA256 vectors),
     `test_tmpl.c` (compile → load in Lua → render).
   - **E2 — server**: `config.c`, `http.c` + `tests/c/test_http.c` (spins the server with
     a C handler on a random port, exercises keep-alive, pipelining, POST bodies,
     limits, static files, 304, traversal, slowloris timeout).
   - **E3 — runtime**: `codecache.c`, `vmpool.c`, `bind_dk.c`, `bind_db.c`, `db.c`,
     `app.c`, `main.c` + `tests/c/test_vmpool.c`, and a placeholder `app/main.lua` /
     `templates/hello.html` proving hot reload end-to-end.
2. **App foundation** (single agent): schema + seed, `dk install`, router, sessions,
   CSRF, auth pages, layout/nav templates, CSS, static assets, `app/lib/php.lua`, home
   dispatcher (town/explore views), stubs for phase-3 modules, `tests/run.sh`,
   `docs/APP.md` (conventions for feature authors).
3. **Features** (parallel): **F1 town/explore/heal/character/map/babble**, **F2 fight**,
   **F3 forum/help/news**, **F4 admin**.
4. **Integration & QA**: end-to-end playthrough script, mechanics review against legacy,
   hot-reload check, load check, README rewrite, `.gitignore`, delete `legacy/`.

## Definition of done

- `make && make test` green with `-Wall -Wextra` and no warnings; `make DEBUG=1 test`
  green under ASan/UBSan.
- `./dk install --admin <user> <email> <password>` then `./dk serve` gives a fully
  playable game: register, log in, explore, fight, level up, drops, inn, shop, maps,
  travel, heal spells, babble box, forum, help, admin panel.
- Editing any `app/**/*.lua`, `templates/**/*.html`, or app keys in `config.lua` is
  visible on the next refresh without restart.
- No SQL built from user input; every POST checks CSRF; output escaped by default.
