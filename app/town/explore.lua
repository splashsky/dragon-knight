-- town/explore.lua :: legacy explore.php move(): compass buttons, 1-in-5 chance of a fight.
local game = require("lib.game")
local php = require("lib.php")
local travel = require("town.travel")
local view = require("lib.view")

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

	local town = game.town_at(lat, lon)
	if town then return travel.go(req, town.id, false) end

	if php.rand(1, 5) == 1 then
		-- /fight picks the monster when currentfight == 1
		dk.db:exec("UPDATE users SET currentaction = 'Fighting', currentfight = 1, latitude = ?, longitude = ?, dropcode = 0 WHERE id = ?",
							 lat, lon, user.id)
		return view.redirect("/fight")
	end
	dk.db:exec("UPDATE users SET currentaction = 'Exploring', latitude = ?, longitude = ?, dropcode = 0 WHERE id = ?",
						 lat, lon, user.id)
	return view.redirect("/")
end

return explore
