-- routes/town.lua :: town, shop, inventory, hotbar, exploring, travel, fast heal spells,
-- character/map popups, babble box
-- Ports legacy towns.php, explore.php, heal.php and the misc index.php actions.
-- The logic lives in app/town/*.lua.
local auth = require("lib.auth")
local babble = require("town.babble")
local character = require("town.character")
local common = require("town.common")
local explore = require("town.explore")
local heal = require("town.heal")
local hotbar = require("town.hotbar")
local inn = require("town.inn")
local inventory = require("town.inventory")
local maps = require("town.maps")
local shop = require("town.shop")
local travel = require("town.travel")
local view = require("lib.view")

local game_ok, not_fighting = auth.game, common.not_fighting

return function(r)
	r:route({ "GET", "POST" }, "/inn", game_ok, not_fighting, inn.handle)

	r:get("/shop", game_ok, not_fighting, shop.list)
	r:get("/shop/buy/#id", game_ok, not_fighting, shop.confirm)
	r:post("/shop/buy/#id", game_ok, not_fighting, shop.buy)
	r:post("/shop/sell/#id", game_ok, not_fighting, shop.sell)

	r:get("/inventory", game_ok, not_fighting, inventory.show)
	r:post("/inventory/equip/#id", game_ok, not_fighting, inventory.equip)
	r:post("/inventory/unequip/:slot", game_ok, not_fighting, inventory.unequip)
	r:post("/inventory/use/#id", game_ok, not_fighting, inventory.use)
	r:get("/inventory/discard/#id", game_ok, not_fighting, inventory.discard_confirm)
	r:post("/inventory/discard/#id", game_ok, not_fighting, inventory.discard)

	r:get("/hotbar", game_ok, not_fighting, hotbar.show)
	r:post("/hotbar", game_ok, not_fighting, hotbar.save)

	r:get("/maps", game_ok, not_fighting, maps.list)
	r:get("/maps/buy/#id", game_ok, not_fighting, maps.confirm)
	r:post("/maps/buy/#id", game_ok, not_fighting, maps.buy)

	r:post("/travel/#id", game_ok, travel.handle)
	r:post("/move", game_ok, explore.move)
	r:post("/spell/#id", game_ok, heal.cast)

	r:get("/character", game_ok, character.show)
	r:get("/character/#id", game_ok, character.online)
	r:get("/map", game_ok, character.map)
	r:get("/map/sky", game_ok, character.sky)
	r:get("/map/sky/data", game_ok, character.sky_data)

	r:get("/babble", game_ok, babble.show)
	r:post("/babble", game_ok, babble.post)
	r:post("/babble/#id/delete", game_ok, babble.delete)

	r:get("/ninja", game_ok, function() return view.redirect("http://www.se7enet.com/img/shirtninja.jpg") end)
end
