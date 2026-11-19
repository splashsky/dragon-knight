-- view.lua :: rendering, the template helper table `h`, layouts and responses.
local csrf = require("lib.csrf")
local dbcount = require("lib.dbcount")
local game = require("lib.game")
local php = require("lib.php")

local view = {}

view.GAME_VERSION = "1.1.11"
view.BUILD = "C/Lua"

-- Base helpers. Templates see these after ctx (names resolve scratch -> ctx -> h).
-- Helpers returning HTML (include, csrf_field, nl2br) must be output with {{{ }}}.
local base = {
  escape = dk.html,
  ipairs = ipairs, pairs = pairs, next = next, select = select, type = type,
  tostring = tostring, tonumber = tonumber, string = string, table = table, math = math,
  utf8 = utf8, os = { date = os.date, time = os.time }, dk = dk, php = php,
  number = php.number_format,
  date = php.prettydate,
  datetime = php.datetime,
}

function base.nl2br(s)
  return php.nl2br(dk.html(s))
end

-- url("/shop/buy", 3) -> "/shop/buy/3"; a trailing table becomes the query string:
-- url("/forum/thread", 7, { start = 15 }) -> "/forum/thread/7?start=15"
function base.url(path, ...)
  local parts, n = { path }, select("#", ...)
  local query
  for i = 1, n do
    local v = select(i, ...)
    if i == n and type(v) == "table" then
      query = v
    else
      parts[#parts + 1] = dk.urlencode(tostring(v))
    end
  end
  local s = table.concat(parts, "/")
  if query then
    local keys = {}
    for k in pairs(query) do keys[#keys + 1] = k end
    table.sort(keys)
    local q = {}
    for _, k in ipairs(keys) do
      q[#q + 1] = dk.urlencode(tostring(k)) .. "=" .. dk.urlencode(tostring(query[k]))
    end
    if #q > 0 then s = s .. "?" .. table.concat(q, "&") end
  end
  return s
end

view.helpers = base

-- Renders templates/<name>.html with ctx. Per-render helpers: include(name [, ctx])
-- (defaults to this ctx), csrf_field(), csrf_token(), req.
function view.render(name, ctx, req)
  ctx = ctx or {}
  local h = setmetatable({ req = req }, { __index = base })
  function h.include(n, c) return view.render(n, c or ctx, req) end
  function h.csrf_field() return csrf.field(req) end
  function h.csrf_token() return csrf.token(req) end
  return dk.render(name, ctx, h)
end

local function html_response(body, status, extra_headers)
  local headers = {
    { "Content-Type", "text/html; charset=utf-8" },
    { "Cache-Control", "private, no-cache" },
  }
  for _, hd in ipairs(extra_headers or {}) do headers[#headers + 1] = hd end
  return { status = status or 200, headers = headers, body = body }
end

function view.elapsed()
  return string.format("%.4f", dk.clock() - dk.request_start)
end

-- Wraps already-rendered HTML in a layout.
-- opts: nav (default: logged in), layout ("main" | "minimal" | any templates/layout/<x>),
--       body_class (extra class(es) on <body>, for page-specific CSS),
--       status, headers (extra {name, value} pairs).
function view.layout(req, title, content, opts)
  opts = opts or {}
  local user = req.user
  local nav = opts.nav
  if nav == nil then nav = user ~= nil end
  if nav and user then
    -- re-read the user row: the handler may have just changed it (legacy display() did too)
    user = game.user(user.id) or user
    req.user = user
  end
  local ctx = {
    title = title,
    content = content,
    body_class = opts.body_class,
    gamename = game.control().gamename,
    nav = (nav and user) and game.nav(user) or nil,
    logged_in = user ~= nil,
    version = view.GAME_VERSION,
    build = view.BUILD,
    elapsed = view.elapsed,
    queries = dbcount.count,
  }
  local body = view.render("layout/" .. (opts.layout or "main"), ctx, req)
  return html_response(body, opts.status, opts.headers)
end

-- The usual page: render templates/<template>.html with ctx, then the layout.
function view.page(req, title, template, ctx, opts)
  return view.layout(req, title, view.render(template, ctx, req), opts)
end

-- A page whose content is a trusted HTML snippet (legacy display("text...")).
-- Escape any user data you interpolate with dk.html().
function view.message(req, title, html, opts)
  return view.layout(req, title, html, opts)
end

-- Error page with a plain-text message (escaped).
function view.error(req, status, title, message, opts)
  opts = opts or {}
  opts.status = status
  return view.page(req, title, "errors/error", { heading = title, message = message, status = status }, opts)
end

function view.not_found(req)
  return view.error(req, 404, "Not Found", "The page you requested does not exist.")
end

function view.method_not_allowed(req, allowed)
  return view.error(req, 405, "Method Not Allowed",
    "That action can't be performed this way. Please go back and use the buttons on the page.",
    { headers = { { "Allow", allowed } } })
end

function view.csrf_failed(req)
  return view.error(req, 403, "Error",
    "Your form has expired or is invalid. Please go back, reload the page and try again.")
end

function view.redirect(url, status)
  return { status = status or 302, headers = { { "Location", url } }, body = "" }
end

function view.text(body, status)
  return { status = status or 200, headers = { { "Content-Type", "text/plain; charset=utf-8" } },
           body = body }
end

-- 500 page; must not depend on the DB or other templates working.
function view.server_error(req, err)
  local detail = dk.config.dev and err or nil
  local ok, body = pcall(view.render, "errors/500", { detail = detail }, req)
  if not ok then
    body = "<!doctype html><title>Error</title><h1>Internal Server Error</h1>" ..
           (detail and ("<pre>" .. dk.html(detail) .. "</pre>") or "")
  end
  return html_response(body, 500)
end

return view
