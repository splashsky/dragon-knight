-- town/maps.lua :: legacy towns.php maps() / maps2() / maps3(): buy a town's map
-- (adds it to users.towns, i.e. the Towns box). The maps are on sale in the market (3.1:
-- town/shop.lua, GET /shop); a town sells only the maps of town_maps (lib/game.lua).
local common = require("town.common")
local game = require("lib.game")
local php = require("lib.php")
local view = require("lib.view")

local maps = {}

-- Legacy maps2/maps3 accepted any id from anywhere: require being in a town that sells the
-- map, of a town that exists and isn't mapped yet (the market never links those).
local function check(req, id)
	local here = common.town_here(req)
	if not here then return nil, common.cheat(req) end
	local town = game.town(id)
	if not town or php.in_list(req.user.towns, town.id) or not game.sells_map(here.id, town.id) then
		return nil, common.cheat(req)
	end
	if req.user.gold < town.mapprice then return nil, common.message(req, "Buy Maps", "maps_poor") end
	return town
end

-- GET /maps: the map store is the market's (3.1): old links land there.
function maps.list(req)
	if not common.town_here(req) then return common.cheat(req) end
	return view.redirect("/shop")
end

-- GET /maps/buy/#id
function maps.confirm(req, params)
	local town, err = check(req, params.id)
	if not town then return err end
	return view.page(req, "Buy Maps", "town/maps_buy", { town = town })
end

-- POST /maps/buy/#id
function maps.buy(req, params)
	if req.form.cancel ~= nil then return view.redirect("/shop") end
	local town, err = check(req, params.id)
	if not town then return err end
	local user = req.user
	dk.db:exec("UPDATE users SET towns = ?, gold = ? WHERE id = ?",
						 user.towns .. "," .. town.id, user.gold - town.mapprice, user.id)
	return common.message(req, "Buy Maps", "maps_done")
end

return maps
