-- town/character.lua :: legacy index.php showchar() (own sheet, popup), onlinechar($id)
-- (anyone's sheet, from Who's Online) and showmap().
local common = require("town.common")
local game = require("lib.game")
local php = require("lib.php")
local view = require("lib.view")

local character = {}

local function bonus(n)
  if n > 0 then return "(+" .. n .. "%)" end
  if n < 0 then return "(" .. n .. "%)" end
  return nil
end

local function sheet(user)
  local class = math.tointeger(user.charclass)
  local nextlevel
  -- legacy: "Next Level: None" already at level 99, although levels row 100 exists.
  if user.level < 99 and class and class >= 1 and class <= 3 then
    local row = game.level_row(user.level + 1)
    nextlevel = php.number_format(row and row[game.level_key(class, "exp")] or 0)
  end
  local spells = {}
  for _, s in ipairs(game.user_spells(user)) do spells[#spells + 1] = s.name end
  return {
    u = user,
    experience = php.number_format(user.experience),
    gold = php.number_format(user.gold),
    plusexp = bonus(user.expbonus),
    plusgold = bonus(user.goldbonus),
    nextlevel = nextlevel,
    charclass = game.class_name(user.charclass),
    difficulty = game.difficulty_name(user.difficulty),
    spells = spells,
  }
end

-- GET /character
function character.show(req)
  local ctx = sheet(req.user)
  ctx.full = true
  return view.page(req, "Character Information", "town/character", ctx,
                   { layout = "minimal", nav = false })
end

-- GET /character/#id
function character.online(req, params)
  local user = game.user(params.id)
  if not user then return common.message(req, "Error", "no_user") end
  return view.page(req, "Character Information", "town/onlinechar", sheet(user))
end

-- GET /map
function character.map(req)
  return view.page(req, "Map", "town/map", {}, { layout = "minimal", nav = false })
end

return character
