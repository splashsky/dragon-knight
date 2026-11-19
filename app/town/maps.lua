-- town/maps.lua :: legacy towns.php maps() / maps2() / maps3(): buy a town's map
-- (adds it to users.towns, i.e. the Travel To list).
local common = require("town.common")
local game = require("lib.game")
local php = require("lib.php")
local view = require("lib.view")

local maps = {}

-- Legacy maps2/maps3 accepted any id from anywhere: require being in a town, a town
-- that exists and isn't mapped yet (the list never links those).
local function check(req, id)
  if not common.town_here(req) then return nil, common.cheat(req) end
  local town = dk.db:first("SELECT * FROM towns WHERE id = ?", id)
  if not town or php.in_list(req.user.towns, town.id) then return nil, common.cheat(req) end
  if req.user.gold < town.mapprice then return nil, common.message(req, "Buy Maps", "maps_poor") end
  return town
end

-- GET /maps
function maps.list(req)
  if not common.town_here(req) then return common.cheat(req) end
  local towns = {}
  for _, t in ipairs(dk.db:query("SELECT * FROM towns ORDER BY id")) do
    towns[#towns + 1] = {
      town = t,
      mapped = php.in_list(req.user.towns, t.id),
      latitude = game.latitude_str(t.latitude),
      longitude = game.longitude_str(t.longitude),
    }
  end
  return view.page(req, "Buy Maps", "town/maps", { towns = towns })
end

-- GET /maps/buy/#id
function maps.confirm(req, params)
  local town, err = check(req, params.id)
  if not town then return err end
  return view.page(req, "Buy Maps", "town/maps_buy", { town = town })
end

-- POST /maps/buy/#id
function maps.buy(req, params)
  if req.form.cancel ~= nil then return view.redirect("/") end
  local town, err = check(req, params.id)
  if not town then return err end
  local user = req.user
  dk.db:exec("UPDATE users SET towns = ?, gold = ? WHERE id = ?",
             user.towns .. "," .. town.id, user.gold - town.mapprice, user.id)
  return common.message(req, "Buy Maps", "maps_done")
end

return maps
