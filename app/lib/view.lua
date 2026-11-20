-- view.lua :: rendering, the template helper table `h`, layouts and responses.
local banner = require("lib.banner")
local chat = require("lib.chat")
local csrf = require("lib.csrf")
local dbcount = require("lib.dbcount")
local game = require("lib.game")
local json = require("lib.json")
local php = require("lib.php")
local presence = require("lib.presence")
local session = require("lib.session")
local themes = require("lib.themes")
local tips = require("lib.tips")

local view = {}

view.GAME_VERSION = "2.4.0-dev"
view.BUILD = "C/Lua"

-- Base helpers. Templates see these after ctx (names resolve scratch -> ctx -> h).
-- Helpers returning HTML (include, csrf_field, nl2br, paragraphs, tip) must be output with
-- {{{ }}}.
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

-- Text as HTML paragraphs (lore): escaped; a blank line starts a new <p>, and the lines of
-- a paragraph are joined with spaces (so content files can wrap long text). "" for blank
-- text.
function base.paragraphs(s)
	local out = {}
	s = tostring(s or ""):gsub("\r\n?", "\n")
	for lines in (s .. "\n\n"):gmatch("(.-)\n[ \t]*\n%s*") do
		local para = lines:gsub("%s+", " "):match("^ ?(.-) ?$")
		if para ~= "" then out[#out + 1] = "<p>" .. dk.html(para) .. "</p>" end
	end
	return table.concat(out)
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

-- This page, for forms that come back to it (`back`): the path and query string, or the
-- path on a page answering a POST.
function view.back_path(req)
	local back = req.path
	if req.method == "GET" or req.method == "HEAD" then back = req.target or back end
	return themes.safe_path(back) or "/"
end

-- Where a form with a `back` field returns to: that page when it is a same-site path with
-- a GET route, else `fallback` (default "/").
function view.back_to(req, fallback)
	local back = themes.safe_path(req.form.back)
	if back and require("routes"):match("GET", back:match("^[^?#]*")) then return back end
	return fallback or "/"
end

-- The theme selector (a POST form to /theme), returning to this page.
local function theme_picker(req)
	return view.render("layout/theme_picker", {
		themes = themes.list,
		current = themes.current(req).key,
		back = view.back_path(req),
	}, req)
end

-- The theme's logo, linked to the game's home page; its alt text is the game's name
-- (legacy), else the theme's.
local function logo(req)
	local theme = themes.current(req)
	local name = game.control().gamename
	if name == nil or name == "" then name = theme.logo.alt end
	return view.render("layout/logo", { theme = theme, gamename = name }, req)
end

-- Renders templates/<name>.html with ctx. Per-render helpers: include(name [, ctx])
-- (defaults to this ctx), csrf_field(), csrf_token(), theme_picker(), logo(), req.
function view.render(name, ctx, req)
	ctx = ctx or {}
	local h = setmetatable({ req = req }, { __index = base })
	function h.include(n, c) return view.render(n, c or ctx, req) end
	function h.csrf_field() return csrf.field(req) end
	function h.csrf_token() return csrf.token(req) end
	function h.theme_picker() return theme_picker(req) end
	function h.logo() return logo(req) end
	-- tip("spell", row [, extra]): the tooltip content of a spell, item, monster or class
	-- (lib/tips.lua, templates/tip/tip.html; docs/APP.md "Tooltips"; extra: an item's
	-- { charges = n }) -> HTML
	function h.tip(kind, row, extra)
		if row == nil then return "" end
		local build = assert(tips[kind], "tip: unknown kind")
		return view.render("tip/tip", build(row, extra), req)
	end
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

-- The Babble Box's template ctx (layout/chat.html); nil when the chat is turned off.
function view.chat(req, large)
	if game.control().showbabble ~= 1 then return nil end
	return {
		posts = chat.history(),
		is_admin = req.user and req.user.authlevel == 1,
		back = view.back_path(req),
		large = large,
		max_chars = chat.MAX_CHARS,
	}
end

-- The who's-online box's ctx (layout/online.html); nil when it is turned off. The box lists
-- at most presence.SHOWN names (`all` lists everyone, for the /online page); the count is
-- always exact.
function view.online(all)
	if game.control().showonline ~= 1 then return nil end
	local limit = not all and presence.SHOWN or nil
	return { online = presence.list(limit), online_count = presence.count(), online_limit = limit }
end

-- The live parts of the layout (docs/APP.md "Live pages"): `live` (the page loads live.js:
-- the user is logged in) and `side` (the online count and the chat in the right column).
local function live_ctx(req, ctx, layout, nav, opts)
	local user = req.user
	if not user or layout == "minimal" then return end
	ctx.live = {
		csrf = csrf.token(req),
		session = req.session and session.live_id(req.session) or "",
		admin = user.authlevel == 1,
	}
	if not nav then return end
	local side = {}
	if game.control().showonline == 1 then side.online_count = presence.count() end
	if not opts.chat_inline then side.chat = view.chat(req, false) end
	ctx.side = side
end

-- Wraps already-rendered HTML in a layout.
-- opts: nav (default: logged in), layout ("main" | "minimal" | any templates/layout/<x>),
--       body_class (extra class(es) on <body>, for page-specific CSS; the layouts add
--       "theme-<key>"),
--       chat_inline (the page shows the chat itself: not in the right column),
--       scripts (more scripts for the page: names of public/js/<name>.js, e.g. { "fight" }),
--       status, headers (extra {name, value} pairs), vars (extra layout ctx values).
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
	local layout = opts.layout or "main"
	local ctx = {
		title = title,
		content = content,
		body_class = opts.body_class,
		theme = themes.current(req),
		gamename = game.control().gamename,
		nav = (nav and user) and game.nav(user) or nil,
		logged_in = user ~= nil,
		version = view.GAME_VERSION,
		build = view.BUILD,
		elapsed = view.elapsed,
		queries = dbcount.count,
		banner = banner.current(req),
		back = view.back_path(req),
	}
	live_ctx(req, ctx, layout, nav and user ~= nil, opts)
	ctx.scripts = opts.scripts
	for k, v in pairs(opts.vars or {}) do ctx[k] = v end
	local body = view.render("layout/" .. layout, ctx, req)
	return html_response(body, opts.status, opts.headers)
end

-- The usual page: render templates/<template>.html with ctx, then the layout.
function view.page(req, title, template, ctx, opts)
	return view.layout(req, title, view.render(template, ctx, req), opts)
end

-- The parts of the page view.page would draw, as HTML for a script to swap in (fight.js):
-- main (the middle column: templates/<template>.html with ctx), nav_left and nav_right
-- (the side columns' boxes, from the user row as it is now, like the layout). Same
-- templates as the page, so the two can't drift.
function view.fragments(req, template, ctx)
	local out = { main = view.render(template, ctx, req) }
	local user = req.user and game.user(req.user.id)
	if user then
		req.user = user
		local nav = game.nav(user)
		out.nav_left = view.render("layout/nav_left", nav, req)
		out.nav_right = view.render("layout/nav_right", nav, req)
	end
	return out
end

-- The JSON answer for a page fetched by a script: t (the route's fields) plus title, url
-- (the page's address, for history.replaceState: req.path unless t has one) and fragments
-- (view.fragments).
function view.fragment_page(req, title, template, ctx, t)
	t = t or {}
	t.title = title
	t.url = t.url or req.path
	t.fragments = view.fragments(req, template, ctx)
	return view.json(t)
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

-- A JSON answer (t: a table for lib/json.lua).
function view.json(t, status, headers)
	local hs = { { "Content-Type", "application/json; charset=utf-8" }, { "Cache-Control", "no-store" } }
	for _, hd in ipairs(headers or {}) do hs[#hs + 1] = hd end
	return { status = status or 200, headers = hs, body = json.encode(t) }
end

-- Whether the request asks for JSON (fetch from live.js: Accept: application/json).
function view.wants_json(req)
	local accept = req.headers["accept"]
	return type(accept) == "string" and accept:find("application/json", 1, true) ~= nil
end

function view.text(body, status)
	return { status = status or 200, headers = { { "Content-Type", "text/plain; charset=utf-8" } },
					 body = body }
end

-- 503 page (database not ready); like the 500 page it doesn't touch the DB.
function view.unavailable(req, message)
	local ok, body = pcall(view.render, "errors/503", { message = message, theme = themes.current(req) }, req)
	if not ok then
		body = "<!doctype html><title>Service Unavailable</title><h1>Service Unavailable</h1><p>" ..
					 dk.html(message) .. "</p>"
	end
	return html_response(body, 503, { { "Retry-After", "60" } })
end

-- 500 page; must not depend on the DB or other templates working.
function view.server_error(req, err)
	local detail = dk.config.dev and err or nil
	local ok, body = pcall(view.render, "errors/500", { detail = detail, theme = themes.current(req) }, req)
	if not ok then
		body = "<!doctype html><title>Error</title><h1>Internal Server Error</h1>" ..
					 (detail and ("<pre>" .. dk.html(detail) .. "</pre>") or "")
	end
	return html_response(body, 500)
end

return view
