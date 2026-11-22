-- routes/tick.lua :: POST /__tick, the server's tick (lib/tick.lua; docs/APP.md "The server
-- tick"). The engine sends it on every boundary of the clock's tick (src/http.c) and marks
-- it (req.tick, which only the engine sets), so no network request can pose as it: they
-- get a 404 (a POST without a CSRF token a 403 first).
local clock = require("lib.clock")
local tick = require("lib.tick")
local view = require("lib.view")

local function run(req)
	if not req.tick then return view.not_found(req) end
	return view.text(tick.summary(tick.run(clock.now())) .. "\n")
end

return function(r)
	r:post("/__tick", run)
end
