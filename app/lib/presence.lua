-- presence.lua :: who's online, kept live (docs/APP.md "Presence").
--
-- A player is online while they have an open event stream (GET /live) or made a request
-- within presence.window() seconds (10 minutes). users.online = 1 marks the players
-- announced as online: the first authenticated request of a player who isn't marked
-- publishes `join` on the `presence` channel; a sweep, at most once per
-- presence.sweep_interval() seconds (1 minute) and run by whichever request comes first
-- after that (meta.presence_sweep holds the time of the last one), publishes `leave` for
-- marked players without a stream and without a request in the window. The who's-online
-- list and count are the marked players, so they always agree with the events. Event
-- data: { id, name, online } (online: the count after the change).
local json = require("lib.json")

local presence = {}

presence.CHANNEL = "presence"
presence.WINDOW = 600     -- seconds since the last request (config online_seconds)
presence.SWEEP = 60       -- seconds between sweeps (config presence_sweep_seconds)
presence.META = "presence_sweep"
presence.SWEEP_MAX = 40   -- leave events per request

local function config_seconds(key, default)
	local n = math.tointeger(tonumber(dk.config[key]))
	if not n or n < 1 then return default end
	return n
end

function presence.window()
	return config_seconds("online_seconds", presence.WINDOW)
end

function presence.sweep_interval()
	return config_seconds("presence_sweep_seconds", presence.SWEEP)
end

-- Whether user `id` has an event stream open (its user:<id> channel has a subscriber).
function presence.streaming(id)
	return dk.subscribers("user:" .. id) > 0
end

-- Both read the partial index users_online (only the players online; tests/lua/test_chat.lua
-- checks the query plans): every game page shows the count.
presence.COUNT_SQL = "SELECT count(*) FROM users WHERE online = 1"
presence.LIST_SQL = "SELECT id, charname FROM users WHERE online = 1 ORDER BY charname, id"
presence.SHOWN = 50       -- names listed in the who's-online box; /online lists everyone

function presence.count()
	return dk.db:value(presence.COUNT_SQL)
end

-- The players online (id, charname), by name; at most `limit` of them when given.
function presence.list(limit)
	if limit then return dk.db:query(presence.LIST_SQL .. " LIMIT ?", limit) end
	return dk.db:query(presence.LIST_SQL)
end

local function publish(event, id, name)
	dk.publish(presence.CHANNEL, event, json.encode({ id = id, name = name, online = presence.count() }))
end

-- An authenticated request by `user` (session.load): updates onlinetime and announces
-- the player when they weren't online.
function presence.touch(user, now)
	if user.online == 1 then
		dk.db:exec("UPDATE users SET onlinetime = ? WHERE id = ?", now, user.id)
	else
		dk.db:exec("UPDATE users SET onlinetime = ?, online = 1 WHERE id = ?", now, user.id)
		user.online = 1
		publish("join", user.id, user.charname)
	end
	user.onlinetime = now
end

-- The departures sweep, when one is due (main.lua calls this on every request).
function presence.sweep(now)
	now = now or dk.now()
	local last = math.tointeger(tonumber(dk.db:value("SELECT value FROM meta WHERE key = ?", presence.META)))
	if last and now - last < presence.sweep_interval() and now >= last then return end
	dk.db:exec("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
						 presence.META, tostring(now))
	local idle = dk.db:query("SELECT id, charname FROM users WHERE online = 1 AND onlinetime < ? ORDER BY id",
													 now - presence.window())
	local left = 0
	for _, u in ipairs(idle) do
		if not presence.streaming(u.id) then
			if left == presence.SWEEP_MAX then
				-- the rest go in the next request's sweep (dk.publish allows 256 per request)
				dk.db:exec("DELETE FROM meta WHERE key = ?", presence.META)
				return
			end
			dk.db:exec("UPDATE users SET online = 0 WHERE id = ?", u.id)
			publish("leave", u.id, u.charname)
			left = left + 1
		end
	end
end

return presence
