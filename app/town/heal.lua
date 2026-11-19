-- town/heal.lua :: legacy heal.php healspells(): the right nav "Fast Spells" (heal spells
-- cast outside of fights).
local common = require("town.common")
local php = require("lib.php")

local heal = {}

-- POST /spell/#id
function heal.cast(req, params)
  local user, id = req.user, params.id
  local spell = dk.db:first("SELECT * FROM spells WHERE id = ?", id)

  -- same checks, same order as legacy
  if not php.in_list(user.spells, id) then return common.message(req, "Error", "spell_unknown") end
  if not spell or spell.type ~= 1 then return common.message(req, "Error", "spell_not_heal") end
  if user.currentmp < spell.mp then return common.message(req, "Error", "spell_no_mp") end
  if user.currentaction == "Fighting" then return common.message(req, "Error", "spell_fighting") end
  if user.currenthp >= user.maxhp then return common.message(req, "Error", "spell_full") end

  local gained = spell.attribute
  local newhp = user.currenthp + gained
  if user.maxhp < newhp then
    gained = user.maxhp - user.currenthp
    newhp = user.maxhp
  end
  dk.db:exec("UPDATE users SET currenthp = ?, currentmp = ? WHERE id = ?",
             php.mysql_uint(newhp), php.mysql_uint(user.currentmp - spell.mp), user.id)
  return common.message(req, "Healing Spell", "spell_done", { spell = spell, gained = gained })
end

return heal
