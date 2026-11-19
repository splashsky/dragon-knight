-- routes/live.lua :: GET /live, the player's event stream (server-sent events; the engine
-- side is src/hub.c, see docs/APP.md "Realtime"). Which channels a stream may listen to
-- is decided here: everyone in the game gets the public channels and their own
-- user:<id>, administrators also admin.
--
-- POST /__test/publish exists only with `test_routes = true` in the config (end-to-end
-- tests and `make bench BENCH_SCENARIO=realtime`): it publishes one event for the
-- logged-in caller. Normal players never publish directly.
local auth = require("lib.auth")
local view = require("lib.view")

local live = {}

live.RETRY_MS = 3000
live.PUBLIC = { "babble", "presence", "notices" }

function live.channels(user)
	local channels = {}
	for i, name in ipairs(live.PUBLIC) do channels[i] = name end
	channels[#channels + 1] = "user:" .. user.id
	if user.authlevel == 1 then channels[#channels + 1] = "admin" end
	return channels
end

function live.stream(req)
	return { sse = { channels = live.channels(req.user), retry = live.RETRY_MS } }
end

-- form: channel, event, data; delay_ms (wait before the commit), fail=1 (error after
-- publishing: the transaction rolls back and the event is dropped)
function live.test_publish(req)
	if dk.config.test_routes ~= true then return view.not_found(req) end
	local f = req.form
	dk.publish(f.channel or "", f.event or "", f.data or "")
	local delay = math.tointeger(tonumber(f.delay_ms)) or 0
	if delay > 0 then
		local stop = dk.clock() + math.min(delay, 5000) / 1000
		while dk.clock() < stop do end
	end
	if f.fail == "1" then error("test publish: failing on purpose") end
	return view.text("published\n")
end

return function(r)
	r:get("/live", auth.game, live.stream)
	r:post("/__test/publish", auth.login, live.test_publish)
end
