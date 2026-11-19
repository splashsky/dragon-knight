-- game.lua :: shared game data helpers (control row, towns, spells, nav data, ...).
-- Module state lives for one request only (fresh VM per request).
local classes = require("lib.classes")
local php = require("lib.php")

local game = {}

game.ONLINE_SECONDS = 600   -- "Who's Online": last 10 minutes

local cache = {}

-- The control row (id 1), cached for the request. Call game.reload_control() after
-- updating it.
function game.control()
	if not cache.control then
		cache.control = dk.db:first("SELECT * FROM control WHERE id = 1") or
			{ id = 1, gamename = "Dragon Knight", gamesize = 250, gameopen = 1, forumtype = 0,
				forumaddress = "", verifyemail = 0, shownews = 0, showbabble = 0, showonline = 0, gameurl = "",
				adminemail = "" }
	end
	return cache.control
end

function game.reload_control()
	cache.control = nil
	return game.control()
end

function game.user(id)
	return dk.db:first("SELECT * FROM users WHERE id = ?", id)
end

-- Town at a map position (or nil).
function game.town_at(latitude, longitude)
	return dk.db:first("SELECT * FROM towns WHERE latitude = ? AND longitude = ? ORDER BY id LIMIT 1",
										 latitude, longitude)
end

-- Town the user is standing in (by coordinates, regardless of currentaction) or nil.
function game.current_town(user)
	return game.town_at(user.latitude, user.longitude)
end

-- Class name for a users.charclass value (nil for an unknown class, like legacy).
function game.class_name(n)
	return classes.name(n)
end

-- Spells the user knows (users.spells comma list), ordered by id; optional type filter
-- (1 = heal, 2 = hurt, 3 = sleep, 4 = uber attack, 5 = uber defense).
function game.user_spells(user, spell_type)
	local out = {}
	for _, s in ipairs(dk.db:query("SELECT * FROM spells ORDER BY id")) do
		if (spell_type == nil or s.type == spell_type) and php.in_list(user.spells, s.id) then
			out[#out + 1] = s
		end
	end
	return out
end

-- Towns on the user's map (users.towns comma list), ordered by id.
function game.user_towns(user)
	local out = {}
	for _, t in ipairs(dk.db:query("SELECT * FROM towns ORDER BY id")) do
		if php.in_list(user.towns, t.id) then out[#out + 1] = t end
	end
	return out
end

-- 5 -> "5N", -5 -> "5S"; longitude: "E"/"W" (legacy display()).
function game.latitude_str(lat)
	if lat < 0 then return (-lat) .. "S" end
	return lat .. "N"
end

function game.longitude_str(lon)
	if lon < 0 then return (-lon) .. "W" end
	return lon .. "E"
end

-- Stat bar: pct = ceil(cur / max * 100) (0 when max == 0), color by thresholds 66/33.
function game.statbar(cur, max)
	local pct = 0
	if max ~= 0 then pct = php.ceil(cur / max * 100) end
	local color = pct >= 66 and "green" or pct >= 33 and "yellow" or "red"
	local h = math.max(0, math.min(100, pct))
	return { pct = pct, height = h, color = color }
end

-- "Low" numbers blink in the right nav: cur <= max / 5.
function game.is_low(cur, max)
	return cur <= max / 5
end

-- Forum link for the Functions box: nil, "/forum", or the external address.
function game.forum_link()
	local c = game.control()
	if c.forumtype == 1 then return "/forum" end
	if c.forumtype == 2 then
		local addr = tostring(c.forumaddress or "")
		if addr:find("^https?://") then return addr end
	end
	return nil
end

function game.online_users()
	return dk.db:query("SELECT id, charname FROM users WHERE onlinetime >= ? ORDER BY charname",
										 dk.now() - game.ONLINE_SECONDS)
end

-- Everything layout/nav_left + layout/nav_right need (port of legacy display()).
function game.nav(user)
	local town = user.currentaction == "In Town" and game.current_town(user) or nil
	local hpbar = game.statbar(user.currenthp, user.maxhp)
	local mpbar = game.statbar(user.currentmp, user.maxmp)
	local tpbar = game.statbar(user.currenttp, user.maxtp)
	return {
		user = user,
		latitude = game.latitude_str(user.latitude),
		longitude = game.longitude_str(user.longitude),
		town = town,
		towns = game.user_towns(user),
		forum = game.forum_link(),
		is_admin = user.authlevel == 1,
		experience = php.number_format(user.experience),
		gold = php.number_format(user.gold),
		hp_low = game.is_low(user.currenthp, user.maxhp),
		mp_low = game.is_low(user.currentmp, user.maxmp),
		bars = { hpbar, mpbar, tpbar },
		spells = game.user_spells(user, 1),
	}
end

return game
