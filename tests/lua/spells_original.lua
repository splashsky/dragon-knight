-- tests/lua/spells_original.lua :: the original spells and consumables as the effects
-- engine ran them (tests/lua/effects_original.lua, frozen) with the refusal texts of the
-- old fight and town code (up to schema 6). Shared by test_action.lua and test_round.lua.
local original = require("tests.effects_original")

local M = {}

-- The original spells and consumables as effect lists (the content files up to schema 6).
M.ORIGINAL = {
	spells = {
		heal = { "heal_hp", "amount", 10 }, revive = { "heal_hp", "amount", 25 }, life = { "heal_hp", "amount", 50 },
		breath = { "heal_hp", "amount", 100 }, gaia = { "heal_hp", "amount", 150 }, hurt = { "damage", "max", 15 },
		pain = { "damage", "max", 35 }, maim = { "damage", "max", 70 }, rend = { "damage", "max", 100 },
		chaos = { "damage", "max", 130 }, sleep = { "sleep", "chance", 5 }, dream = { "sleep", "chance", 9 },
		nightmare = { "sleep", "chance", 13 }, craze = { "buff_attack_pct", "pct", 10 },
		rage = { "buff_attack_pct", "pct", 25 }, fury = { "buff_attack_pct", "pct", 50 },
		ward = { "buff_defense_pct", "pct", 10 }, fend = { "buff_defense_pct", "pct", 25 },
		barrier = { "buff_defense_pct", "pct", 50 },
	},
	items = { herb = { "heal_hp", "amount", 30 }, potion = { "heal_hp", "amount", 100 }, ether = { "heal_mp", "amount", 30 } },
}

function M.effect_list(spec)
	return { { kind = spec[1], [spec[2]] = spec[3] } }
end

-- What the old code said about refusals (fight/combat.lua, town/heal.lua + its template,
-- town/inventory.lua, up to schema 6).
M.OLD_FIGHT = {
	hp_full = "Your Hit Points are already full. Please go back and try again.",
	mp_full = "Your Magic Points are already full. Please go back and try again.",
	tp_full = "Your Travel Points are already full. Please go back and try again.",
}
M.OLD_TOWN_SPELL = {
	hp_full = "Your Hit Points are already full. You don't need to use a Healing spell now.",
	mp_full = "Your Magic Points are already full. You don't need to use this spell now.",
}
M.OLD_TOWN_ITEM = {
	hp_full = "Your Hit Points are already full. You don't need to use the %s now.",
	mp_full = "Your Magic Points are already full. You don't need to use the %s now.",
}
M.CANNOT = {
	spell = "This spell cannot be cast. Please go back and try again.",
	item = "This item cannot be used. Please go back and try again.",
}

-- The old path: effects.refusal + effects.apply (+ the MP cost for spells) on the users
-- row copy that held the fight. Returns { lines, killed } or { refused }.
function M.run(kind, entity, st, rand, in_fight)
	local spec = M.ORIGINAL[kind == "spell" and "spells" or "items"][entity.key]
	local list = M.effect_list(spec)
	local refused = original.refusal(list, { player = st, in_fight = in_fight })
	if refused then
		if in_fight then
			return { refused = M.OLD_FIGHT[refused] or M.CANNOT[kind] }
		elseif kind == "spell" then
			return { refused = M.OLD_TOWN_SPELL[refused] or "?" }
		end
		return { refused = (M.OLD_TOWN_ITEM[refused] or "?"):format(entity.name) }
	end
	local intro = kind == "spell" and ("You have cast the " .. entity.name .. " spell") or ("You have used the " .. entity.name)
	local lines = original.apply(list, { player = st, in_fight = in_fight, rand = rand, intro = intro })
	if kind == "spell" then st.currentmp = st.currentmp - entity.mp end
	return { lines = lines, killed = (st.currentmonsterhp or 1) <= 0 }
end

return M
