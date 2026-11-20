-- town/travel.lua :: legacy towns.php travelto($id, $usepoints): Travel To menu (costs TP,
-- town must be on your map) and arriving by walking onto a town (explore.lua, free).
local common = require("town.common")
local php = require("lib.php")
local state = require("fight.state")
local view = require("lib.view")

local travel = {}

function travel.go(req, id, usepoints)
	local user = req.user
	if user.currentaction == "Fighting" then return view.redirect("/fight") end

	local town = dk.db:first("SELECT * FROM towns WHERE id = ?", id)
	if not town then return common.cheat(req) end   -- legacy travelled to (null, null)
	if usepoints then
		if user.currenttp < town.travelpoints then return common.message(req, "Travel To", "travel_tp") end
		if not php.in_list(user.towns, id) then return common.cheat(req) end
	end
	if user.latitude == town.latitude and user.longitude == town.longitude then
		return common.message(req, "Travel To", "travel_here")
	end

	-- moving on: the page of the last finished fight goes
	state.forget(user.id)
	local newtp = user.currenttp
	if usepoints then newtp = newtp - town.travelpoints end
	-- arriving by exploring puts the town on your map
	local towns = user.towns
	if not php.in_list(towns, id) then towns = towns .. "," .. id end

	dk.db:exec("UPDATE users SET currentaction = 'In Town', towns = ?, currenttp = ?, latitude = ?, longitude = ? WHERE id = ?",
						 towns, newtp, town.latitude, town.longitude, user.id)
	return common.message(req, "Travel To", "travel_done", { town = town })
end

-- POST /travel/#id
function travel.handle(req, params)
	return travel.go(req, params.id, true)
end

return travel
