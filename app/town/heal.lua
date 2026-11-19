-- town/heal.lua :: legacy heal.php healspells(): the right nav "Fast Spells" (spells usable
-- outside of fights: the heal spells), cast through the effects engine (lib/effects.lua).
local common = require("town.common")
local effects = require("lib.effects")
local game = require("lib.game")
local php = require("lib.php")
local spells = require("lib.spells")

local heal = {}

-- effects.refusal() -> message key (templates/town/message.html)
local REFUSED = { hp_full = "spell_full", mp_full = "spell_full_mp", tp_full = "spell_full_tp" }

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
	local refused = effects.refusal(spell.effects, { player = st, in_fight = false })
	if refused then return common.message(req, "Error", REFUSED[refused] or "spell_not_heal") end

	local lines = effects.apply(spell.effects, {
		player = st, in_fight = false, intro = "You have cast the " .. spell.name .. " spell",
	})
	dk.db:exec("UPDATE users SET currenthp = ?, currentmp = ?, currenttp = ? WHERE id = ?",
						 php.mysql_uint(st.currenthp), php.mysql_uint(st.currentmp - spell.mp),
						 php.mysql_uint(st.currenttp), user.id)
	return common.message(req, "Healing Spell", "spell_done", { lines = lines })
end

return heal
