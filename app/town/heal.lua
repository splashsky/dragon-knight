-- town/heal.lua :: legacy heal.php healspells(): the right nav "Fast Spells" (spells usable
-- outside of fights: the heal spells), cast through their content files' code
-- (lib/action.lua) with the player as caster.
local action = require("lib.action")
local actors = require("lib.actors")
local common = require("town.common")
local game = require("lib.game")
local php = require("lib.php")
local spells = require("lib.spells")

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

	local st = game.player(user)
	local player = actors.player(st)
	local r = action.perform({
		kind = "spell", entity = spell, caster = player, target = spell.target == "self" and player or nil,
		in_fight = false, rand = php.rand,
	})
	if not r.ok then
		if r.reason == "cannot" then return common.message(req, "Error", "spell_cannot") end
		return common.message(req, "Error", "refused", { text = r.refused })
	end
	actors.apply(st, r.events)
	dk.db:exec("UPDATE users SET currenthp = ?, currentmp = ?, currenttp = ? WHERE id = ?",
						 php.mysql_uint(st.currenthp), php.mysql_uint(st.currentmp), php.mysql_uint(st.currenttp), user.id)
	return common.message(req, "Healing Spell", "spell_done", { lines = r.lines })
end

return heal
