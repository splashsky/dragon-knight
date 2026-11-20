-- routes/test.lua :: routes for the end-to-end tests, answering 404 unless the config has
-- `test_routes = true` (tests/run.sh's config does; so does POST /__test/publish in
-- routes/live.lua).
--
--   GET  /__test/routes     every route, one "<METHOD> <pattern>" per line, sorted
--                           (tests/e2e/pure.sh checks it requests every GET route)
--   POST /__test/encounter  an encounter begins for the caller where they stand, as a map
--                           move's 1-in-5 begins one (tests/run.sh t_fight_new)
local auth = require("lib.auth")
local encounter = require("fight.encounter")
local state = require("fight.state")
local view = require("lib.view")

local function enabled() return dk.config.test_routes == true end

local function routes(req)
	if not enabled() then return view.not_found(req) end
	local r, lines = require("routes"), {}
	for pattern, by_method in pairs(r.exact) do
		for method in pairs(by_method) do lines[#lines + 1] = method .. " " .. pattern end
	end
	for _, rt in ipairs(r.routes) do lines[#lines + 1] = rt.method .. " " .. rt.pattern end
	table.sort(lines)
	return view.text(table.concat(lines, "\n") .. "\n")
end

local function begin_encounter(req)
	if not enabled() then return view.not_found(req) end
	local user = req.user
	state.clear(user.id)
	dk.db:exec("UPDATE users SET currentaction = 'Fighting', dropcode = 0 WHERE id = ?", user.id)
	if not encounter.begin(user.id) then
		return view.error(req, 500, "Error", "There are no monsters in this area.")
	end
	return view.redirect("/fight")
end

return function(r)
	r:get("/__test/routes", routes)
	r:post("/__test/encounter", auth.game, begin_encounter)
end
