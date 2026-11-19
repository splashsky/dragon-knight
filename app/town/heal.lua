-- town/heal.lua :: legacy heal.php healspells(): the right nav "Fast Spells" (spells usable
-- outside of fights: the heal spells), cast through their content files' code
-- (lib/action.lua) with the player as caster; statuses they apply are world statuses
-- (lib/world.lua).
local action = require("lib.action")
local common = require("town.common")
local game = require("lib.game")
local php = require("lib.php")
local spells = require("lib.spells")
local world = require("lib.world")

local heal = {}

-- POST /spell/#id
function heal.cast(req, params)
	local user, id = req.user, params.id

	-- same checks, same order as legacy
	if not spells.knows(user, id) then return common.message(req, "Error", "spell_unknown") end
	local spell = spells.get(id)
	if not spell or not spells.usable(spell, "town") then return common.message(req, "Error", "spell_not_heal") end
	if user.currentmp < spell.mp then return common.message(req, "Error", "spell_no_mp") end
	if user.currentaction == "Fighting" then return common.message(req, "Error", "spell_fighting") end

	local f = world.load(user, game.player(user), php.rand)
	local player = world.player(f)
	local r = action.perform({
		kind = "spell", entity = spell, caster = player, target = spell.target == "self" and player or nil,
		in_fight = false, rand = php.rand,
	})
	if not r.ok then
		if r.reason == "cannot" then return common.message(req, "Error", "spell_cannot") end
		return common.message(req, "Error", "refused", { text = r.refused })
	end
	return common.message(req, "Healing Spell", "spell_done", { lines = world.apply(f, r) })
end

return heal
