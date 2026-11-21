-- town/explore.lua :: legacy explore.php move(): compass buttons, 1-in-5 chance of a fight
-- (it begins here: fight/encounter.lua). Each move is a turn for the world statuses
-- (lib/world.lua). Setting out from a town, arriving in one (town/travel.lua) and a fight
-- beginning are scenes for the live client (lib/scene.lua).
local encounter = require("fight.encounter")
local game = require("lib.game")
local php = require("lib.php")
local scene = require("lib.scene")
local state = require("fight.state")
local travel = require("town.travel")
local view = require("lib.view")
local world = require("lib.world")

local explore = {}

-- POST /move (button name north / south / east / west; several at once all apply, and
-- none at all stays put but still rolls for a fight -- both as legacy).
function explore.move(req)
	local user = req.user
	if user.currentaction == "Fighting" then return view.redirect("/fight") end

	local size = game.control().gamesize
	local form = req.form
	local lat, lon = user.latitude, user.longitude
	if form.north ~= nil then lat = lat + 1; if lat > size then lat = size end end
	if form.south ~= nil then lat = lat - 1; if lat < -size then lat = -size end end
	if form.east ~= nil then lon = lon + 1; if lon > size then lon = size end end
	if form.west ~= nil then lon = lon - 1; if lon < -size then lon = -size end end
	local leaving = user.currentaction == "In Town" and game.current_town(user) or nil

	world.move(user, php.rand)
	-- moving on: the page of the last finished fight goes
	state.forget(user.id)

	local town = game.town_at(lat, lon)
	if town then return travel.go(req, town.id, false) end

	if php.rand(1, 5) == 1 then
		-- the encounter begins here: the monster is picked, its first strike played
		-- (fight/encounter.lua); with no monster to meet the move is an ordinary one
		dk.db:exec("UPDATE users SET currentaction = 'Fighting', latitude = ?, longitude = ?, dropcode = 0 WHERE id = ?",
							 lat, lon, user.id)
		local outcome, monster = encounter.begin(user.id)
		if outcome == "death" then
			return scene.add(req, view.redirect("/fight"), "death", "You have died",
				"The " .. monster.name .. " struck before you could raise your weapon.")
		elseif outcome then
			return scene.add(req, view.redirect("/fight"), "fight", "Fight!", "A " .. monster.name .. " blocks your way.")
		end
	end
	dk.db:exec("UPDATE users SET currentaction = 'Exploring', latitude = ?, longitude = ?, dropcode = 0 WHERE id = ?",
						 lat, lon, user.id)
	if leaving then
		return scene.add(req, view.redirect("/"), "explore", "Exploring", "You leave " .. leaving.name .. " behind.")
	end
	return view.redirect("/")
end

return explore
